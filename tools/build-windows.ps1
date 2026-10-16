param(
    [ValidateSet('RelWithDebInfo', 'Release')][string]$Configuration = 'RelWithDebInfo',
    [switch]$Lto,
    [switch]$ConfigureOnly,
    [switch]$Fresh,
    [ValidateRange(1, 256)][int]$Jobs = 6,
    [string]$BuildDirectory,
    [string]$VisualStudioPath,
    [string]$LlvmPath,
    [string]$PythonExecutable = $env:PYTHON3_EXECUTABLE,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$BuildArguments
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$runtime = Join-Path $repo 'runtime'
$Configuration = if ($Configuration -ieq 'Release') { 'Release' } else { 'RelWithDebInfo' }

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
    finally { $hasher.Dispose(); $stream.Dispose() }
}

function Find-Tool([string]$Name, [string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    throw "$Name was not found. Install the required tool or add it to PATH."
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE." }
}

try {
    if (-not [Environment]::Is64BitProcess) { throw 'Run this script in 64-bit PowerShell.' }
    $git = Find-Tool 'git.exe' @()
    if (-not (Test-Path -LiteralPath (Join-Path $runtime 'CMakeLists.txt'))) {
        throw 'Runtime is missing. Run git submodule update --init --recursive.'
    }
    if (-not $VisualStudioPath) {
        $vswhere = Find-Tool 'vswhere.exe' @("${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe")
        $VisualStudioPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -ne 0 -or -not $VisualStudioPath) {
            throw 'Install Visual Studio Build Tools with Desktop development with C++ and a Windows SDK.'
        }
    }
    $devCommand = Join-Path $VisualStudioPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $devCommand)) { throw "Missing $devCommand" }
    $environmentLines = & $env:ComSpec /d /c "call `"$devCommand`" -no_logo -arch=x64 -host_arch=x64 >nul && set"
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the x64 Visual Studio environment.' }
    foreach ($line in $environmentLines) {
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
    }
    if ($LlvmPath) {
        $compiler = Join-Path $LlvmPath 'clang-cl.exe'
        if (-not (Test-Path -LiteralPath $compiler)) { throw 'LlvmPath must contain clang-cl.exe.' }
    } else {
        $compiler = Find-Tool 'clang-cl.exe' @((Join-Path $VisualStudioPath 'VC\Tools\Llvm\x64\bin\clang-cl.exe'))
    }
    $LlvmPath = Split-Path $compiler -Parent
    $env:PATH = "$LlvmPath;$env:PATH"
    $compilerInfo = & $compiler --version
    if ($LASTEXITCODE -ne 0 -or ($compilerInfo -join ' ') -notmatch 'Target: x86_64-pc-windows-msvc') {
        throw 'An x64 clang-cl targeting x86_64-pc-windows-msvc is required.'
    }
    $stream = [IO.File]::OpenRead($compiler)
    try {
        $reader = [IO.BinaryReader]::new($stream)
        $stream.Position = 0x3c
        $peOffset = $reader.ReadInt32()
        $stream.Position = $peOffset + 4
        if ($reader.ReadUInt16() -ne 0x8664) { throw 'Select the 64-bit clang-cl executable, not the x86 host compiler.' }
    } finally { $stream.Dispose() }
    $cmakeRoot = Join-Path $VisualStudioPath 'Common7\IDE\CommonExtensions\Microsoft\CMake'
    $cmake = Find-Tool 'cmake.exe' @((Join-Path $cmakeRoot 'CMake\bin\cmake.exe'))
    $ninja = Find-Tool 'ninja.exe' @((Join-Path $cmakeRoot 'Ninja\ninja.exe'))
    $linker = Find-Tool 'lld-link.exe' @((Join-Path $LlvmPath 'lld-link.exe'))
    $cmakeVersion = & $cmake --version
    if ($LASTEXITCODE -ne 0 -or ($cmakeVersion[0] -notmatch '(\d+\.\d+\.\d+)') -or [version]$matches[1] -lt [version]'3.30.0') {
        throw 'CMake 3.30 or newer is required by the presets.'
    }
    if (-not $PythonExecutable) {
        $launcher = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue
        if ($launcher) {
            $PythonExecutable = & $launcher.Source -3 -c 'import sys; print(sys.executable)' 2>$null
            if ($LASTEXITCODE -ne 0) { $PythonExecutable = $null }
        }
        if (-not $PythonExecutable) { $PythonExecutable = Find-Tool 'python.exe' @() }
    }
    Invoke-Checked $PythonExecutable @('-c', 'import sys; sys.exit(0 if sys.version_info.major == 3 else 1)')
    $PythonExecutable = (& $PythonExecutable -c 'import sys; print(sys.executable)').Trim()
    $resourceDirectory = & (Join-Path $LlvmPath 'clang.exe') -print-resource-dir
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the selected Clang resource directory.' }
    $builtinsDirectory = Join-Path $resourceDirectory 'lib\windows'
    if (-not (Test-Path -LiteralPath (Join-Path $builtinsDirectory 'clang_rt.builtins-x86_64.lib'))) {
        throw 'The selected LLVM installation is missing x64 compiler-rt builtins.'
    }
    $env:LIB = "$builtinsDirectory;$env:LIB"
    $preset = "x64-Clang-$Configuration"
    if (-not $BuildDirectory) {
        $suffix = if ($Lto) { '-lto' } else { '' }
        $BuildDirectory = Join-Path $runtime "Build\w1-$preset$suffix"
    }
    $BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
    $ipo = if ($Lto) { 'ON' } else { 'OFF' }
    $arguments = @('--preset', $preset, '-S', $runtime, '-B', $BuildDirectory,
        "-DCMAKE_C_COMPILER=$compiler", "-DCMAKE_CXX_COMPILER=$compiler", "-DCMAKE_ASM_COMPILER=$compiler",
        "-DCMAKE_MAKE_PROGRAM=$ninja", "-DCMAKE_LINKER=$linker", "-DPython3_EXECUTABLE=$PythonExecutable",
        '-DHAVE_ENDIAN_H=0', '-DENABLE_TESTS=OFF', "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$ipo",
        "-DCMAKE_INTERPROCEDURAL_OPTIMIZATION_$($Configuration.ToUpperInvariant())=$ipo")
    if ($Fresh) { $arguments += '--fresh' }
    Write-Host "Compiler: $compiler"
    Write-Host ($compilerInfo -join [Environment]::NewLine)
    Write-Host "Python: $PythonExecutable"
    Write-Host "Build: $BuildDirectory (LTO: $ipo)"
    Push-Location $runtime
    try { Invoke-Checked $cmake $arguments } finally { Pop-Location }
    if ($ConfigureOnly) { exit 0 }
    Invoke-Checked $cmake (@('--build', $BuildDirectory, '--parallel', "$Jobs") + $BuildArguments)
    if (-not (Test-Path -LiteralPath (Join-Path $BuildDirectory 'shadps4.exe'))) { throw 'Build did not produce the emulator executable.' }
    $mainCommit = & $git -C $repo rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record main commit.' }
    $runtimeCommit = & $git -C $runtime rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record runtime commit.' }
    $mainChanges = @(& $git -C $repo status --porcelain --ignore-submodules)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record main working-tree state.' }
    $runtimeChanges = @(& $git -C $runtime status --porcelain)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record runtime working-tree state.' }
    [ordered]@{
        mainCommit = $mainCommit; runtimeCommit = $runtimeCommit
        mainChanges = $mainChanges; runtimeChanges = $runtimeChanges
        configuration = $Configuration; lto = [bool]$Lto
        compiler = $compilerInfo; builtAtUtc = [DateTime]::UtcNow.ToString('o')
        executableSha256 = (Get-Sha256 (Join-Path $BuildDirectory 'shadps4.exe'))
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $BuildDirectory 'build-info.json') -Encoding UTF8
    Write-Host "Emulator built: $BuildDirectory\shadps4.exe"
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}

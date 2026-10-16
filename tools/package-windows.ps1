param(
    [string]$BuildDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'runtime\Build\w1-x64-Clang-RelWithDebInfo'),
    [string]$OutputDirectory,
    [string]$DumpbinPath,
    [string[]]$DllDirectory = @(),
    [switch]$IncludeAcceptanceTools
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
    finally { $hasher.Dispose(); $stream.Dispose() }
}
try {
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell.' }
    $BuildDirectory = (Resolve-Path -LiteralPath $BuildDirectory).Path
    $executable = Join-Path $BuildDirectory 'shadps4.exe'
    $metadataPath = Join-Path $BuildDirectory 'build-info.json'
    if (-not (Test-Path -LiteralPath $metadataPath)) { throw 'Build with tools/build-windows.ps1 before packaging.' }
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ((Get-Sha256 $executable) -ne $metadata.executableSha256) {
        throw 'Executable no longer matches build-info.json. Rebuild before packaging.'
    }
    if (-not $DumpbinPath) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'Visual Studio C++ tools are required to inspect dependencies.' }
        $version = (Get-Content -LiteralPath (Join-Path $vs 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt') -Raw).Trim()
        $DumpbinPath = Join-Path $vs "VC\Tools\MSVC\$version\bin\Hostx64\x64\dumpbin.exe"
    }
    $dlls = @{}
    $systemDependencies = @{}
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($executable)
    while ($queue.Count -gt 0) {
        $binary = $queue.Dequeue()
        $imports = & $DumpbinPath /nologo /dependents $binary
        if ($LASTEXITCODE -ne 0) { throw "Dependency inspection failed: $binary" }
        foreach ($line in $imports) {
            if ($line -notmatch '^\s+([\w.\-]+\.dll)\s*$') { continue }
            $name = $matches[1]
            if ($dlls.ContainsKey($name) -or $systemDependencies.ContainsKey($name)) { continue }
            if ($name -match '^(api-ms-|ext-ms-)' -or (Test-Path -LiteralPath (Join-Path "$env:SystemRoot\System32" $name))) {
                $systemDependencies[$name] = $true
                continue
            }
            $found = $null
            foreach ($directory in (@($BuildDirectory) + $DllDirectory)) {
                $candidate = Join-Path $directory $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { $found = (Resolve-Path -LiteralPath $candidate).Path; break }
            }
            if (-not $found) { throw "Unresolved dependency: $name. Supply its directory with -DllDirectory." }
            $dlls[$name] = $found
            $queue.Enqueue($found)
        }
    }
    if (-not $OutputDirectory) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $OutputDirectory = Join-Path $repo "packages\i3-pc-$stamp"
    }
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    if ((Test-Path -LiteralPath $OutputDirectory) -or (Test-Path -LiteralPath "$OutputDirectory.zip")) {
        throw 'Output already exists. Choose a new directory; existing packages are never overwritten.'
    }
    $allowlist = @('Play.bat', 'Install.bat', 'Install.ps1', 'Keys.ps1', 'XboxPrompts.ps1', 'README.txt', 'input_config\CUSA00004.ini')
    foreach ($relative in $allowlist) {
        $source = Join-Path (Join-Path $repo 'dist') $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing package input: $source" }
    }
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    foreach ($relative in $allowlist) {
        $target = Join-Path $OutputDirectory $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath (Join-Path (Join-Path $repo 'dist') $relative) -Destination $target
    }
    Copy-Item -LiteralPath $executable -Destination (Join-Path $OutputDirectory 'inFAMOUS Second Son.exe')
    & (Join-Path $OutputDirectory 'XboxPrompts.ps1') -OutputDirectory $OutputDirectory
    foreach ($name in $dlls.Keys) { Copy-Item -LiteralPath $dlls[$name] -Destination (Join-Path $OutputDirectory $name) }
    Copy-Item -LiteralPath $metadataPath -Destination $OutputDirectory
    Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $OutputDirectory
    Copy-Item -LiteralPath (Join-Path $repo 'docs\W1_WINDOWS.md') -Destination $OutputDirectory
    if ($IncludeAcceptanceTools) {
        $toolOutput = Join-Path $OutputDirectory 'tools'
        New-Item -ItemType Directory -Path $toolOutput | Out-Null
        foreach ($name in @('accept-windows.ps1','collect-vulkan-diagnostics.ps1')) {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $toolOutput
        }
        Copy-Item -LiteralPath (Join-Path $repo 'docs/PC2_ACCEPTANCE.md') -Destination $OutputDirectory
    }
    @'
Create game_path.txt here with the full path to your own CUSA00004 v1.07 eboot.bin.
Start Play.bat. Settings and saves will be created in the user directory.
Requires Windows 10/11 x64, an x86-64-v3 CPU (target: AMD Ryzen), a compatible
Vulkan GPU/driver (target: NVIDIA) and Microsoft Visual C++ 2015-2022 x64 Redistributable.
Visual Studio, CMake, Ninja, Python and LLVM are not required to play.
No game data, firmware, saves or private settings are included.
Source: https://github.com/Retried/i3-pc (see build-info.json for exact commits).
The second-PC gameplay check is still required; this is a validation package.
'@ | Set-Content -LiteralPath (Join-Path $OutputDirectory 'START-HERE.txt') -Encoding ascii
    if ($IncludeAcceptanceTools) {
        Add-Content -LiteralPath (Join-Path $OutputDirectory 'START-HERE.txt') -Value 'Optional isolated capture and second-PC checks: see PC2_ACCEPTANCE.md.' -Encoding ascii
    }
    [ordered]@{
        systemDependencies = @($systemDependencies.Keys | Sort-Object)
        bundledDependencies = @($dlls.Keys | Sort-Object)
        files = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse | ForEach-Object {
            @{ path = $_.FullName.Substring($OutputDirectory.Length + 1); sha256 = (Get-Sha256 $_.FullName) }
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'package-manifest.json') -Encoding UTF8
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($OutputDirectory, "$OutputDirectory.zip", [IO.Compression.CompressionLevel]::Optimal, $true)
    Write-Host "Package: $OutputDirectory.zip"
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}

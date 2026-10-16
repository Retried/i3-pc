# Detached Windows build/package with durable launch, logs and verified status.
param(
    [string]$BuildDirectory,
    [string]$PackageDirectory,
    [Parameter(Mandatory = $true)][string]$LaunchDirectory,
    [ValidateSet('Release','RelWithDebInfo')][string]$Configuration = 'Release',
    [switch]$Lto,
    [ValidateRange(1,256)][int]$Jobs = 3,
    [string]$PythonExecutable = $env:PYTHON3_EXECUTABLE,
    [switch]$Worker
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
$LaunchDirectory = [IO.Path]::GetFullPath($LaunchDirectory)
$hostExe = (Get-Process -Id $PID).Path
function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $hasher.Dispose() }
}
function Read-SourceState {
    $state = [ordered]@{}
    foreach ($entry in @(@('wrapper',$repo),@('runtime',(Join-Path $repo 'runtime')))) {
        $sha = & git -C $entry[1] rev-parse HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read source SHA.' }
        $changes = @(& git -C $entry[1] status --porcelain --ignore-submodules)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read source state.' }
        $state[$entry[0]] = @{sha=$sha;changes=$changes}
    }
    return $state
}
if (-not $Worker) {
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell.' }
    $cpus = @(Get-CimInstance Win32_Processor)
    if (-not $cpus.Count -or @($cpus | Where-Object { $_.Name -notmatch 'AMD' }).Count) { throw 'AMD CPUs only.' }
    if (-not @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }).Count) { throw 'NVIDIA target GPU required.' }
    if (Get-Process -Name clang-cl,ninja,cmake,shadps4,i3,'inFAMOUS Second Son' -ErrorAction SilentlyContinue) { throw 'Another build/emulator is running; no duplicate launched.' }
    if (-not $BuildDirectory -or -not $PackageDirectory) { throw 'BuildDirectory and PackageDirectory are required.' }
    $BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
    $PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
    foreach ($path in @($BuildDirectory,$PackageDirectory,"$PackageDirectory.zip",$LaunchDirectory)) {
        if (Test-Path -LiteralPath $path) { throw "Output already exists: $path" }
    }
    $source = Read-SourceState
    if ($source.wrapper.changes.Count -or $source.runtime.changes.Count) { throw 'Publish or finish source changes before starting the release build.' }
    New-Item -ItemType Directory -Path $LaunchDirectory | Out-Null
    $inputRecord = [ordered]@{repo=$repo;buildDirectory=$BuildDirectory;packageDirectory=$PackageDirectory;configuration=$Configuration;lto=[bool]$Lto;jobs=$Jobs;pythonExecutable=$PythonExecutable;source=$source;createdAtUtc=[DateTime]::UtcNow.ToString('o');target='Windows x64; AMD Ryzen; NVIDIA Vulkan';scriptHashes=@{}}
    foreach ($name in @('start-windows-build.ps1','build-windows.ps1','package-windows.ps1','accept-windows.ps1','collect-vulkan-diagnostics.ps1')) {
        $inputRecord.scriptHashes[$name] = Get-Sha256 (Join-Path $PSScriptRoot $name)
    }
    $inputRecord | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $LaunchDirectory 'inputs.json') -Encoding UTF8
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'),'-Worker','-LaunchDirectory',('"' + $LaunchDirectory + '"'))
    $child = Start-Process -FilePath $hostExe -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput (Join-Path $LaunchDirectory 'stdout.log') -RedirectStandardError (Join-Path $LaunchDirectory 'stderr.log') -PassThru
    [ordered]@{pid=$child.Id;startedAtUtc=$child.StartTime.ToUniversalTime().ToString('o');command=@($hostExe)+$arguments;configuration=$Configuration;lto=[bool]$Lto;source=$source;inputs='inputs.json';stdout='stdout.log';stderr='stderr.log';status='status.json'} | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $LaunchDirectory 'launch.json') -Encoding UTF8
    Write-Output "Started PID $($child.Id). Launch record: $LaunchDirectory\launch.json"
    exit 0
}
$status = [ordered]@{status='running';phase='build';exitCode=$null;startedAtUtc=[DateTime]::UtcNow.ToString('o')}
$statusPath = Join-Path $LaunchDirectory 'status.json'
try {
    $inputRecord = Get-Content -LiteralPath (Join-Path $LaunchDirectory 'inputs.json') -Raw | ConvertFrom-Json
    $status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    $buildArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'build-windows.ps1'),'-BuildDirectory',$inputRecord.buildDirectory,'-Configuration',$inputRecord.configuration,'-Jobs',[string]$inputRecord.jobs)
    if ($inputRecord.lto) { $buildArgs += '-Lto' }
    if ($inputRecord.pythonExecutable) { $buildArgs += @('-PythonExecutable',$inputRecord.pythonExecutable) }
    & $hostExe @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Build failed with exit $LASTEXITCODE." }
    $source = Read-SourceState
    if ($source.wrapper.sha -ne $inputRecord.source.wrapper.sha -or $source.runtime.sha -ne $inputRecord.source.runtime.sha -or $source.wrapper.changes.Count -or $source.runtime.changes.Count) { throw 'Source state changed during build; do not accept this artifact.' }
    $exe = Join-Path $inputRecord.buildDirectory 'shadps4.exe'
    $metadata = Get-Content -LiteralPath (Join-Path $inputRecord.buildDirectory 'build-info.json') -Raw | ConvertFrom-Json
    $hash = Get-Sha256 $exe
    if ($metadata.executableSha256 -ne $hash -or $metadata.runtimeCommit -ne $source.runtime.sha -or $metadata.mainCommit -ne $source.wrapper.sha -or $metadata.configuration -ne $inputRecord.configuration -or $metadata.lto -ne $inputRecord.lto) { throw 'Executable metadata does not match the requested source/configuration.' }
    $status.phase='package'
    $status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
    & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'package-windows.ps1') -BuildDirectory $inputRecord.buildDirectory -OutputDirectory $inputRecord.packageDirectory -IncludeAcceptanceTools
    if ($LASTEXITCODE -ne 0) { throw "Packaging failed with exit $LASTEXITCODE." }
    $manifest = Get-Content -LiteralPath (Join-Path $inputRecord.packageDirectory 'package-manifest.json') -Raw | ConvertFrom-Json
    foreach ($file in $manifest.files) {
        if ((Get-Sha256 (Join-Path $inputRecord.packageDirectory $file.path)) -ne $file.sha256) { throw "Packaged file hash mismatch: $($file.path)" }
    }
    if ((Get-Sha256 (Join-Path $inputRecord.packageDirectory 'inFAMOUS Second Son.exe')) -ne $hash) { throw 'Packaged executable mismatch.' }
    $zip = "$($inputRecord.packageDirectory).zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $prefix = (Split-Path $inputRecord.packageDirectory -Leaf) + '/'
        foreach ($file in $manifest.files) {
            $entry = $archive.GetEntry($prefix + $file.path.Replace('\','/'))
            if (-not $entry) { throw "Missing ZIP entry: $($file.path)" }
            $stream = $entry.Open(); $hasher = [Security.Cryptography.SHA256]::Create()
            try { $entryHash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
            finally { $stream.Dispose(); $hasher.Dispose() }
            if ($entryHash -ne $file.sha256) { throw "ZIP entry hash mismatch: $($file.path)" }
        }
    } finally { $archive.Dispose() }
    $status.status='complete';$status.phase='verified-package';$status.exitCode=0
    $status.executable=$exe;$status.executableSha256=$hash;$status.package=$zip
    $status.packageSha256=Get-Sha256 $zip
    $status.runtimeBehavior='Not tested by this build job; second-PC acceptance remains required.'
} catch {
    $status.status='failed';$status.exitCode=1;$status.error=$_.Exception.Message
    Write-Error $_ -ErrorAction Continue
} finally {
    $status.finishedAtUtc=[DateTime]::UtcNow.ToString('o')
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
exit $status.exitCode

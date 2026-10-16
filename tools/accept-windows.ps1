# Isolated AMD/NVIDIA acceptance capture. This does not grant gameplay acceptance.
param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$Game,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$UserSeed,
    [ValidateSet('smoke', 'core-sync', 'gpu')][string]$Mode = 'smoke',
    [ValidateRange(70, 7200)][int]$DurationSeconds = 300,
    [string]$LayerDirectory,
    [string]$VulkanInfoPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output directory already exists.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$process = $null
$status = [ordered]@{ status='failed'; exitCode=$null; mode=$Mode; gameplayAcceptance=$false }
function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $hasher.Dispose() }
}
function Read-SfoStrings([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 20 -or [BitConverter]::ToUInt32($bytes, 0) -ne 0x46535000) { throw 'Invalid SFO.' }
    $keys = [BitConverter]::ToUInt32($bytes, 8)
    $values = [BitConverter]::ToUInt32($bytes, 12)
    $count = [BitConverter]::ToUInt32($bytes, 16)
    if (20 + [long]$count * 16 -gt $bytes.Length) { throw 'Truncated SFO table.' }
    $fields = @{}
    for ($index = 0; $index -lt $count; ++$index) {
        $entry = 20 + $index * 16
        if ([BitConverter]::ToUInt16($bytes, $entry + 2) -ne 0x204) { continue }
        $keyAt = [long]$keys + [BitConverter]::ToUInt16($bytes, $entry)
        $valueAt = [long]$values + [BitConverter]::ToUInt32($bytes, $entry + 12)
        $length = [BitConverter]::ToUInt32($bytes, $entry + 4)
        if ($keyAt -ge $bytes.Length -or $valueAt + $length -gt $bytes.Length) { throw 'Invalid SFO offsets.' }
        $keyEnd = $keyAt
        while ($keyEnd -lt $bytes.Length -and $bytes[$keyEnd]) { ++$keyEnd }
        $key = [Text.Encoding]::UTF8.GetString($bytes, $keyAt, $keyEnd - $keyAt)
        $fields[$key] = [Text.Encoding]::UTF8.GetString($bytes, $valueAt, $length).TrimEnd([char]0)
    }
    return $fields
}
try {
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell.' }
    if (@(Get-CimInstance Win32_Processor | Where-Object { $_.Name -notmatch 'AMD' }).Count) { throw 'AMD CPUs only.' }
    if (Get-Process -Name shadps4,i3,'inFAMOUS Second Son',clang-cl,ninja,cmake -ErrorAction SilentlyContinue) {
        throw 'Another emulator or build is running.'
    }
    $Executable = (Resolve-Path -LiteralPath $Executable).Path
    $Game = (Resolve-Path -LiteralPath $Game).Path
    $build = Get-Content -LiteralPath (Join-Path (Split-Path $Executable -Parent) 'build-info.json') -Raw | ConvertFrom-Json
    $binaryHash = Get-Sha256 $Executable
    if ($binaryHash -ne $build.executableSha256) { throw 'Executable/build-info hash mismatch.' }
    $sfo = Read-SfoStrings (Join-Path (Split-Path $Game -Parent) 'sce_sys/param.sfo')
    if ($sfo['TITLE_ID'] -ne 'CUSA00004' -or $sfo['APP_VER'] -ne '01.07') { throw 'CUSA00004 APP_VER 01.07 required.' }
    if ($LayerDirectory) { $env:VK_LAYER_PATH = (Resolve-Path -LiteralPath $LayerDirectory).Path }
    $probe = @('-NoProfile','-ExecutionPolicy','Bypass','-File', (Join-Path $PSScriptRoot 'collect-vulkan-diagnostics.ps1'), '-OutputDirectory', (Join-Path $OutputDirectory 'hardware'), '-Executable', $Executable)
    if ($VulkanInfoPath) { $probe += @('-VulkanInfoPath', $VulkanInfoPath) }
    & (Get-Process -Id $PID).Path @probe
    if ($LASTEXITCODE -ne 0) { throw 'Hardware probe failed; vulkaninfo is required for unambiguous NVIDIA selection.' }
    $hardware = Get-Content -LiteralPath (Join-Path $OutputDirectory 'hardware/diagnostics.json') -Raw | ConvertFrom-Json
    if ($null -eq $hardware.selectedVulkanGpuIndex -or -not @($hardware.hardware.cpu).Count) { throw 'AMD/NVIDIA target unavailable.' }
    if ($Mode -ne 'smoke' -and $hardware.validationLayerEnumerated -ne $true) {
        $status.status = 'blocked'
        throw 'Khronos validation layer unavailable. Supply a local SDK layer directory; no validation run was performed.'
    }
    $user = Join-Path $OutputDirectory 'user'
    New-Item -ItemType Directory -Path $user | Out-Null
    $config = '{"General":{},"GPU":{},"Vulkan":{}}' | ConvertFrom-Json
    if ($UserSeed) {
        $UserSeed = (Resolve-Path -LiteralPath $UserSeed).Path
        foreach ($name in @('home','input_config','users.json','keys.json','i3_graphics.txt','i3_first_run.txt','i3_intro_shown.txt')) {
            $path = Join-Path $UserSeed $name
            if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination (Join-Path $user $name) -Recurse }
        }
        $configPath = Join-Path $UserSeed 'config.json'
        if (Test-Path -LiteralPath $configPath) { $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json }
    }
    foreach ($section in @('General','GPU','Vulkan')) {
        if (-not $config.PSObject.Properties[$section]) { $config | Add-Member -NotePropertyName $section -NotePropertyValue ([pscustomobject]@{}) }
    }
    $updates = @{
        General=@{home_dir='';sys_modules_dir='';font_dir='';discord_rpc_enabled=$false}
        GPU=@{full_screen=$false;internal_screen_width=1280;internal_screen_height=720;window_width=1280;window_height=720}
        Vulkan=@{gpu_id=$hardware.selectedVulkanGpuIndex;vkvalidation_enabled=($Mode -ne 'smoke');vkvalidation_core_enabled=($Mode -ne 'gpu');vkvalidation_sync_enabled=($Mode -eq 'core-sync');vkvalidation_gpu_enabled=($Mode -eq 'gpu')}
    }
    foreach ($section in $updates.Keys) {
        foreach ($name in $updates[$section].Keys) { $config.$section | Add-Member -NotePropertyName $name -NotePropertyValue $updates[$section][$name] -Force }
    }
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $user 'config.json') -Encoding UTF8
    Get-ChildItem Env: | Where-Object { $_.Name -match '^(SOTC_|I3_)' } | ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" }
    $env:SOTC_HEADLESS='1'; $env:I3_SKIP_FIRST_RUN='1'; $env:SOTC_SCRIPT_BOOT_MS='0'; $env:SDL_AUDIODRIVER='dummy'
    $steps = @(@{at=20;action='cross'},@{at=40;action='cross'},@{at=60;action='cross'},@{at=$DurationSeconds;action='quit'})
    foreach ($at in @(10,50,100,200,($DurationSeconds - 5)) | Select-Object -Unique) {
        if ($at -lt $DurationSeconds) { $steps += @{at=$at;action='shot'} }
    }
    $env:SOTC_SCRIPT=($steps | Sort-Object { [int]$_['at'] } | ForEach-Object { "$($_.at):$($_.action)" }) -join ','
    Copy-Item -LiteralPath $Executable -Destination (Join-Path $OutputDirectory 'shadps4.exe')
    Get-ChildItem -LiteralPath (Split-Path $Executable -Parent) -Filter '*.dll' -File | Copy-Item -Destination $OutputDirectory
    $process = Start-Process -FilePath (Join-Path $OutputDirectory 'shadps4.exe') -ArgumentList @('--game', ('"' + $Game + '"'), '--fullscreen','false') -WorkingDirectory $OutputDirectory -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputDirectory 'stdout.log') -RedirectStandardError (Join-Path $OutputDirectory 'stderr.log') -PassThru
    $null = $process.Handle
    [ordered]@{pid=$process.Id;startedAtUtc=$process.StartTime.ToUniversalTime().ToString('o');sourceExecutable=$Executable;executableSha256=$binaryHash;buildInfo=$build;gameHash=(Get-Sha256 $Game);title=$sfo['TITLE_ID'];appVersion=$sfo['APP_VER'];mode=$Mode;script=$env:SOTC_SCRIPT;configuration=$config;seed=$UserSeed;isolatedUser=$true;performanceMeasurement=$false} | ConvertTo-Json -Depth 22 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'launch.json') -Encoding UTF8
    $limit = [DateTime]::UtcNow.AddSeconds($DurationSeconds + 180)
    $samples = @()
    while (-not $process.WaitForExit(1000)) {
        if ([DateTime]::UtcNow -gt $limit) { $process.Kill(); $process.WaitForExit(); throw 'Own child exceeded timeout.' }
        $process.Refresh()
        $samples += [pscustomobject]@{utc=[DateTime]::UtcNow.ToString('o');workingSetBytes=$process.WorkingSet64;cpuMilliseconds=$process.TotalProcessorTime.TotalMilliseconds}
    }
    $process.WaitForExit()
    $status.exitCode = $process.ExitCode
    $samples | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'process.csv') -NoTypeInformation -Encoding ascii
    $logPath = Join-Path $user 'log/shad_log.txt'
    $log = Get-Content -LiteralPath $logPath -Raw
    $status.logSha256 = Get-Sha256 $logPath
    $status.validationMessages = @([regex]::Matches($log, '(?m)^.*(?:VUID-|SYNC-HAZARD|Validation Error).*$') | ForEach-Object { $_.Value })
    if ($process.ExitCode -ne 0 -or $log -notmatch 'GPU_Model: NVIDIA' -or $log -notmatch 'App Version: 01.07' -or $log -match '<Critical>|eErrorDeviceLost|Device lost|Assertion Failed') { throw 'Startup/exit/version/GPU/critical checks failed.' }
    if ($Mode -ne 'smoke' -and ($log -notmatch 'Enabled instance layers:.*VK_LAYER_KHRONOS_validation' -or $log -notmatch 'Validation layer requested=true, explicitly enabled=true')) { throw 'Explicit Khronos enabled log not confirmed.' }
    if ($status.validationMessages.Count) { throw 'Validation messages require review; not validation-clean.' }
    $status.status = 'captured'
    $status.visualReview = 'pending; screenshots do not establish full gameplay acceptance'
} catch {
    $status.error = $_.Exception.Message
    Write-Error $_ -ErrorAction Continue
} finally {
    if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $status.finishedAtUtc = [DateTime]::UtcNow.ToString('o')
    $status | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'status.json') -Encoding UTF8
}
if ($status.status -eq 'captured') { exit 0 }
exit 1

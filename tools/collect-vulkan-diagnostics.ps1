param(
    [string]$OutputDirectory,
    [string]$VulkanInfoPath,
    [string]$Executable,
    [string[]]$RuntimeLog = @()
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

function Get-GitState([string]$Directory) {
    $git = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) { return @{ commit = $null; changes = $null; status = 'git unavailable' } }
    $revision = & $git.Source -C $Directory rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return @{ commit = $null; changes = $null; status = 'revision unavailable' } }
    $changes = @(& $git.Source -C $Directory status --porcelain --ignore-submodules 2>$null)
    if ($LASTEXITCODE -ne 0) { return @{ commit = $revision; changes = $null; status = 'changes unavailable' } }
    return @{ commit = $revision; changes = $changes; status = 'available' }
}

function Invoke-Probe([string]$Path, [string[]]$Arguments, [string]$Name) {
    if (-not $Path) { return @{ status = 'unavailable'; exitCode = $null } }
    $launch = @{
        FilePath = $Path; WorkingDirectory = $OutputDirectory; WindowStyle = 'Hidden'; PassThru = $true
        RedirectStandardOutput = (Join-Path $OutputDirectory "$Name.stdout.txt")
        RedirectStandardError = (Join-Path $OutputDirectory "$Name.stderr.txt")
    }
    if ($Arguments.Count -gt 0) { $launch.ArgumentList = $Arguments }
    $process = Start-Process @launch
    # Windows PowerShell must retain a process handle to preserve its exit code.
    $null = $process.Handle
    $finished = $process.WaitForExit(30000)
    if (-not $finished) { $process.Kill(); $process.WaitForExit() }
    $process.WaitForExit()
    return @{
        executable = $Path; arguments = $Arguments; exitCode = $process.ExitCode
        status = $(if (-not $finished) { 'timed out' } elseif ($process.ExitCode -eq 0) { 'completed' } else { 'failed' })
    }
}

try {
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell.' }
    if (-not $OutputDirectory) {
        $OutputDirectory = Join-Path $repo ("runtime\Build\vulkan-diagnostics-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    $OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    if (Test-Path -LiteralPath $OutputDirectory) { throw 'Output already exists. Select a new diagnostic directory.' }
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    if ($VulkanInfoPath) { $VulkanInfoPath = (Resolve-Path -LiteralPath $VulkanInfoPath).Path }
    else {
        $tool = Get-Command vulkaninfo.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($tool) { $VulkanInfoPath = $tool.Source }
    }
    $summary = Invoke-Probe $VulkanInfoPath @('--summary') 'vulkan-summary'
    $selectedGpu = $null
    if ($summary.status -eq 'completed') {
        $summaryText = Get-Content -LiteralPath (Join-Path $OutputDirectory 'vulkan-summary.stdout.txt') -Raw
        foreach ($block in [regex]::Matches($summaryText, '(?ms)^GPU(\d+):\s*\r?\n(.*?)(?=^GPU\d+:|\z)')) {
            if ($block.Groups[2].Value -match 'vendorID\s*=\s*0x10de\b') {
                $selectedGpu = [int]$block.Groups[1].Value
                break
            }
        }
    }
    $vulkan = if ($null -ne $selectedGpu) {
        Invoke-Probe $VulkanInfoPath @("--json=$selectedGpu", '--output', 'vulkan-capabilities.json') 'vulkaninfo'
    } else { @{ status = 'unavailable'; exitCode = $null; reason = 'No NVIDIA GPU identified in Vulkan summary' } }
    $nvidiaTool = Get-Command nvidia-smi.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $nvidia = if ($nvidiaTool) {
        Invoke-Probe $nvidiaTool.Source @('--query-gpu=name,driver_version,pci.bus_id,memory.total', '--format=csv') 'nvidia-smi'
    } else { @{ status = 'unavailable'; exitCode = $null } }
    $hardware = @{ status = 'unavailable'; cpu = $null; gpu = $null; os = $null; ramBytes = $null }
    try {
        $hardware.cpu = @(Get-CimInstance Win32_Processor | Where-Object { $_.Name -match 'AMD' } | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors)
        $hardware.gpu = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object Name, DriverVersion)
        $hardware.os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber
        $hardware.ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        $hardware.status = if ($hardware.cpu.Count -gt 0) { 'available' } else { 'AMD CPU unavailable; outside target hardware' }
    } catch { $hardware.status = 'partially available or unavailable' }
    $environment = [ordered]@{}
    foreach ($name in @('VK_DRIVER_FILES', 'VK_ICD_FILENAMES', 'VK_LAYER_PATH', 'VK_ADD_LAYER_PATH',
        'VK_INSTANCE_LAYERS', 'VK_LOADER_DEBUG', 'VK_LOADER_LAYERS_ENABLE', 'VK_LOADER_LAYERS_DISABLE',
        'VK_LAYER_SETTINGS_PATH', 'SOTC_HEADLESS', 'I3_NO_MIRROR', 'I3_NO_ARG_MIRROR',
        'SOTC_MIRROR_ALL', 'SOTC_MIRROR_ONLY', 'SOTC_MIRROR_SKIP')) {
        $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    $binary = $null
    if ($Executable) {
        $Executable = (Resolve-Path -LiteralPath $Executable).Path
        $metadataPath = Join-Path (Split-Path $Executable -Parent) 'build-info.json'
        $metadata = if (Test-Path -LiteralPath $metadataPath) { Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json } else { $null }
        $binary = @{ path = $Executable; sha256 = (Get-Sha256 $Executable); buildInfo = $metadata; metadataHashMatches = $null }
        if ($metadata -and $metadata.PSObject.Properties['executableSha256']) {
            $binary.metadataHashMatches = $binary.sha256 -eq $metadata.executableSha256
        }
    }
    $logs = @()
    for ($index = 0; $index -lt $RuntimeLog.Count; ++$index) {
        $path = (Resolve-Path -LiteralPath $RuntimeLog[$index]).Path
        $copyName = "runtime-$index.log"
        Copy-Item -LiteralPath $path -Destination (Join-Path $OutputDirectory $copyName)
        $logs += @{ name = $copyName; sha256 = (Get-Sha256 (Join-Path $OutputDirectory $copyName)) }
    }
    $validationAvailable = if ($summary.status -eq 'completed') {
        $summaryText -match '\bVK_LAYER_KHRONOS_validation\b'
    } else { $null }
    [ordered]@{
        schemaVersion = 2; capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        target = 'Windows x64; AMD CPU; NVIDIA Vulkan GPU'; selectedVulkanGpuIndex = $selectedGpu
        wrapper = (Get-GitState $repo); runtime = (Get-GitState (Join-Path $repo 'runtime'))
        hardware = $hardware; environment = $environment; executable = $binary
        vulkanSummary = $summary; vulkaninfo = $vulkan; nvidiaSmi = $nvidia
        validationLayerEnumerated = $validationAvailable
        validationRunPerformed = $false
        note = 'Capability inventory only. Layer enumeration does not prove validation was enabled in a game run.'
        runtimeLogs = $logs
    } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'diagnostics.json') -Encoding UTF8
    @'
Review diagnostics.json, the Vulkan capability inventory and any explicitly supplied logs.
The GPU summary is used to locate NVIDIA and enumerate layers; the capability profile
targets only the selected NVIDIA GPU. CPU inventory is limited to AMD.
Missing values are unavailable, not zero. No game is launched by this collector.
Validation requires VK_LAYER_KHRONOS_validation to be available and explicitly enabled
for a separate emulator run. This bundle alone does not validate rendering or performance.
Only explicitly requested runtime logs are copied; they may contain local paths.
'@ | Set-Content -LiteralPath (Join-Path $OutputDirectory 'README.txt') -Encoding ascii
    Write-Output "Vulkan diagnostics: $OutputDirectory"
    if ($vulkan.status -ne 'completed') { throw 'Vulkan capability probe was unavailable or failed; inspect diagnostics.json.' }
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}

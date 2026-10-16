# PID-scoped telemetry. NVIDIA utilization and VRAM describe the whole selected GPU.
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$ProcessId = 0,
    [string]$Name = 'shadps4',
    [int]$Max = 0,
    [string]$NvidiaGpu = '0'
)
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$nvidia = Get-Command nvidia-smi.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ProcessId) { $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue }
else { $process = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $process) { throw 'Target process is not running.' }
$ProcessId = $process.Id
$started = $process.StartTime.ToUniversalTime()
$beforeThreads = @{}
$beforeAt = $null
$beforeCpu = $null
$count = 0
Set-Content -LiteralPath $Out -Value 'unix_seconds,process_cpu_percent,busiest_thread_percent,nvidia_gpu_percent,nvidia_vram_used_mb,working_set_mb,nvidia_power_w,nvidia_temp_c' -Encoding ascii
while ($true) {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process -or $process.StartTime.ToUniversalTime() -ne $started) { break }
    $now = [DateTimeOffset]::UtcNow
    $cpuTime = $process.TotalProcessorTime.TotalMilliseconds
    $threads = @{}
    foreach ($thread in $process.Threads) {
        try { $threads[$thread.Id] = $thread.TotalProcessorTime.TotalMilliseconds } catch { }
    }
    $cpu = $null
    $busiest = $null
    if ($beforeAt) {
        $elapsed = ($now - $beforeAt).TotalMilliseconds
        $cpu = ($cpuTime - $beforeCpu) / $elapsed / [Environment]::ProcessorCount * 100.0
        foreach ($threadId in $threads.Keys) {
            if ($beforeThreads.ContainsKey($threadId)) {
                $share = ($threads[$threadId] - $beforeThreads[$threadId]) / $elapsed * 100.0
                if ($null -eq $busiest -or $share -gt $busiest) { $busiest = $share }
            }
        }
    }
    $gpu = $null; $vram = $null; $power = $null; $temperature = $null
    if ($nvidia) {
        $values = & $nvidia.Source "--id=$NvidiaGpu" '--query-gpu=utilization.gpu,memory.used,power.draw,temperature.gpu' '--format=csv,noheader,nounits' 2>$null
        if ($LASTEXITCODE -eq 0 -and $values) {
            $parts = ($values | Select-Object -First 1) -split ','
            $parsed = @()
            foreach ($part in $parts) {
                $number = 0.0
                $parsed += $(if ([double]::TryParse($part.Trim(), [Globalization.NumberStyles]::Float, $culture, [ref]$number)) { $number } else { $null })
            }
            if ($parsed.Count -eq 4) { $gpu, $vram, $power, $temperature = $parsed }
        }
    }
    $cells = @(($now.ToUnixTimeMilliseconds() / 1000.0), $cpu, $busiest, $gpu, $vram, ($process.WorkingSet64 / 1MB), $power, $temperature)
    $line = ($cells | ForEach-Object { if ($null -eq $_) { '' } else { $_.ToString('F3', $culture) } }) -join ','
    Add-Content -LiteralPath $Out -Value $line -Encoding ascii
    $beforeAt = $now; $beforeCpu = $cpuTime; $beforeThreads = $threads
    ++$count
    if ($Max -gt 0 -and $count -ge $Max) { break }
    Start-Sleep -Milliseconds 1000
}

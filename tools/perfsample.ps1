# Samples what a benchmark video shows beside the frame rate, once a second, until the process
# ends: total CPU load, the busiest thread of the process, its GPU load and video memory, its
# RAM. Reads Windows performance counters and process times only; nothing is attached to the game.
# Output: CSV lines "unix seconds,cpu %,busiest thread %,gpu %,video memory MB,ram MB".
param([string]$Out = 'D:\i3-pc\testrun\perf_samples.csv', [string]$Name = 'i3', [int]$Max = 0)

Set-Content -Path $Out -Value 'time,cpu,thread,gpu,vram,ram' -Encoding ascii
$seen = $false
$before = @{}
$beforeAt = $null
$count = 0
while ($true) {
    $p = Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) {
        if ($seen) { break }
        Start-Sleep -Milliseconds 500
        continue
    }
    $seen = $true
    $id = $p.Id
    $paths = @(
        '\Processor(_Total)\% Processor Time',
        '\GPU Engine(*engtype_3D)\Utilization Percentage',
        "\GPU Process Memory(pid_${id}_*)\Dedicated Usage"
    )
    $s = $null
    try {
        $s = (Get-Counter -Counter $paths -SampleInterval 1 -ErrorAction SilentlyContinue).CounterSamples
    } catch { }
    if (-not $s) { Start-Sleep -Milliseconds 500; continue }
    $cpu = ($s | Where-Object Path -like '*processor(_total)*' | Measure-Object CookedValue -Maximum).Maximum
    # GPU load of the whole card: the per-process counters read zero for this program. Every
    # process has one counter per engine; the busiest 3D engine, summed over processes, is the load.
    $gpu = 0.0
    $s | Where-Object Path -like '*gpu engine*' |
        Group-Object { $_.InstanceName -replace '^pid_\d+_', '' } | ForEach-Object {
            $sum = ($_.Group | Measure-Object CookedValue -Sum).Sum
            if ($sum -gt $gpu) { $gpu = $sum }
        }
    $vram = 0.0
    $mem = ($s | Where-Object Path -like '*gpu process memory*' | Measure-Object CookedValue -Sum).Sum
    if ($mem) { $vram = $mem / 1MB }
    # Busiest thread: processor time each thread gained since the last sample.
    $thread = 0.0
    $nowAt = Get-Date
    $now = @{}
    try {
        $p.Refresh()
        foreach ($t in $p.Threads) {
            try { $now[$t.Id] = $t.TotalProcessorTime.TotalMilliseconds } catch { }
        }
    } catch { }
    if ($beforeAt) {
        $span = ($nowAt - $beforeAt).TotalMilliseconds
        foreach ($k in $now.Keys) {
            if ($before.ContainsKey($k)) {
                $share = ($now[$k] - $before[$k]) / $span * 100.0
                if ($share -gt $thread) { $thread = $share }
            }
        }
    }
    $before = $now
    $beforeAt = $nowAt
    $ram = $p.WorkingSet64 / 1MB
    $unix = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
    $line = [string]::Format([Globalization.CultureInfo]::InvariantCulture,
        '{0:F2},{1:F1},{2:F1},{3:F1},{4:F0},{5:F0}', $unix, $cpu, $thread, $gpu, $vram, $ram)
    Add-Content -Path $Out -Value $line -Encoding ascii
    $count++
    if ($Max -gt 0 -and $count -ge $Max) { break }
}

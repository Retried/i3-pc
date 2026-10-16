# Stream a detached build's durable logs without owning the build process.
param(
    [Parameter(Mandatory = $true)][string]$LaunchDirectory,
    [string]$LaunchFile = 'launch.json',
    [string]$StatusFile = 'status.json',
    [string]$StdoutFile = 'stdout.log',
    [string]$StderrFile = 'stderr.log',
    [switch]$KeepOpen
)
$ErrorActionPreference = 'Stop'
$LaunchDirectory = [IO.Path]::GetFullPath($LaunchDirectory)
$launch = Get-Content -LiteralPath (Join-Path $LaunchDirectory $LaunchFile) -Raw | ConvertFrom-Json
$readers = @()
function Complete-Viewer([int]$Code) {
    if ($KeepOpen) { [void](Read-Host 'Press Enter to close this log console') }
    exit $Code
}
function Write-NewOutput {
    foreach ($reader in $readers) {
        $chunk = $reader.ReadToEnd()
        if ($chunk.Length) { [Console]::Write($chunk) }
    }
}
try {
    foreach ($name in @($StdoutFile, $StderrFile)) {
        $stream = [IO.File]::Open((Join-Path $LaunchDirectory $name), [IO.FileMode]::Open,
            [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $readers += [IO.StreamReader]::new($stream)
    }
    Write-Host "Build console: $LaunchDirectory (worker PID $($launch.pid))"
    Write-Host 'Closing this viewer leaves the detached build running.'
    while ($true) {
        Write-NewOutput
        $statusPath = Join-Path $LaunchDirectory $StatusFile
        $status = $null
        if (Test-Path -LiteralPath $statusPath) {
            # The worker replaces this small JSON file while updating its phase.
            try { $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json }
            catch { $status = $null }
        }
        if ($status -and $null -ne $status.exitCode) {
            Write-NewOutput
            Write-Host "Build status: $($status.status); exit $($status.exitCode)"
            if ($status.PSObject.Properties['error']) { Write-Host $status.error }
            Complete-Viewer ([int]$status.exitCode)
        }
        $worker = Get-Process -Id $launch.pid -ErrorAction SilentlyContinue
        if (-not $worker -or
            [Math]::Abs(($worker.StartTime.ToUniversalTime() -
                ([DateTime]$launch.startedAtUtc).ToUniversalTime()).TotalSeconds) -gt 1) {
            Write-NewOutput
            Write-Host 'Worker exited without a final status: interrupted/unknown.'
            Complete-Viewer 1
        }
        Start-Sleep -Milliseconds 250
    }
} finally {
    foreach ($reader in $readers) { $reader.Dispose() }
}

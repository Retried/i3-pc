# Open a separate log console without desktop input or activation automation.
param(
    [Parameter(Mandatory = $true)][string]$LaunchDirectory,
    [string]$LaunchFile = 'launch.json',
    [string]$StatusFile = 'status.json',
    [string]$StdoutFile = 'stdout.log',
    [string]$StderrFile = 'stderr.log',
    [switch]$CloseOnExit
)
$ErrorActionPreference = 'Stop'
$LaunchDirectory = [IO.Path]::GetFullPath($LaunchDirectory)
$viewer = Join-Path $PSScriptRoot 'show-windows-build.ps1'
$shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath (Join-Path $LaunchDirectory $LaunchFile))) {
    throw 'Build launch record is missing.'
}
$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $viewer + '"'),
    '-LaunchDirectory', ('"' + $LaunchDirectory + '"'),
    '-LaunchFile', ('"' + $LaunchFile + '"'), '-StatusFile', ('"' + $StatusFile + '"'),
    '-StdoutFile', ('"' + $StdoutFile + '"'), '-StderrFile', ('"' + $StderrFile + '"'))
if (-not $CloseOnExit) { $arguments += '-KeepOpen' }
$console = Start-Process -FilePath $shell -ArgumentList $arguments -WindowStyle Normal -PassThru
[ordered]@{
    pid = $console.Id
    startedAtUtc = $console.StartTime.ToUniversalTime().ToString('o')
    command = @($shell) + $arguments
    buildLaunch = $LaunchFile
    stdout = $StdoutFile
    stderr = $StderrFile
    keepOpen = -not [bool]$CloseOnExit
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $LaunchDirectory 'console-launch.json') -Encoding UTF8
Write-Output "Opened build console PID $($console.Id). Closing it leaves the build running."

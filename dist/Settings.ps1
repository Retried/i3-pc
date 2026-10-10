# inFAMOUS Second Son - PC build settings. Edits .\user\config.json.
# Run Settings.bat, or e.g.: pwsh -File Settings.ps1 -Fps 60 -VSync off -Fullscreen on
param(
    [ValidateSet('30', '60', '90', '120', '144', 'uncapped', '')] [string]$Fps = '',
    [ValidateSet('on', 'off', '')] [string]$VSync = '',
    [ValidateSet('on', 'off', '')] [string]$Fullscreen = '',
    [ValidateSet('720p', '1080p', '1440p', '4k', '')] [string]$Window = '',
    [ValidateSet('on', 'off', '')] [string]$Upscaling = '',
    [ValidateSet('english', 'spanish', 'latin-spanish', 'french', 'german', 'italian', 'portuguese', 'brazilian', 'russian', 'japanese', '')] [string]$Language = ''
)

$path = Join-Path $PSScriptRoot 'user\config.json'
if (-not (Test-Path $path)) {
    Write-Host "No config found at $path."
    exit 1
}
$config = Get-Content $path -Raw | ConvertFrom-Json

function Ask($prompt, $choices, $current) {
    Write-Host ""
    Write-Host "$prompt  (current: $current)"
    for ($i = 0; $i -lt $choices.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $choices[$i]) }
    $answer = Read-Host "Choice, or Enter to keep"
    if ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $choices.Count) {
        return $choices[[int]$answer - 1]
    }
    return ''
}

# The game presents once per tick of the frame clock, so the clock rate is the frame rate cap.
$currentFps = if ($config.GPU.vblank_frequency -ge 1000) { 'uncapped' } else { [string]$config.GPU.vblank_frequency }
$currentVSync = if ($config.GPU.present_mode -eq 'Fifo') { 'on' } else { 'off' }
$currentFull = if ($config.GPU.full_screen) { 'on' } else { 'off' }
# Console language ids (European release).
$languages = [ordered]@{ english = 18; spanish = 3; 'latin-spanish' = 20; french = 2; german = 4; italian = 5; portuguese = 7; brazilian = 17; russian = 8; japanese = 0 }
$currentLanguage = ($languages.GetEnumerator() | Where-Object { $_.Value -eq $config.General.console_language }).Key
if (-not $currentLanguage) { $currentLanguage = "id $($config.General.console_language)" }

if (-not ($Fps -or $VSync -or $Fullscreen -or $Window -or $Upscaling -or $Language)) {
    $Fps = Ask 'Frame rate cap' @('30', '60', '90', '120', '144', 'uncapped') $currentFps
    $VSync = Ask 'VSync' @('on', 'off') $currentVSync
    $Fullscreen = Ask 'Fullscreen' @('on', 'off') $currentFull
    $Window = Ask 'Window size' @('720p', '1080p', '1440p', '4k') "$($config.GPU.window_width)x$($config.GPU.window_height)"
    $Upscaling = Ask 'FSR upscaling to the window size' @('on', 'off') $(if ($config.GPU.fsr_enabled) { 'on' } else { 'off' })
    $Language = Ask 'Language' @($languages.Keys) $currentLanguage
}

if ($Fps) { $config.GPU.vblank_frequency = if ($Fps -eq 'uncapped') { 1000 } else { [int]$Fps } }
# Fifo waits for the display; Immediate presents as soon as a frame is ready.
if ($VSync) { $config.GPU.present_mode = if ($VSync -eq 'on') { 'Fifo' } else { 'Immediate' } }
if ($Fullscreen) {
    $config.GPU.full_screen = ($Fullscreen -eq 'on')
    $config.GPU.full_screen_mode = if ($Fullscreen -eq 'on') { 'Fullscreen (Borderless)' } else { 'Windowed' }
}
if ($Window) {
    $size = @{ '720p' = 1280, 720; '1080p' = 1920, 1080; '1440p' = 2560, 1440; '4k' = 3840, 2160 }[$Window]
    $config.GPU.window_width = $size[0]
    $config.GPU.window_height = $size[1]
}
if ($Upscaling) { $config.GPU.fsr_enabled = ($Upscaling -eq 'on') }
# The PS4 Pro mode of the game does not run in this build, so the base console profile is kept.
$config.General.neo_mode = $false
if ($Language) { $config.General.console_language = $languages[$Language] }
$config | ConvertTo-Json -Depth 10 | Set-Content $path -Encoding utf8

Write-Host ""
Write-Host ("Saved: frame clock {0} Hz, present mode {1}, fullscreen {2}, window {3}x{4}" -f `
        $config.GPU.vblank_frequency, $config.GPU.present_mode, $config.GPU.full_screen, `
        $config.GPU.window_width, $config.GPU.window_height)

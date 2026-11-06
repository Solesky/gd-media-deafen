# Starts Geometry Dash, then mutes your browser and media apps when your auto-deafen mod fires, and undoes
# that when it fires again. Exits once the game closes.
# In PAUSE mode it also pauses whatever is playing, and the mute is a backup for anything that ignores the
# pause, such as a second tab. MUTE mode is for live streams, which would fall behind if paused.
# switch_mode.ps1 switches between the two.
#
# Auto-deafen mods fire by pressing a key (the one bound to deafen in Discord). This script watches for that
# same key using Raw Input, which only observes: the key still reaches Discord, and nothing sits between
# your keyboard and GD.
param(
    [string]$GameExe = "C:\Program Files (x86)\Steam\steamapps\common\Geometry Dash\GeometryDash.exe",
    [string]$Keys = '',          # virtual key codes to watch, like "17,16,191". Empty means Mega Hack's Auto Deafen shortcut
    [string[]]$MediaApps = @(),  # for testing: mute these apps instead of the ones in apps.txt
    [string]$OnlyPause = '',     # for testing: only pause this app, leaving everything else alone
    [int]$GraceSeconds = 60      # how long to wait for the game after it closes, in case Geode or Steam restarts it
)

$gameName = [IO.Path]::GetFileNameWithoutExtension($GameExe)

function Get-Game { Get-Process -Name $gameName -ErrorAction SilentlyContinue | Select-Object -First 1 }

# Start the game first, so a problem further down can never stop GD from opening.
$startError = $null
if (-not (Get-Game)) { Start-Process $GameExe -WorkingDirectory (Split-Path $GameExe) -ErrorAction SilentlyContinue -ErrorVariable startError }

$mutex = New-Object Threading.Mutex($false, "GDMediaDeafen_$gameName")
try { if (-not $mutex.WaitOne(0)) { exit } } catch [Threading.AbandonedMutexException] {}

$log = Join-Path $PSScriptRoot 'media_deafen.log'
$mutedFile = Join-Path $PSScriptRoot 'muted_apps.txt'
$modeFile = Join-Path $PSScriptRoot 'mode.txt'
Set-Content $log "Started $(Get-Date)"
function Write-Log($message) { Add-Content $log "$(Get-Date -Format HH:mm:ss) $message" }
if ($startError) { Write-Log "Could not start the game: $startError" }

# Read on every press, so edits to apps.txt apply the next time it fires.
function Get-MediaApps {
    if ($MediaApps) { return $MediaApps }
    Get-Content (Join-Path $PSScriptRoot 'apps.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
}

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$asTask = [WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

function Wait-Operation($operation, [type]$resultType) {
    $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
    if ($task.Wait(3000)) { $task.Result }
}

$deafened = $false
$mutedApps = @()
$pausedApps = @()

function Mute-Media {
    $script:mutedApps = @([AppAudio]::Mute(@(Get-MediaApps)))
    if ($script:mutedApps) { Set-Content $mutedFile $script:mutedApps }
    Write-Log "Deafen: muted [$($script:mutedApps -join ', ')]"
}

function Unmute-Media {
    [AppAudio]::Unmute($script:mutedApps)
    Remove-Item $mutedFile -ErrorAction SilentlyContinue
    Write-Log "Undeafen: unmuted [$($script:mutedApps -join ', ')]"
    $script:mutedApps = @()
}

function Pause-Media {
    $script:pausedApps = @()
    foreach ($session in $manager.GetSessions()) {
        if ($OnlyPause -and $session.SourceAppUserModelId -ne $OnlyPause) { continue }
        if ($session.GetPlaybackInfo().PlaybackStatus -eq 'Playing') {
            if (Wait-Operation ($session.TryPauseAsync()) ([bool])) { $script:pausedApps += $session.SourceAppUserModelId }
        }
    }
    Write-Log "Deafen: paused [$($script:pausedApps -join ', ')]"
}

# Only resumes what Pause-Media paused, so anything you had paused yourself stays paused.
function Resume-Media {
    $apps = $script:pausedApps
    $script:pausedApps = @()
    foreach ($session in $manager.GetSessions()) {
        $app = $session.SourceAppUserModelId
        if ($apps -notcontains $app) { continue }
        # Browsers can be slow to act on this. Play is not a toggle, so asking again is safe.
        for ($try = 0; $try -lt 3 -and $session.GetPlaybackInfo().PlaybackStatus -eq 'Paused'; $try++) {
            [void](Wait-Operation ($session.TryPlayAsync()) ([bool]))
            Start-Sleep -Seconds 1
        }
        Write-Log "Undeafen: $app is $($session.GetPlaybackInfo().PlaybackStatus) after $try attempt(s)"
    }
}

function Write-Audible {
    try { Write-Log "Audible now: [$([AppAudio]::AudibleApps() -join ', ')]" } catch { Write-Log "Audio error: $_" }
}

# Muting comes first because it's instant, and each step runs even if the other one fails.
# The mode is read on every press, so switching it works while GD is open and applies from the next deafen.
function Start-Deafen {
    try { Mute-Media } catch { Write-Log "Mute error: $_" }
    if ((Get-Content $modeFile -ErrorAction SilentlyContinue) -eq 'MUTE') {
        Write-Log 'Deafen: mute mode, not pausing'
    } else {
        try { Pause-Media } catch { Write-Log "Pause error: $_" }
    }
    Write-Audible
}

function Stop-Deafen {
    try { Unmute-Media } catch { Write-Log "Unmute error: $_" }
    try { Resume-Media } catch { Write-Log "Resume error: $_" }
    Write-Audible
}

try {
    Add-Type -Path (Join-Path $PSScriptRoot 'AppAudio.cs')
    Add-Type -Path (Join-Path $PSScriptRoot 'KeyWatcher.cs') -ReferencedAssemblies System.Windows.Forms

    try {
        $manager = Wait-Operation ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
    } catch { Write-Log "Media controls unavailable, muting only: $_" }

    # A run that was killed while muted leaves its list behind, so put those apps right first.
    if (Test-Path $mutedFile) {
        $leftMuted = @(Get-Content $mutedFile)
        [AppAudio]::Unmute($leftMuted)
        Remove-Item $mutedFile
        Write-Log "Unmuted [$($leftMuted -join ', ')], left muted by an earlier run"
    }

    $watched = if ($Keys) { $Keys } else { & (Join-Path $PSScriptRoot 'mega_hack_keys.ps1') }
    if (-not $watched) { throw 'No deafen key. Set a shortcut for Auto Deafen in Mega Hack, or run Install.cmd again.' }
    $watcher = [RawKeyWatcher]::new([int[]]($watched -split ','))
    Write-Log "Watching key code(s) $watched"

    $game = $null
    $missingSince = $null
    while ($true) {
        $presses = $watcher.Wait(1000)
        for ($i = 0; $i -lt $presses; $i++) {
            # The key is a toggle, the same as Discord's deafen bind, so this stays in step with Discord.
            $deafened = -not $deafened
            if ($deafened) { Start-Deafen } else { Stop-Deafen }
        }

        if (-not $game -or $game.HasExited) {
            if ($deafened) { Stop-Deafen; $deafened = $false }
            $game = Get-Game
            if ($game) {
                $missingSince = $null
            } elseif (-not $missingSince) {
                $missingSince = Get-Date
            } elseif (((Get-Date) - $missingSince).TotalSeconds -ge $GraceSeconds) {
                break
            }
        }
    }
    Write-Log 'Game closed, exiting'
} catch {
    Write-Log "Error: $_"
} finally {
    if ($deafened) { Stop-Deafen }
    $mutex.ReleaseMutex()
}

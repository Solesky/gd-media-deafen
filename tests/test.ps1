# Tests everything against a stand-in game and a silent stand-in player, using F24 and Shift as the deafen keys.
# It works in a temporary copy, so your real settings, log and shortcuts are left alone, and it only pauses and
# mutes the stand-in, so anything you're listening to keeps playing. Don't play GD while it runs.
#
# Run it with: powershell -NoProfile -ExecutionPolicy Bypass -File tests\test.ps1
$repo = Split-Path $PSScriptRoot
$work = Join-Path $PSScriptRoot "work-$PID"
$desktop = Join-Path $work 'fake_desktop'
$installDesktop = Join-Path $work 'fake_desktop_for_install'
$fakeAppData = Join-Path $work 'fake_appdata'
$megaHackFolder = Join-Path $fakeAppData 'GeometryDash\geode\mods\absolllute.megahack\v9'
New-Item -ItemType Directory $desktop, $installDesktop, $megaHackFolder -Force | Out-Null
Copy-Item (Join-Path $repo '*') $work -Include *.ps1, *.cs, apps.txt, Install.cmd

$log = Join-Path $work 'media_deafen.log'
$modeFile = Join-Path $work 'mode.txt'
$mutedFile = Join-Path $work 'muted_apps.txt'
$pingExe = "$env:WINDIR\System32\PING.EXE"
$realAppData = $env:LOCALAPPDATA
$F24 = 0x87
$Shift = 0x10

Add-Type -Path (Join-Path $work 'AppAudio.cs')
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TestKeys {
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    public static void Down(byte vk) { keybd_event(vk, 0, 0, UIntPtr.Zero); }
    public static void Up(byte vk) { keybd_event(vk, 0, 2, UIntPtr.Zero); }
}
'@

Add-Type -AssemblyName System.Runtime.WindowsRuntime
[void][Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType = WindowsRuntime]
$asTask = [WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
$managerType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]
$managerTask = $asTask.MakeGenericMethod($managerType).Invoke($null, @($managerType::RequestAsync()))
[void]$managerTask.Wait(3000)
$manager = $managerTask.Result

$script:passed = 0
$script:failed = 0
function Report($ok, $label, $detail = '') {
    if ($ok) { $script:passed++; "  ok    $label" } else { $script:failed++; "  FAIL  $label $detail" }
}

function Press-Keys([byte[]]$Codes) {
    foreach ($code in $Codes) { [TestKeys]::Down($code) }
    [array]::Reverse($Codes)
    foreach ($code in $Codes) { [TestKeys]::Up($code) }
}

function Get-StandIn { $manager.GetSessions() | Where-Object { $_.SourceAppUserModelId -eq 'powershell.exe' } | Select-Object -First 1 }

function Invoke-Media($operation) { [void]$asTask.MakeGenericMethod([bool]).Invoke($null, @($operation)).Wait(3000) }

# Waits first, so a pause that follows a mute can't slip past, then allows a little longer for anything slow.
function Check-Player($label, $playback, $muted) {
    Start-Sleep -Seconds 2
    $deadline = (Get-Date).AddSeconds(4)
    do {
        $actualPlayback = "$((Get-StandIn).GetPlaybackInfo().PlaybackStatus)"
        $actualMuted = [bool](([AppAudio]::Describe() -match '^powershell: playing') -match 'muted')
        $ok = $actualPlayback -eq $playback -and $actualMuted -eq $muted
        if (-not $ok) { Start-Sleep -Milliseconds 300 }
    } while (-not $ok -and (Get-Date) -lt $deadline)
    Report $ok $label "(expected $playback, muted=$muted; got $actualPlayback, muted=$actualMuted)"
}

function Wait-ForLog($text, $seconds = 30) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path $log) -and (Select-String -Path $log -Pattern $text -SimpleMatch -Quiet)) { return $true }
        Start-Sleep -Milliseconds 200
    }
    $false
}

function Set-MegaHackShortcut($json) {
    Set-Content (Join-Path $megaHackFolder 'hackpro.json') "{`n  `"LEVEL/AUTO_DEAFEN/DROPDOWN/SHORTCUT`": $json,`n  `"OTHER`": 1`n}"
}

function Start-Game { Start-Process $pingExe -ArgumentList '-n 900 127.0.0.1' -WindowStyle Hidden -PassThru }

function Start-Listener {
    param([string[]]$Extra = @(), [string]$Game = $pingExe, [switch]$NoWait)
    Remove-Item $log -ErrorAction SilentlyContinue
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$work\media_deafen.ps1`"", '-GameExe', "`"$Game`"", '-MediaApps', 'powershell', '-OnlyPause', 'powershell.exe', '-GraceSeconds', '2') + $Extra
    $env:LOCALAPPDATA = $fakeAppData
    $process = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList $arguments
    $env:LOCALAPPDATA = $realAppData
    if (-not $NoWait) { [void](Wait-ForLog 'Watching') }
    $process
}

function Stop-All($processes) { foreach ($process in $processes) { if ($process) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } } }

function Switch-Mode($expected) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$work\switch_mode.ps1" -ShortcutFolder $desktop
    Report ((Get-Content $modeFile) -eq $expected -and (Test-Path (Join-Path $desktop "GD set to $expected.lnk"))) "switched to $expected, and the shortcut's name shows it"
}

function Get-ShortcutArguments($folder, $name) { (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $folder "$name.lnk")).Arguments }

# 3 seconds of 16-bit mono silence at 44.1 kHz.
$wav = Join-Path $work 'silence.wav'
$samples = New-Object byte[] 264600
$writer = New-Object IO.BinaryWriter ([IO.File]::Create($wav))
$writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int](36 + $samples.Length)); $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
$writer.Write([int]16); $writer.Write([int16]1); $writer.Write([int16]1); $writer.Write([int]44100); $writer.Write([int]88200); $writer.Write([int16]2); $writer.Write([int16]16)
$writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([int]$samples.Length); $writer.Write($samples); $writer.Close()

# WinRT's player gives the stand-in a media session, and SoundPlayer gives it an entry in the volume mixer.
$playerScript = Join-Path $work 'silent_player.ps1'
@"
[void][Windows.Media.Playback.MediaPlayer, Windows.Media.Playback, ContentType = WindowsRuntime]
[void][Windows.Media.Core.MediaSource, Windows.Media.Core, ContentType = WindowsRuntime]
`$p = New-Object Windows.Media.Playback.MediaPlayer
`$p.Source = [Windows.Media.Core.MediaSource]::CreateFromUri([uri]'$wav')
`$p.IsLoopingEnabled = `$true
`$p.Play()
`$s = New-Object System.Media.SoundPlayer '$wav'
`$s.PlayLooping()
Start-Sleep -Seconds 900
"@ | Set-Content $playerScript

$others = @{}
$manager.GetSessions() | ForEach-Object { $others[$_.SourceAppUserModelId] = "$($_.GetPlaybackInfo().PlaybackStatus)" }
[AppAudio]::Unmute(@('powershell'))
$player = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$playerScript`"")
$game = $null
$listener = $null
try {
    Start-Sleep -Seconds 4
    Check-Player 'the stand-in starts playing, not muted' 'Playing' $false

    '--- Mega Hack shortcut, one key ---'
    Set-MegaHackShortcut "[`n    135`n  ]"
    New-Item -ItemType File (Join-Path $desktop 'GD set to PAUSE.lnk') | Out-Null
    $game = Start-Game
    $listener = Start-Listener
    Report (Select-String -Path $log -Pattern 'Watching key code(s) 135' -SimpleMatch -Quiet) 'reads the key from the settings file'
    Press-Keys $F24
    Check-Player 'with no mode set, it pauses and mutes' 'Paused' $true
    Press-Keys $F24
    Check-Player 'the next press resumes and unmutes' 'Playing' $false

    '--- MUTE mode ---'
    Switch-Mode 'MUTE'
    Press-Keys $F24
    Check-Player 'it mutes and keeps playing' 'Playing' $true
    Press-Keys $F24
    Check-Player 'the next press unmutes' 'Playing' $false

    '--- switching during a run ---'
    Press-Keys $F24
    Start-Sleep -Seconds 1
    Switch-Mode 'PAUSE'
    Press-Keys $F24
    Check-Player 'switching to PAUSE during a muted run still unmutes' 'Playing' $false
    Press-Keys $F24
    Check-Player 'the next deafen uses the new mode' 'Paused' $true
    Switch-Mode 'MUTE'
    Press-Keys $F24
    Check-Player 'switching to MUTE during a paused run still resumes' 'Playing' $false

    '--- holding the key ---'
    [TestKeys]::Down($F24); [TestKeys]::Down($F24); [TestKeys]::Down($F24); [TestKeys]::Up($F24)
    Check-Player 'holding it down counts as one press' 'Playing' $true
    Press-Keys $F24
    Check-Player 'the next press unmutes' 'Playing' $false

    '--- something you paused yourself ---'
    Switch-Mode 'PAUSE'
    Invoke-Media (Get-StandIn).TryPauseAsync()
    Press-Keys $F24
    Check-Player 'deafen mutes it' 'Paused' $true
    Press-Keys $F24
    Check-Player 'undeafen unmutes it but leaves it paused' 'Paused' $false
    Invoke-Media (Get-StandIn).TryPlayAsync()
    Switch-Mode 'MUTE'

    '--- the game closes during a run ---'
    Press-Keys $F24
    Check-Player 'deafen mutes it' 'Playing' $true
    Report (Test-Path $mutedFile) 'it keeps a list of what it muted'
    Stop-Process -Id $game.Id -Force
    Report $listener.WaitForExit(30000) 'it exits by itself'
    Check-Player 'closing the game unmutes it' 'Playing' $false
    Report (-not (Test-Path $mutedFile)) 'the list is gone'
    Report (Select-String -Path $log -Pattern 'Game closed, exiting' -SimpleMatch -Quiet) 'the log says the game closed'

    '--- killed while muted, then started again ---'
    $game = Start-Game
    $listener = Start-Listener
    Press-Keys $F24
    Check-Player 'deafen mutes it' 'Playing' $true
    Stop-All $listener
    Start-Sleep -Seconds 1
    Check-Player 'it stays muted after the script is killed' 'Playing' $true
    $listener = Start-Listener
    Check-Player 'starting again unmutes it' 'Playing' $false
    Report (Select-String -Path $log -Pattern 'left muted by an earlier run' -SimpleMatch -Quiet) 'the log says why'
    Stop-All $listener

    '--- key combinations ---'
    Set-MegaHackShortcut '[16, 135]'
    $listener = Start-Listener
    Press-Keys $F24
    Check-Player 'the key alone does nothing' 'Playing' $false
    Press-Keys $Shift
    Check-Player 'the modifier alone does nothing' 'Playing' $false
    Press-Keys $Shift, $F24
    Check-Player 'the combination counts' 'Playing' $true
    Press-Keys $Shift, $F24
    Check-Player 'pressing it again unmutes' 'Playing' $false
    Press-Keys $F24, $Shift
    Check-Player 'the order of the keys does not matter' 'Playing' $true
    Press-Keys $Shift, $F24
    Check-Player 'pressing it again unmutes' 'Playing' $false
    Stop-All $listener

    Set-MegaHackShortcut '[160, 135]'
    $listener = Start-Listener
    Press-Keys $Shift, $F24
    Check-Player 'a shortcut saved as left Shift matches Shift' 'Playing' $true
    Press-Keys $Shift, $F24
    Check-Player 'pressing it again unmutes' 'Playing' $false
    Stop-All $listener

    $listener = Start-Listener -Extra @('-Keys', '135')
    Press-Keys $F24
    Check-Player '-Keys overrides the settings file' 'Playing' $true
    Press-Keys $F24
    Check-Player 'pressing it again unmutes' 'Playing' $false
    Stop-All $listener
    Stop-All $game

    '--- problems it should report ---'
    Set-MegaHackShortcut '[]'
    $game = Start-Game
    $listener = Start-Listener -NoWait
    Report (Wait-ForLog 'No deafen key') 'with no key anywhere, the log says so'
    Report $listener.WaitForExit(15000) 'and it exits'
    Stop-All $listener
    Stop-All $game
    $listener = Start-Listener -NoWait -Game 'C:\does\not\exist\NotAGame.exe' -Extra @('-Keys', '135')
    Report (Wait-ForLog 'Could not start the game') 'with a wrong game path, the log says so'
    Report $listener.WaitForExit(30000) 'and it exits'
    Stop-All $listener

    '--- installer ---'
    $zipFolder = Join-Path $work 'fake.zip'
    New-Item -ItemType Directory $zipFolder | Out-Null
    Copy-Item "$work\install.ps1" $zipFolder
    [void](& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$zipFolder\install.ps1" -GameExe $pingExe -Keys 135 -ShortcutFolder $installDesktop)
    Report ($LASTEXITCODE -eq 1 -and -not (Get-ChildItem $installDesktop)) 'refuses to run from inside a ZIP'

    [void](& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$work\install.ps1" -GameExe 'C:\does\not\exist.exe' -Keys 135 -ShortcutFolder $installDesktop)
    Report ($LASTEXITCODE -eq 1 -and -not (Get-ChildItem $installDesktop)) 'stops if the game path is wrong'

    Set-MegaHackShortcut '[45]'
    $env:LOCALAPPDATA = $fakeAppData
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$work\install.ps1" -GameExe $pingExe -ShortcutFolder $installDesktop
    $env:LOCALAPPDATA = $realAppData
    $arguments = Get-ShortcutArguments $installDesktop 'Geometry Dash (Media Deafen)'
    Report (($output -join ' ') -match 'Mega Hack \(key code 45\)' -and $arguments -notmatch '-Keys') 'follows Mega Hack if it has a shortcut'

    $steamGame = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$work\install.ps1" -Keys 135 -ShortcutFolder $installDesktop | Select-String '^Geometry Dash: '
    if ($steamGame) {
        $path = $steamGame.Line.Substring('Geometry Dash: '.Length)
        Report ((Test-Path $path) -and (Get-ShortcutArguments $installDesktop 'Geometry Dash (Media Deafen)') -match [regex]::Escape($path)) "finds the game in Steam: $path"
    } else { '  skip  Steam copy of the game not found on this PC' }

    # The real shortcuts, opened the way a double-click would open them. MUTE mode and apps.txt keep this to the stand-in.
    if ($script:failed -eq 0) {
        Set-Content $modeFile 'MUTE'
        Set-Content "$work\apps.txt" "# only the stand-in`npowershell"
        '' | & "$work\Install.cmd" -GameExe $pingExe -Keys 135 -ShortcutFolder $installDesktop | Out-Null
        $gameLink = Join-Path $installDesktop 'Geometry Dash (Media Deafen).lnk'
        Report ((Test-Path $gameLink) -and (Test-Path (Join-Path $installDesktop 'GD set to MUTE.lnk'))) 'Install.cmd makes both shortcuts, named for the current mode'
        Report (@(Get-ChildItem $installDesktop -Filter 'GD set to *.lnk').Count -eq 1) 'running it again leaves one switch shortcut'

        $game = Start-Game
        Remove-Item $log -ErrorAction SilentlyContinue
        Start-Process explorer.exe -ArgumentList "`"$gameLink`""
        Report (Wait-ForLog 'Watching key code(s) 135') 'the game shortcut starts the script'
        Press-Keys $F24
        Check-Player 'a press mutes what apps.txt lists' 'Playing' $true
        Press-Keys $F24
        Check-Player 'the next press unmutes' 'Playing' $false
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$work*media_deafen*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        Stop-All $game

        Start-Process explorer.exe -ArgumentList "`"$(Join-Path $installDesktop 'GD set to MUTE.lnk')`""
        $deadline = (Get-Date).AddSeconds(15)
        while (-not (Test-Path (Join-Path $installDesktop 'GD set to PAUSE.lnk')) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
        Start-Sleep -Milliseconds 500
        Report ((Get-Content $modeFile) -eq 'PAUSE' -and (Test-Path (Join-Path $installDesktop 'GD set to PAUSE.lnk'))) 'the switch shortcut switches and renames itself'
    } else { '  skip  real shortcut test, because something above failed' }

    $changed = @($manager.GetSessions() | Where-Object { $_.SourceAppUserModelId -ne 'powershell.exe' -and $others.ContainsKey($_.SourceAppUserModelId) -and $others[$_.SourceAppUserModelId] -ne "$($_.GetPlaybackInfo().PlaybackStatus)" })
    Report ($changed.Count -eq 0) 'anything else that was playing is unchanged' "($($changed.SourceAppUserModelId -join ', '))"
} finally {
    Stop-All $listener
    Stop-All $game
    Stop-All $player
    $env:LOCALAPPDATA = $realAppData
    [AppAudio]::Unmute(@('powershell'))
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$work*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
''
"$($script:passed) passed, $($script:failed) failed"
if ($script:failed) { exit 1 }

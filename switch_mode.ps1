# Switches what happens to background media when Auto Deafen fires: PAUSE pauses and mutes it, and MUTE only
# mutes it, for live streams. media_deafen.ps1 reads mode.txt on every press, so this works while GD is open.
# The desktop shortcut that runs this is renamed to show the current mode.
param(
    [string]$ShortcutFolder = [Environment]::GetFolderPath('Desktop')
)

$modeFile = Join-Path $PSScriptRoot 'mode.txt'
$mode = if ((Get-Content $modeFile -ErrorAction SilentlyContinue) -eq 'MUTE') { 'PAUSE' } else { 'MUTE' }
Set-Content $modeFile $mode
Get-ChildItem $ShortcutFolder -Filter 'GD set to *.lnk' | Rename-Item -NewName "GD set to $mode.lnk"

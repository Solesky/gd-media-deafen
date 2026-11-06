# Finds Geometry Dash and your deafen key, then puts two shortcuts on your desktop.
# Run it again any time to update them, such as after moving this folder or changing your key.
param(
    [string]$GameExe = '',   # where GeometryDash.exe is, instead of searching Steam for it
    [string]$Keys = '',      # virtual key codes to watch, like "17,16,191", instead of using Mega Hack's shortcut or asking
    [string]$ShortcutFolder = [Environment]::GetFolderPath('Desktop')   # for testing: put the shortcuts in this folder
)
$ErrorActionPreference = 'Stop'

# Windows runs files inside a ZIP from a temporary copy that gets deleted, which would break the shortcuts.
if ($PSScriptRoot -match '\.zip') {
    'Extract the ZIP to a folder first, then run Install.cmd from there.'
    exit 1
}

function Find-Game {
    $running = Get-Process GeometryDash -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($running -and $running.Path) { return $running.Path }

    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) { $steam = "${env:ProgramFiles(x86)}\Steam" }
    $libraries = @($steam)
    $folders = "$steam\steamapps\libraryfolders.vdf"
    if (Test-Path $folders) {
        $libraries = @([regex]::Matches((Get-Content $folders -Raw), '"path"\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }) + $libraries
    }
    # Built as text because Join-Path fails on a drive that isn't plugged in, and a Steam library can be on one.
    foreach ($library in $libraries) {
        $exe = "$library\steamapps\common\Geometry Dash\GeometryDash.exe"
        if (Test-Path $exe) { return $exe }
    }
}

# Uses RawUI because [Console]::ReadKey skips combinations like Alt+Insert. Pressing Shift, Ctrl, Alt or the
# Windows key on the way to the real key doesn't count as the answer.
function Read-KeyCombination {
    do { $press = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC') } while ($press.VirtualKeyCode -in 16, 17, 18, 91, 92)
    $state = [int]$press.ControlKeyState
    $codes = @()
    if ($state -band 12) { $codes += 17 }   # left or right Ctrl
    if ($state -band 16) { $codes += 16 }   # Shift
    if ($state -band 3) { $codes += 18 }    # left or right Alt
    ($codes + $press.VirtualKeyCode) -join ','
}

function New-Shortcut($name, $script, $arguments, $icon) {
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $ShortcutFolder "$name.lnk"))
    $link.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $link.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $PSScriptRoot $script)`" $arguments"
    $link.WorkingDirectory = $PSScriptRoot
    $link.IconLocation = $icon
    $link.WindowStyle = 7
    $link.Save()
}

if (-not $GameExe) { $GameExe = Find-Game }
if (-not $GameExe) { $GameExe = (Read-Host 'Could not find Geometry Dash. Paste the full path to GeometryDash.exe').Trim('" ') }
if (-not (Test-Path $GameExe)) {
    "Could not find $GameExe, so nothing was changed."
    exit 1
}
"Geometry Dash: $GameExe"

if (-not $Keys) {
    $megaHackKeys = & (Join-Path $PSScriptRoot 'mega_hack_keys.ps1')
    if ($megaHackKeys) {
        "Deafen key: your Auto Deafen shortcut in Mega Hack (key code $megaHackKeys)"
    } else {
        ''
        'No Auto Deafen shortcut found in Mega Hack.'
        'Press the key or key combination your auto-deafen mod uses.'
        '(If it is also bound in Discord, Discord will deafen, so press it once more afterwards.)'
        $Keys = Read-KeyCombination
    }
}
$gameArguments = "-GameExe `"$GameExe`""
if ($Keys) {
    "Deafen key code(s): $Keys"
    $gameArguments += " -Keys $Keys"
}

$mode = if ((Get-Content (Join-Path $PSScriptRoot 'mode.txt') -ErrorAction SilentlyContinue) -eq 'MUTE') { 'MUTE' } else { 'PAUSE' }
Get-ChildItem $ShortcutFolder -Filter 'GD set to *.lnk' | Remove-Item
New-Shortcut 'Geometry Dash (Media Deafen)' 'media_deafen.ps1' $gameArguments "$GameExe,0"
New-Shortcut "GD set to $mode" 'switch_mode.ps1' "-ShortcutFolder `"$ShortcutFolder`"" "$env:WINDIR\System32\SndVol.exe,0"

''
'Done. There are two new shortcuts on your desktop:'
'  Geometry Dash (Media Deafen): open GD with this from now on, instead of Steam'
"  GD set to $mode`: double-click to switch between PAUSE and MUTE"
''
'Keep this folder where it is, because the shortcuts point to it.'

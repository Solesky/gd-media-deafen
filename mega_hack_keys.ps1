# Prints the shortcut set for Auto Deafen in Mega Hack as virtual key codes, like "17,16,191", or nothing if there isn't one.
$config = Get-ChildItem "$env:LOCALAPPDATA\GeometryDash\geode\mods\absolllute.megahack\v*\hackpro.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($config) {
    $match = [regex]::Match((Get-Content $config.FullName -Raw), '"LEVEL/AUTO_DEAFEN/DROPDOWN/SHORTCUT":\s*\[([\d\s,]+)\]')
    if ($match.Success) { $match.Groups[1].Value -replace '\s', '' }
}

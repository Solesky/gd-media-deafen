# GD Media Deafen

Auto Deafen for your background audio. When your auto-deafen mod deafens Discord at a set percentage in Geometry Dash, this also pauses or mutes whatever you're listening to, like YouTube, Kick, Twitch, Spotify or a podcast. It all comes back when the mod undeafens, such as when you die or finish.

## What you need

- Windows 10 or 11 (tested on Windows 11)
- The Steam version of Geometry Dash
- A mod that presses a key at your chosen percentage

**Mega Hack v9** is the only mod this has been tested with, and your key is detected automatically. Other mods that press a key, such as [AutoDeafen+](https://geode-sdk.org/mods/okayscylla.autodeafenplus), should work too: the installer asks you to press the key.

Mods that talk to Discord directly without pressing a key, such as [AutoDeafen](https://geode-sdk.org/mods/lynxdeer.autodeafen), won't work.

## Install

1. Click **Code > Download ZIP** at the top of this page, and extract it to a folder you'll keep.
2. In Mega Hack, turn on Auto Deafen, set your percentage, and give it a shortcut, using the same key you use for deafen in Discord. Pick a key you don't type with, such as Insert, because pressing it by hand counts too.
3. Double-click `Install.cmd`. If Windows warns you about it, click **More info > Run anyway**.
4. From now on, open GD with the new **Geometry Dash (Media Deafen)** desktop shortcut instead of Steam.

Your mod's settings decide when it fires, including the percentage and whether it works in practice mode or from a start position.

## Pause or mute

The installer also adds a desktop icon called **GD set to PAUSE**. Double-click it to switch modes, and its name changes to show the current one. You can switch with GD open, and it applies the next time Auto Deafen fires.

| Mode | What happens | Good for |
|---|---|---|
| **PAUSE** | Pauses and mutes, then resumes and unmutes | Videos and podcasts |
| **MUTE** | Keeps playing silently, then unmutes | Live streams, which would fall behind if paused |

## Other apps

Pausing works on anything that shows up in Windows' media controls. Muting covers the browsers and players listed in `apps.txt`, and you can add more there using the name of the app's `.exe` file. Nothing else is touched, including GD, Discord and OBS.

## Troubleshooting

- **Nothing happens:** GD has to be opened through the shortcut. If it's already open, double-click the shortcut anyway. That starts the script without opening a second GD.
- **It's backwards, and pauses when you die:** it counts key presses, so it gets out of step if it started during a run past your percentage. Close GD and reopen it from the shortcut.
- **It stopped working while GD was open:** double-click the shortcut again.
- **An app stayed muted:** open GD from the shortcut again, which fixes anything left muted, or unmute it in Windows' volume mixer.
- **Anything else:** `media_deafen.log` in this folder records what happened on each press in the current session.

## How it works

It doesn't touch the game or its memory. The only game-related file it reads is Mega Hack's settings file, to find your key.

- **Watching for the key:** it uses Windows' Raw Input, which only observes, so it adds no delay to your inputs. It ignores every other key, records nothing, and never connects to the internet.
- **Pausing:** it uses Windows' media controls, the same ones your keyboard's media keys use. It only resumes what it paused, so anything you paused yourself stays paused.
- **Muting:** it uses the same per-app mute as Windows' volume mixer.

It runs on PowerShell, which comes with Windows, so there's nothing else to install. All of the code is plain text in this folder if you want to read it.

## Uninstall

Delete the two desktop shortcuts and this folder. The installer doesn't add anything else.

## Similar projects

- [Music Integrations](https://geode-sdk.org/mods/vinsterplays.music_integrations): pauses your media when you enter a level, and has an in-game overlay for controlling it.
- [GDUtils](https://github.com/Jouca/GDUtils-Geode): among other things, mutes Spotify while you're in a level.
- [Gamebar Autodeafen](https://github.com/itsobrie/gamebar-autodeafen-gb): mutes Xbox Game Bar party chat at a percentage.

## Testing changes

`tests\test.ps1` runs everything against a stand-in game and a silent stand-in player, so it won't interrupt anything you're listening to:

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test.ps1
```

Not affiliated with RobTop Games, Geode or Mega Hack.

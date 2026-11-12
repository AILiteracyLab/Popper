# Building Popper

## Prerequisites

- [AutoHotkey v2](https://www.autohotkey.com/), installed machine-wide in `C:\Program Files\AutoHotkey` or per-user in `%LOCALAPPDATA%\Programs\AutoHotkey`
- The Ahk2Exe compiler. AutoHotkey's Dash offers to add it, or run `UX\install-ahk2exe.ahk` from the AutoHotkey folder

If AutoHotkey is somewhere else, set `AHK_ROOT` first:

```
set AHK_ROOT=D:\Tools\AutoHotkey
```

## Self-test

```
scripts\selftest.bat
scripts\selftest.bat http://your-server:8000 Systran/faster-whisper-small
```

The self-test uses a throwaway settings folder in `%TEMP%`, so your real settings and recordings are safe. It checks settings, key encryption, device listing, 7 seconds of real capture from both tracks with a Windows sound played for the loopback track, crash repair, microphone detection and transcript merging. Given a server URL, it also sends real uploads. Set `POPPER_TEST_KEY` if the server needs a key.

## Compile

```
scripts\compile.bat
```

This writes `build\Popper.exe` and copies the tray icons to `build\assets\`.

## Installer

```
scripts\build-all.bat
```

This compiles Popper, then `installer\Uninstall.ahk`, then `installer\Setup.ahk`, and writes `build\Popper-Setup.exe`. Setup is one file: it packs Popper, the uninstaller, the icons and the licence inside it with `FileInstall`. Share that file.

Setup installs per-user to `%LOCALAPPDATA%\Programs\Popper`. It adds a Start menu entry, a startup entry (on by default) and an entry in Settings > Apps, and needs no administrator rights. Running it again over an existing install upgrades in place. It closes a running Popper first, so a call in progress is saved.

The uninstaller removes only the files Setup put there. It keeps recordings and transcripts, and keeps settings unless the user ticks the box.

## Releasing an update

Installed copies check `APP_REPO`'s latest GitHub release once a week, and on **Check now** in Settings > About.

1. Set the new version in `src\main.ahk` (`APP_VERSION` and `;@Ahk2Exe-SetVersion`), `installer\Setup.ahk` (the same two) and `installer\Uninstall.ahk` (`;@Ahk2Exe-SetVersion`).
2. Move the changelog's Unreleased notes under the new version.
3. Run `scripts\build-all.bat`.
4. Publish a release whose tag is the version, such as `0.2.0`, with `build\Popper-Setup.exe` attached:

```
gh release create 0.2.0 build\Popper-Setup.exe --title "Popper 0.2.0" --notes "..."
```

The updater picks the first attached `.exe` with `Setup` in its name, downloads it and runs it with `/upgrade`.

## Layout

| Path | What it does |
|------|--------------|
| `src/main.ahk` | Entry point |
| `src/core/app.ahk` | Ties detection, recording and transcription together |
| `src/core/wasapi.ahk` | Microphone and loopback capture through WASAPI |
| `src/core/recorder.ahk` | Writes each track as WAV pieces, padded to wall-clock time |
| `src/core/detector.ahk` | Reads which app holds the microphone |
| `src/core/sessions.ahk` | One folder per call, with its state in `session.ini` |
| `src/core/transcriber.ahk` | The upload queue, using the Windows `curl.exe` |
| `src/core/merger.ahk` | Builds the transcript from both tracks |
| `src/providers/profiles.ahk` | Transcription services the user adds |
| `src/ui/` | Tray, recording bar, main window, settings and editors |

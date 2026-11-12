# Popper

Backup meeting transcription for Windows.

Someone forgot to press record in Teams. Popper didn't. It notices when a call takes your microphone, records both sides, and leaves a transcript in a folder when the call ends. No bot joins the call and nothing is sent anywhere except the transcription service you choose.

## How it works

1. **Popper sits in the system tray.** It checks every two seconds which app is using your microphone, using the same list Windows keeps for the mic icon in the taskbar.
2. **A call starts.** When Teams, Zoom, Webex, Slack or another app you add takes the mic, Popper starts recording and shows a small bar with Stop and Discard buttons.
3. **Two tracks.** Your microphone is one track. What your speakers play, which is everyone else, is the other. That gives each line of the transcript a speaker, you or them, without any speaker-recognition model.
4. **The call ends.** Twenty seconds after the app lets go of the mic, Popper stops. Audio goes to your transcription service in five-minute pieces, during the call if you like, so the transcript is ready soon after you hang up.
5. **You get a folder.** `transcript.md`, captions in `transcript.vtt`, and the audio, which Popper deletes after 30 days unless you change that.

If the service is offline, Popper keeps the audio and tries again every minute. If Popper or Windows crashes mid-call, the audio up to that moment is repaired and transcribed on the next start.

## Features

- **Automatic recording** for any app you choose, with Teams, Zoom, Webex and Slack on by default
- **Add your own apps** by name, or pick one from the list of apps that recently used your mic
- **Add your own transcription services**: OpenAI, Groq, or your own server such as Speaches or faster-whisper-server. Keep several and switch between them
- **Names and terms list** so Whisper spells your colleagues and products correctly
- **Echo removal** for when you use speakers instead of a headset
- **Manual recording** from the window, the tray or an optional hotkey
- **Follows your headset** when you plug it in mid-call
- **Light and dark themes**
- **No analytics.** Popper sends nothing to its authors

## Getting started

### Install

1. Download `Popper-Setup.exe` from the latest release.
2. Run it. It installs for your Windows account only, so it needs no administrator rights.
3. Leave **Start Popper when I sign in to Windows** ticked. Popper can only catch a call while it is running.
4. Popper opens its settings. On the Transcription tab, press **Add** and set up a service.

Setup is not code-signed, so Windows SmartScreen may warn you. Choose **More info**, then **Run anyway**. To remove Popper, use Settings > Apps > Installed apps. Your recordings and transcripts are kept.

### From source

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone this repository.
3. Run `src\main.ahk`.
4. Popper opens its settings. On the Transcription tab, press **Add** and set up a service.

### Setting up a service

| Type | Server URL | Model | Key |
|------|------------|-------|-----|
| Your own Speaches or faster-whisper-server | `http://your-server:8000` | press **List models** | usually none |
| OpenAI | `https://api.openai.com` | `whisper-1` | needed |
| Groq | `https://api.groq.com/openai` | `whisper-large-v3-turbo` | needed |

Popper adds `/v1/audio/transcriptions` to the server URL and asks for `verbose_json`, so it works with any server that speaks the OpenAI transcription API and returns segments with timestamps. Press **Test** to send one second of silence through the real endpoint.

For a self-hosted Speaches server, add `vad_filter=true` under Extra fields. It skips the silent parts of each piece.

## Settings

| Tab | What it covers |
|-----|----------------|
| **General** | Start with Windows, your name and the label for everyone else, theme, hotkey |
| **Detection** | Which apps start a recording, how long to wait after a call ends, the recording bar |
| **Transcription** | Your services, language, names and terms, transcribing during the call |
| **Audio** | Which microphone and which speakers to record, upload piece length |
| **Output** | Recordings folder, how long to keep audio, extra file types |
| **About** | Version, links and where Popper keeps its files |
| **Disclaimer** | Recording consent, privacy and accuracy |

Settings live in `%AppData%\Popper\settings.ini`. Recordings go to `%USERPROFILE%\Popper` by default. That folder is outside OneDrive on purpose, so call audio does not sync to the cloud unless you choose a synced folder.

## Recording people

Tell the people on a call that you are recording. In many places the law requires it, and your employer or client may have rules too. Popper's bar is on your screen only, so the others cannot see it. Saying "I'm taking a recording for my notes" at the start covers it.

## Privacy

- Audio is saved locally and sent only to the transcription service you set up
- API keys are encrypted with Windows DPAPI, per user and per machine
- The log at `%AppData%\Popper\popper.log` records events and errors, never transcript text or keys
- No analytics, no update pings, no accounts

## Limits

- **Two speakers.** Everyone on the far end is labelled with one name. Telling them apart needs a speaker-recognition model, which Popper does not include.
- **Five-minute pieces.** A word that falls exactly on a piece boundary can be split or lost.
- **Audio from the selected speaker device only.** If your calls play through a device that is not the one Popper records, choose it on the Audio tab.

## Building

See [BUILDING.md](BUILDING.md).

## Inspiration

Popper was written from scratch. These open-source projects shaped the idea of recording both sides locally and labelling speakers by track:

- [Meetily](https://github.com/Zackriya-Solutions/meetily)
- [Anarlog, formerly Hyprnote](https://github.com/fastrepl/anarlog)

No code was copied from them.

## Requirements

- Windows 10 or 11
- A transcription service: your own server, or an OpenAI or Groq API key
- AutoHotkey v2, only if running from source

## Licence

CC BY-NC-ND 4.0 (Creative Commons Attribution-NonCommercial-NoDerivatives). See [LICENSE](LICENSE).

`src/lib/cJson.ahk` is by Philip Taylor (G33kDude) under the 0BSD licence.

## Developer

(c) 2026 Jamie Bykov-Brett - [Bykov-Brett Enterprises](https://bykovbrett.net/)

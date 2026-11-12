# Changelog

## [0.1.0] - 2026-11-12

First public release.

### Added
- Installer: one `Popper-Setup.exe`, per-user, no administrator rights, in the wizard style of the other AI Literacy Lab apps
- Setup turns on "Start Popper when I sign in" by default, since Popper only catches calls while it runs
- Uninstaller in Settings > Apps that keeps recordings, and keeps settings unless asked
- `scripts\build-installer.bat` and `scripts\build-all.bat`
- Updates from GitHub releases: a weekly check (can be turned off), a "Check now" button on the About tab, and a tray item when a new version is out. Installing runs Setup with `/upgrade`, which keeps your choices and reopens Popper

### Changed
- Example profile names in comments and tests are generic

### Fixed
- Build scripts find a per-user AutoHotkey install

### Added in the first build
- Automatic recording when a watched app takes the microphone, read from the Windows microphone privacy list
- Watched apps list with Teams, Zoom, Webex and Slack on by default, browsers off, and an "add an app that used the mic" picker
- Two-track capture through WASAPI: your microphone, and loopback of the speaker device for everyone else
- 16 kHz mono WAV pieces padded to wall-clock time, so the two tracks line up
- Recording bar with Stop, Discard and hide, draggable, never takes focus
- Transcription profiles for any OpenAI-compatible service, with presets for OpenAI, Groq and self-hosted Speaches or faster-whisper-server
- Test and List models buttons for each profile
- DPAPI-encrypted API keys
- Upload queue on disk that survives restarts, retries offline servers every minute and backs off on server errors
- Crash recovery that repairs and transcribes audio from an interrupted call
- Transcript in Markdown with optional captions (VTT) and plain text
- Echo removal for calls on speakers, and filtering of Whisper's silence ghosts
- Main window listing recordings with Open, Folder, Retry and Delete
- Tabbed settings: General, Detection, Transcription, Audio, Output, About, Disclaimer
- Audio retention, 30 days by default
- Self-test script

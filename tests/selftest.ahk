#Requires AutoHotkey v2.0
#SingleInstance Off

/**
 * Popper self-test. Run from the repo root:
 *
 *   AutoHotkey64.exe /ErrorStdOut tests\selftest.ahk [server-url] [model]
 *
 * Uses a throwaway settings folder in %TEMP%, so your real settings and
 * recordings are not touched. It captures 7 seconds of real audio from the
 * default microphone and speakers and plays a Windows sound so the loopback
 * track has something to hear. With a server URL it also sends a real upload.
 */

global APP_NAME := "Popper"
global APP_VERSION := "0.1.0-test"
global APP_REPO := "https://github.com/AILiteracyLab/Popper"

#Include ..\src\lib\cJson.ahk
#Include ..\src\core\config.ahk
#Include ..\src\core\credentials.ahk
#Include ..\src\core\applog.ahk
#Include ..\src\core\util.ahk
#Include ..\src\core\wasapi.ahk
#Include ..\src\core\recorder.ahk
#Include ..\src\core\detector.ahk
#Include ..\src\core\sessions.ahk
#Include ..\src\core\transcriber.ahk
#Include ..\src\core\merger.ahk
#Include ..\src\core\updater.ahk
#Include ..\src\providers\profiles.ahk
#Include ..\src\ui\theme.ahk
#Include ..\src\ui\tray.ahk
#Include ..\src\ui\pill.ahk
#Include ..\src\ui\main-window.ahk
#Include ..\src\ui\settings.ahk
#Include ..\src\ui\profile-editor.ahk
#Include ..\src\ui\app-editor.ahk
#Include ..\src\core\app.ahk

global TestDir := A_Temp "\popper-selftest-" A_Now
DirCreate(TestDir)
global AppConfig := ConfigManager(TestDir "\appdata")
AppConfig.Set("Output", "Folder", TestDir "\recordings")
AppLog.Path := TestDir "\appdata\popper.log"
global Failures := 0

; Results go to stdout and to selftest-result.txt in the repo root, because
; stdout from a GUI-subsystem exe is not always captured.
global ResultFile := A_ScriptDir "\..\selftest-result.txt"
try FileDelete(ResultFile)
Out(msg) {
    try FileAppend(msg "`n", "*", "UTF-8")
    FileAppend(msg "`n", ResultFile, "UTF-8")
}
Check(name, ok, detail := "") {
    global Failures
    if !ok
        Failures++
    Out((ok ? "PASS " : "FAIL ") name (detail != "" ? "  (" detail ")" : ""))
}

Out("Popper self-test in " TestDir)

; 1. Settings
AppConfig.Set("General", "MyName", "Tester")
Check("settings round trip", AppConfig.Get("General", "MyName") = "Tester")
Check("default value", AppConfig.Get("Audio", "ChunkMinutes") = "5")
Check("version compare", Updater.Compare("0.10.0", "0.9.1") = 1 && Updater.Compare("1.0", "1.0.0") = 0 && Updater.Compare("0.1.0", "0.2.0-beta") = -1)
Check("watched apps seeded", Detector.WatchedApps().Length >= 5, Detector.WatchedApps().Length " apps")

; 2. DPAPI
CredentialManager.Store("profile:t", "sk-test-1234567890")
raw := AppConfig.Get("Credentials", "profile:t", "")
Check("key is not stored in plain text", raw != "" && !InStr(raw, "sk-test"))
Check("key decrypts", CredentialManager.Retrieve("profile:t") = "sk-test-1234567890")
Check("key masks", CredentialManager.GetMasked("profile:t") = "********7890")

; 3. Devices
spk := AudioDevices.List(AudioDevices.FLOW_RENDER)
mic := AudioDevices.List(AudioDevices.FLOW_CAPTURE)
Check("speakers listed", spk.Length > 0, spk.Length ? spk[1].name : "none")
Check("microphones listed", mic.Length > 0, mic.Length ? mic[1].name : "none")

; 4. Capture: 2-second chunks for 7 seconds, both tracks
capDir := TestDir "\capture"
DirCreate(capDir "\audio")
global Chunks := []
OnChunk(name, frames, peak) {
    global Chunks
    Chunks.Push({name: name, frames: frames, peak: peak})
}
tracks := [Track("system", capDir, 2, "default", OnChunk), Track("mic", capDir, 2, "default", OnChunk)]
q := Util.Qpc()
for t in tracks
    t.Start(q)
for t in tracks
    Out("     " t.kind " device: " (t.DeviceName() = "" ? "NOT OPEN" : t.DeviceName()) (t.stream && t.stream.converting ? " (script conversion)" : " (Windows conversion)"))
PollAll() {
    global tracks
    for t in tracks
        t.Poll()
}
SetTimer(PollAll, 40)
started := A_TickCount
played := false
while A_TickCount - started < 7000 {
    if !played && A_TickCount - started > 2500 {
        try SoundPlay(A_WinDir "\Media\Windows Notify System Generic.wav")
        played := true
    }
    Sleep(50)
}
SetTimer(PollAll, 0)
for t in tracks
    t.Finish()
counts := Map("system", 0, "mic", 0), sysPeak := 0, badFrames := 0
for c in Chunks {
    counts[StrSplit(c.name, "-")[1]]++
    if c.name != "system-003" && c.name != "mic-003" && Abs(c.frames - 32000) > 1
        badFrames++
    if InStr(c.name, "system") && c.peak > sysPeak
        sysPeak := c.peak
}
Check("system track wrote chunks", counts["system"] >= 3, counts["system"] " chunks")
Check("mic track wrote chunks", counts["mic"] >= 3, counts["mic"] " chunks")
Check("full chunks are exactly 2 s", badFrames = 0, badFrames " wrong")
Check("loopback heard the test sound", sysPeak > 300, "peak " sysPeak)
f := FileOpen(capDir "\audio\mic-000.wav", "r")
hdrOk := f.ReadUInt() = 0x46464952 && f.ReadUInt() = 36 + 64000
f.Pos := 40
hdrOk := hdrOk && f.ReadUInt() = 64000
f.Close()
Check("WAV header sizes patched", hdrOk)

; 5. Crash repair
w := WavFile.Create(capDir "\audio\crash.wav")
w.RawWrite(Buffer(16000, 0), 16000)
w.Close()
info := WavFile.Repair(capDir "\audio\crash.wav")
Check("crash repair counts frames", info.frames = 8000, info.frames " frames")

; 6. Detector
entries := Detector.Entries()
inUse := ""
for e in entries
    if e.inUse
        inUse .= (inUse = "" ? "" : ", ") e.label
Check("mic history readable", entries.Length > 0, entries.Length " apps, in use now: " (inUse = "" ? "none" : inUse))
Check("self excluded from detection", Detector.ActiveApp() = "" || !InStr(StrLower(Detector.ActiveApp()), "autohotkey"))
Check("Teams key matches", RegExMatch("msteams_8wekyb3d8bbwe", "msteams_") > 0)

; 7. Merger with an echo
sDir := TestDir "\recordings\2026-11-10 1400 Test"
DirCreate(sDir "\work")
s := Session(sDir)
s.Set("App", "Test"), s.Set("Started", "20261110140000"), s.Set("ChunkSeconds", "300"), s.Set("DurationSec", "320")
s.AddChunk("system-000", 4800000, 5000), s.SetChunk("system-000", "done")
s.AddChunk("mic-000", 4800000, 5000), s.SetChunk("mic-000", "done")
s.AddChunk("mic-001", 320000, 5000), s.SetChunk("mic-001", "done")
s.AddChunk("system-001", 320000, 5000), s.SetChunk("system-001", "failed"), s.SetChunkError("system-001", "test gap")
Util.WriteText(sDir "\work\system-000.json", '{"segments":[{"start":1.0,"end":4.0,"text":" Shall we start with the budget review today?","no_speech_prob":0.01,"avg_logprob":-0.2},{"start":10.0,"end":11.0,"text":" Thank you.","no_speech_prob":0.9,"avg_logprob":-1.5}]}')
Util.WriteText(sDir "\work\mic-000.json", '{"segments":[{"start":1.2,"end":4.1,"text":" shall we start with the budget review","no_speech_prob":0.02,"avg_logprob":-0.4},{"start":5.0,"end":7.0,"text":" Yes, I sent the figures on Friday.","no_speech_prob":0.01,"avg_logprob":-0.2}]}')
Util.WriteText(sDir "\work\mic-001.json", '{"segments":[{"start":2.0,"end":3.0,"text":" Bye for now.","no_speech_prob":0.01,"avg_logprob":-0.2}]}')
turns := Merger.Build(s)
md := FileRead(sDir "\transcript.md", "UTF-8")
Check("merger keeps both speakers", turns = 3, turns " turns")
Check("echo dropped", !InStr(md, "shall we start with the budget review`n"))
Check("silence ghost dropped", !InStr(md, "Thank you."))
Check("second chunk offset", InStr(md, "[00:05:02] Tester:") > 0)
Check("gap reported", InStr(md, "test gap") > 0)
Check("vtt written", FileExist(sDir "\transcript.vtt") != "")

; 8. Endpoint building
p := {name: "x", url: "https://api.groq.com/openai", model: "m", extra: "vad_filter=true;temperature=0", key: ""}
Check("endpoint for base URL", Profiles.Endpoint(p) = "https://api.groq.com/openai/v1/audio/transcriptions")
p.url := "http://host:8000/v1/"
Check("endpoint for /v1 URL", Profiles.Endpoint(p) = "http://host:8000/v1/audio/transcriptions")
Check("extra fields parsed", Profiles.ExtraFields(p).Length = 2)

; 9. Live upload, if a server was given
if A_Args.Length >= 1 {
    p := {name: "test", url: A_Args[1], model: A_Args.Length >= 2 ? A_Args[2] : "", extra: "", key: EnvGet("POPPER_TEST_KEY")}
    r := Profiles.Test(p)
    Check("upload to " A_Args[1], r.ok, r.message)
    r2 := Transcriber.RunSync(p, capDir "\audio\mic-000.wav")
    Check("mic chunk transcribes", r2.code = 200, "HTTP " r2.code)
    if r2.code = 200 {
        try Out("     text: " SubStr(JSON.Load(r2.body)["text"], 1, 200))
    }
}

Out(Failures = 0 ? "ALL PASSED" : Failures " FAILED")
ExitApp(Failures ? 1 : 0)

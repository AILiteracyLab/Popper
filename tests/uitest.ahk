#Requires AutoHotkey v2.0
#SingleInstance Off

/**
 * Popper interface smoke test. Opens every window off-screen with sample
 * data, saves a PNG of each to tests\screens\, and closes. Nothing records,
 * nothing uploads, and your real settings are not touched.
 *
 *   AutoHotkey64.exe tests\uitest.ahk
 */

global APP_NAME := "Popper"
global APP_VERSION := "0.1.0"
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

global Shots := A_ScriptDir "\screens"
global Report := A_ScriptDir "\screens\uitest-result.txt"
DirCreate(Shots)
try FileDelete(Report)
OnError((e, m) => (FileAppend("ERROR " e.Message " | " e.Extra " | " e.File ":" e.Line "`n" e.Stack "`n", Report, "UTF-8"), -1))
Note(msg) => FileAppend(msg "`n", Report, "UTF-8")

theme := A_Args.Length ? A_Args[1] : "light"
TestDir := A_Temp "\popper-uitest-" A_Now
global AppConfig := ConfigManager(TestDir "\appdata")
AppConfig.Set("Output", "Folder", TestDir "\recordings")
AppConfig.Set("General", "MyName", "Jamie")
AppConfig.Set("General", "Theme", theme)
AppLog.Path := TestDir "\appdata\popper.log"
ThemeManager.Load()
TraySetIcon(Util.AssetPath("icon.ico"))  ; as Tray.Init does in the app
Util.ShowExtra := " x-5000 y50 NoActivate"

Profiles.Save({name: "Home server", preset: Profiles.Presets[1].name, url: "http://whisper.example:8000", model: "Systran/faster-whisper-medium", extra: "vad_filter=true"}, "", "")
Profiles.Save({name: "OpenAI", preset: "OpenAI", url: "https://api.openai.com", model: "whisper-1", extra: ""}, "", "sk-example-0000")
Profiles.SetActive("Home server")

MakeSession(stamp, app, status, secs, chunks) {
    dir := AppConfig.Get("Output", "Folder") "\" FormatTime(stamp, "yyyy-MM-dd HHmm") " " app
    DirCreate(dir "\audio"), DirCreate(dir "\work")
    s := Session(dir)
    s.Set("App", app), s.Set("Started", stamp), s.Set("DurationSec", secs), s.Set("ChunkSeconds", 300), s.Set("Status", status)
    for c in chunks
        s.AddChunk(c[1], 4800000, 5000), s.SetChunk(c[1], c[2])
    if status = "done"
        Util.WriteText(dir "\transcript.md", "# test")
    if status = "failed"
        s.Set("Error", "The server refused the API key.")
    return s
}
MakeSession("20261110093000", "Microsoft Teams", "done", 2843, [["system-000", "done"]])
MakeSession("20261109143000", "Zoom", "partial", 1820, [["system-000", "done"], ["mic-001", "failed"]])
MakeSession("20261110113000", "Microsoft Teams", "processing", 3605, [["system-000", "done"], ["mic-000", "done"], ["system-001", "pending"], ["mic-001", "pending"]])
MakeSession("20261108100000", "Webex", "failed", 610, [["system-000", "failed"]])

Capture(hwnd, name) {
    ; Off-screen windows paint lazily: force every child to paint first.
    DllCall("RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x0185)  ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
    Sleep(700)
    WinGetPos(, , &w, &h, "ahk_id " hwnd)
    hdc := DllCall("GetDC", "ptr", 0, "ptr")
    mdc := DllCall("CreateCompatibleDC", "ptr", hdc, "ptr")
    hbm := DllCall("CreateCompatibleBitmap", "ptr", hdc, "int", w, "int", h, "ptr")
    old := DllCall("SelectObject", "ptr", mdc, "ptr", hbm, "ptr")
    DllCall("PrintWindow", "ptr", hwnd, "ptr", mdc, "uint", 2)
    DllCall("SelectObject", "ptr", mdc, "ptr", old)
    static token := 0
    if !token {
        DllCall("LoadLibrary", "str", "gdiplus", "ptr")
        si := Buffer(24, 0), NumPut("uint", 1, si, 0)
        DllCall("gdiplus\GdiplusStartup", "ptr*", &token, "ptr", si, "ptr", 0)
    }
    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "ptr", hbm, "ptr", 0, "ptr*", &pBmp)
    clsid := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "ptr", clsid)
    path := Shots "\" theme "-" name ".png"
    r := DllCall("gdiplus\GdipSaveImageToFile", "ptr", pBmp, "wstr", path, "ptr", clsid, "ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
    DllCall("DeleteObject", "ptr", hbm), DllCall("DeleteDC", "ptr", mdc), DllCall("ReleaseDC", "ptr", 0, "ptr", hdc)
    Note((r = 0 ? "saved " : "FAILED ") name " " w "x" h)
}

MainWindow.Show()
Sleep(600)
MainWindow.LV.Modify(1, "Select Focus"), MainWindow._UpdateButtons()
Sleep(200)
Capture(MainWindow.Gui.Hwnd, "main")

SettingsWindow.Show()
for i, tab in SettingsWindow.TabNames {
    SettingsWindow.Tabs.Choose(i)
    Sleep(350)
    Capture(SettingsWindow.Gui.Hwnd, "settings-" i "-" StrLower(tab))
}

SettingsWindow.Tabs.Choose(3)
ProfileEditor.Show(SettingsWindow.Gui, "Home server", (n) => 0)
Sleep(400)
Capture(ProfileEditor.Gui.Hwnd, "profile-editor")
ProfileEditor.Close()

AppEditor.Show(SettingsWindow.Gui, {name: "Zoom", enabled: true, matches: ["#zoom.exe"]}, (a) => 0)
Sleep(400)
Capture(AppEditor.Gui.Hwnd, "app-editor")
AppEditor.Close()

Pill.Show("Microsoft Teams")
Sleep(400)
Capture(Pill.Gui.Hwnd, "pill")
Pill.Hide()

SettingsWindow.Close()
Note("done")
try DirDelete(TestDir, true)
ExitApp(0)

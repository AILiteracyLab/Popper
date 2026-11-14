#Requires AutoHotkey v2.0
#SingleInstance Force

/**
 * Popper uninstaller. Setup copies it into the install folder, and Windows
 * runs it from Settings > Apps. It removes only the files Setup installed,
 * so a folder the user also keeps other things in is never emptied.
 * Recordings and transcripts are always kept.
 */

;@Ahk2Exe-SetName Popper Uninstall
;@Ahk2Exe-SetDescription Removes Popper
;@Ahk2Exe-SetVersion 0.1.1
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Jamie Bykov-Brett
;@Ahk2Exe-SetCompanyName Bykov-Brett Enterprises
;@Ahk2Exe-SetMainIcon ..\assets\icon.ico

DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

global UNINSTALL_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Popper"
global RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global InstallDir := A_ScriptDir
global SettingsDir := A_AppData "\Popper"
global Files := ["Popper.exe", "LICENSE.txt", "assets\icon.ico", "assets\recording.ico"]

recordings := RecordingsFolder()

g := Gui("-MaximizeBox -MinimizeBox", "Uninstall Popper")
g.SetFont("s10", "Segoe UI")
g.BackColor := "FFFFFF"
g.SetFont("Bold s14")
g.Add("Text", "x20 y20 w420", "Uninstall Popper")
g.SetFont("Norm s10 c1F2328")
g.Add("Text", "x20 y58 w420", "This removes Popper from this computer, along with its shortcuts and its entry in your Windows startup list.")
g.Add("Text", "x20 y110 w420", "Your recordings and transcripts are kept, in:")
g.Add("Edit", "x20 y132 w420 r1 ReadOnly -Wrap", recordings)
cb := g.Add("Checkbox", "x20 y175 w420", "Also remove my settings and saved API keys")
g.Add("Text", "x38 y198 w402 c666666", "Leave this off if you plan to install Popper again.")
g.Add("Button", "x250 y240 w95 h30 Default", "&Uninstall").OnEvent("Click", (*) => Uninstall(g, cb.Value))
g.Add("Button", "x350 y240 w90 h30", "Cancel").OnEvent("Click", (*) => ExitApp())
g.OnEvent("Close", (*) => ExitApp())
g.OnEvent("Escape", (*) => ExitApp())
g.Show("w460 h290")

RecordingsFolder() {
    folder := ""
    try folder := IniRead(SettingsDir "\settings.ini", "Output", "Folder", "")
    return folder != "" ? folder : EnvGet("USERPROFILE") "\Popper"
}

ClosePopper() {
    if !ProcessExist("Popper.exe")
        return
    DetectHiddenWindows(true)
    for hwnd in WinGetList("ahk_class AutoHotkey ahk_exe Popper.exe")
        try PostMessage(0x0010, 0, 0, , "ahk_id " hwnd)  ; WM_CLOSE saves a call in progress
    if ProcessWaitClose("Popper.exe", 8)
        ProcessClose("Popper.exe")
    Sleep(500)
}

Uninstall(g, removeSettings) {
    g.Opt("+OwnDialogs")
    try {
        ClosePopper()
        if ProcessExist("Popper.exe")
            throw Error("Popper is still running. Close it from the tray and try again.")

        try RegDelete(RUN_KEY, "Popper")
        try FileDelete(A_Programs "\Popper.lnk")
        try FileDelete(A_Desktop "\Popper.lnk")

        for f in Files
            try FileDelete(InstallDir "\" f)

        if removeSettings && DirExist(SettingsDir)
            DirDelete(SettingsDir, true)

        try RegDeleteKey(UNINSTALL_KEY)
    } catch as e {
        MsgBox("Popper could not be fully removed:`n`n" e.Message, "Uninstall Popper", "IconX")
        return
    }

    ; This file is still running, so a short-lived cmd removes it, then the
    ; folders. rmdir without /s only removes a folder that is now empty.
    cmd := 'ping -n 3 127.0.0.1 >nul & del /f /q "' A_ScriptFullPath '"'
        . ' & rmdir "' InstallDir '\assets" & rmdir "' InstallDir '"'
    if A_IsCompiled
        Run(A_ComSpec ' /c "' cmd '"', A_Temp, "Hide")

    MsgBox("Popper has been removed.`n`nYour recordings are still in " recordings ".", "Uninstall Popper", "Iconi")
    ExitApp()
}

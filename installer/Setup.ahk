#Requires AutoHotkey v2.0
#SingleInstance Force

/**
 * Popper Setup. One file: Popper.exe, the uninstaller and the icons are
 * packed inside it with FileInstall. Installs for the current user only,
 * so it needs no administrator rights.
 *
 * Build with scripts\build-installer.bat after scripts\compile.bat.
 */

;@Ahk2Exe-SetName Popper Setup
;@Ahk2Exe-SetDescription Popper Setup
;@Ahk2Exe-SetVersion 0.1.1
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Jamie Bykov-Brett
;@Ahk2Exe-SetCompanyName Bykov-Brett Enterprises
;@Ahk2Exe-SetMainIcon ..\assets\icon.ico

DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

global APP_NAME := "Popper"
global APP_VERSION := "0.1.1"
global PUBLISHER := "Jamie Bykov-Brett"
global UNINSTALL_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Popper"
global RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global ACCENT := "2563EB"

global InstallPath := DefaultInstallPath()
global MainGui := ""
global Steps := Map(1, [], 2, [], 3, [], 4, [])
global CurrentStep := 1
global InstallDone := false
global ExePath := ""
global Opts := {startup: true, startMenu: true, desktop: false, launch: true}

; Popper's updater runs "Popper-Setup.exe /upgrade": no wizard, keep the
; existing choices, then open Popper again.
global Upgrading := false
for arg in A_Args
    if RegExMatch(arg, "i)^[/-]{1,2}upgrade$")
        Upgrading := true

if Upgrading
    RunUpgrade()
else
    BuildGui()

RunUpgrade() {
    global MainGui, Opts
    Opts := {
        startup: RegValueExists(RUN_KEY, "Popper"),
        startMenu: FileExist(A_Programs "\Popper.lnk") != "",
        desktop: FileExist(A_Desktop "\Popper.lnk") != "",
        launch: true
    }
    MainGui := Gui("-MaximizeBox -MinimizeBox", "Updating " APP_NAME)
    MainGui.SetFont("s10 c1F2328", "Segoe UI")
    MainGui.BackColor := "FFFFFF"
    MainGui.SetFont("Bold s12")
    MainGui.Add("Text", "x20 y18 w360", "Updating Popper to " APP_VERSION)
    MainGui.SetFont("Norm s10")
    MainGui.Add("Text", "x20 y50 w360 h40 vStatus", "Starting...")
    MainGui.Add("Progress", "x20 y95 w360 h18 vBar c" ACCENT, 0)
    MainGui.Add("Button", "x300 y125 w80 h28 Hidden vCancelBtn", "Close").OnEvent("Click", (*) => ExitApp())
    MainGui.OnEvent("Close", (*) => MainGui["CancelBtn"].Enabled ? ExitApp() : true)
    MainGui.Show("w400 h165")
    Install()
    if InstallDone {
        Sleep(800)
        CancelOrFinish()
    } else {
        MainGui["CancelBtn"].Visible := true
    }
}

RegValueExists(key, name) {
    try {
        RegRead(key, name)
        return true
    }
    return false
}

DefaultInstallPath() {
    ; Reuse the folder of an earlier install, so an upgrade lands in place.
    try {
        p := RegRead(UNINSTALL_KEY, "InstallLocation")
        if p != ""
            return p
    }
    return EnvGet("LOCALAPPDATA") "\Programs\Popper"
}

BuildGui() {
    global MainGui
    MainGui := Gui("-MaximizeBox -MinimizeBox", APP_NAME " Setup")
    MainGui.SetFont("s10", "Segoe UI")
    MainGui.BackColor := "FFFFFF"

    ; Sidebar, as in the other AI Literacy Lab installers
    MainGui.Add("Text", "x0 y0 w180 h400 Background" ACCENT)
    MainGui.SetFont("Bold s14 cFFFFFF")
    MainGui.Add("Text", "x15 y20 w150 BackgroundTrans", APP_NAME)
    MainGui.SetFont("Bold s9 cFFFFFF")
    MainGui.Add("Text", "x15 y45 w150 BackgroundTrans", "Bykov-Brett Enterprises")
    MainGui.SetFont("Norm s9 cFFFFFF")
    MainGui.Add("Text", "x15 y62 w150 BackgroundTrans", "Setup, version " APP_VERSION)
    MainGui.SetFont("s10 cFFFFFF")
    for i, label in ["1. Welcome", "2. Location", "3. Options", "4. Install"]
        MainGui.Add("Text", "x15 y" (70 + i * 30) " w150 BackgroundTrans vSide" i, label)
    MainGui.SetFont("Norm s10 c1F2328", "Segoe UI")

    BuildWelcome(), BuildLocation(), BuildOptions(), BuildInstall()

    MainGui.Add("Button", "x200 y355 w80 h30 vBackBtn", "< &Back").OnEvent("Click", (*) => Go(-1))
    MainGui.Add("Button", "x290 y355 w80 h30 vNextBtn Default", "&Next >").OnEvent("Click", (*) => Go(1))
    MainGui.Add("Button", "x450 y355 w80 h30 vCancelBtn", "Cancel").OnEvent("Click", (*) => CancelOrFinish())
    MainGui.OnEvent("Close", (*) => CancelOrFinish())
    MainGui.OnEvent("Escape", (*) => CancelOrFinish())

    ShowStep(1)
    MainGui.Show("w550 h400")
    ; Focus the tick box, or the licence box takes focus with all its text selected.
    MainGui["Accept"].Focus()
}

Add(step, type, opts, text := "") {
    ctrl := MainGui.Add(type, opts, text)
    Steps[step].Push(ctrl)
    return ctrl
}

Title(step, text) {
    MainGui.SetFont("Bold s14")
    Add(step, "Text", "x200 y25 w330", text)
    MainGui.SetFont("Norm s10")
}

BuildWelcome() {
    Title(1, "Welcome to " APP_NAME)
    Add(1, "Text", "x200 y60 w330", "Popper records your calls in the background and turns them into transcripts, as a backup for when nobody turned on the meeting recording.")
    notice := "
    (
LICENCE
Popper is licensed under Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International. You may share it unchanged, with credit, for non-commercial use. The full text is in the LICENSE file on GitHub.

PROVIDED AS IS
Popper comes with no warranty of any kind. Transcripts can contain errors. Check anything important against the recording.

RECORDING OTHER PEOPLE
Popper records your microphone and everything your speakers play, which includes everyone else on a call. The law on recording calls differs between countries and states, and your employer may have its own rules. Tell the people on the call that you are recording, and get their consent where the law or your organisation requires it. You are responsible for how you use Popper.

WHERE YOUR AUDIO GOES
Recordings stay on this computer until Popper sends them to the transcription service you choose. That service's own privacy terms then apply. API keys are encrypted with your Windows account and never leave this computer, except in requests to that service.
    )"
    Add(1, "Edit", "x200 y120 w330 h185 ReadOnly Multi -WantReturn", notice)
    cb := Add(1, "Checkbox", "x200 y315 w330 vAccept", "I accept the licence and the recording notice")
    cb.OnEvent("Click", (*) => MainGui["NextBtn"].Enabled := cb.Value)
}

BuildLocation() {
    Title(2, "Choose a folder")
    Add(2, "Text", "x200 y65 w330", "Popper installs for your Windows account only, so it does not need administrator rights.")
    Add(2, "Edit", "x200 y115 w250 r1 vPathEdit", InstallPath)
    Add(2, "Button", "x460 y114 w70 h26", "Bro&wse...").OnEvent("Click", Browse)
    Add(2, "Text", "x200 y160 w330 c666666", "Your settings stay in %AppData%\Popper and your recordings in the folder you choose in Popper. Setup changes neither.")
}

BuildOptions() {
    Title(3, "Options")
    Add(3, "Checkbox", "x200 y70 w330 vStartup Checked", "Start Popper when I sign in to Windows")
    Add(3, "Text", "x218 y92 w312 c666666", "Popper can only catch a call while it is running, so leave this on.")
    Add(3, "Checkbox", "x200 y135 w330 vStartMenu Checked", "Add Popper to the Start menu")
    Add(3, "Checkbox", "x200 y160 w330 vDesktop", "Add a desktop shortcut")
    Add(3, "Checkbox", "x200 y185 w330 vLaunch Checked", "Open Popper when setup finishes")
    Add(3, "Text", "x200 y230 w330 c666666", "You can change the startup option later in Popper's settings, on the General tab.")
}

BuildInstall() {
    Title(4, "Installing")
    Add(4, "Text", "x200 y65 w330 h60 vStatus", "Ready to install.")
    Add(4, "Progress", "x200 y135 w330 h20 vBar c" ACCENT, 0)
}

ShowStep(n) {
    global CurrentStep := n
    for step, ctrls in Steps
        for ctrl in ctrls
            ctrl.Visible := (step = n)
    loop 4
        MainGui["Side" A_Index].SetFont(A_Index = n ? "Bold" : "Norm")
    MainGui["BackBtn"].Enabled := n > 1 && n < 4
    MainGui["NextBtn"].Text := n = 3 ? "&Install" : "&Next >"
    MainGui["NextBtn"].Enabled := n = 1 ? MainGui["Accept"].Value : n < 4
}

Go(delta) {
    n := CurrentStep + delta
    if delta > 0 && CurrentStep = 2 {
        p := Trim(MainGui["PathEdit"].Value)
        if p = "" || !RegExMatch(p, "^[A-Za-z]:\\") {
            Warn("Choose a full folder path, such as " DefaultInstallPath() ".")
            return
        }
        global InstallPath := RTrim(p, "\")
    }
    ShowStep(n)
    if n = 4 {
        global Opts := {
            startup: MainGui["Startup"].Value = 1,
            startMenu: MainGui["StartMenu"].Value = 1,
            desktop: MainGui["Desktop"].Value = 1,
            launch: MainGui["Launch"].Value = 1
        }
        Install()
    }
}

Browse(*) {
    MainGui.Opt("+OwnDialogs")
    dir := DirSelect("*" MainGui["PathEdit"].Value, 3, "Choose where to install Popper")
    if dir != ""
        MainGui["PathEdit"].Value := RegExReplace(dir, "\\Popper$") "\Popper"
}

Warn(msg) {
    MainGui.Opt("+OwnDialogs")
    MsgBox(msg, APP_NAME " Setup", "Icon!")
}

Status(text, pct) {
    MainGui["Status"].Value := text
    MainGui["Bar"].Value := pct
}

; Popper runs as Popper.exe once installed. Ask it to close so a call being
; recorded is saved properly, then make sure it has gone.
ClosePopper() {
    if !ProcessExist("Popper.exe")
        return true
    MainGui.Opt("+OwnDialogs")
    if !Upgrading && MsgBox("Popper is running. Setup will close it and open it again afterwards.`n`nIf it is recording a call, the recording so far is saved.", APP_NAME " Setup", "OKCancel Icon!") != "OK"
        return false
    DetectHiddenWindows(true)
    for hwnd in WinGetList("ahk_class AutoHotkey ahk_exe Popper.exe")
        try PostMessage(0x0010, 0, 0, , "ahk_id " hwnd)  ; WM_CLOSE runs Popper's exit handler
    if ProcessWaitClose("Popper.exe", 8)
        ProcessClose("Popper.exe")
    Sleep(500)
    return !ProcessExist("Popper.exe")
}

Install() {
    global ExePath, InstallDone
    MainGui["CancelBtn"].Enabled := false
    try {
        Status("Closing Popper if it is running...", 5)
        if !ClosePopper() {
            Status("Setup stopped. Popper is still running.", 0)
            MainGui["CancelBtn"].Enabled := true
            return
        }

        Status("Copying files...", 20)
        DirCreate(InstallPath "\assets")
        ; FileInstall paths are relative to this script when it is compiled.
        FileInstall("..\build\Popper.exe", InstallPath "\Popper.exe", true)
        FileInstall("..\build\Uninstall.exe", InstallPath "\Uninstall.exe", true)
        FileInstall("..\assets\icon.ico", InstallPath "\assets\icon.ico", true)
        FileInstall("..\assets\recording.ico", InstallPath "\assets\recording.ico", true)
        FileInstall("..\LICENSE", InstallPath "\LICENSE.txt", true)
        ExePath := InstallPath "\Popper.exe"
        icon := InstallPath "\assets\icon.ico"

        Status("Adding shortcuts...", 55)
        startMenu := A_Programs "\Popper.lnk"
        desktop := A_Desktop "\Popper.lnk"
        if Opts.startMenu
            FileCreateShortcut(ExePath, startMenu, InstallPath, , "Backup meeting transcription", icon)
        else
            try FileDelete(startMenu)
        if Opts.desktop
            FileCreateShortcut(ExePath, desktop, InstallPath, , "Backup meeting transcription", icon)
        else
            try FileDelete(desktop)

        Status("Registering with Windows...", 75)
        if Opts.startup
            RegWrite('"' ExePath '" /startup', "REG_SZ", RUN_KEY, "Popper")
        else
            try RegDelete(RUN_KEY, "Popper")

        sizeKb := 0
        loop files InstallPath "\*.*", "R"
            sizeKb += A_LoopFileSizeKB
        RegWrite(APP_NAME, "REG_SZ", UNINSTALL_KEY, "DisplayName")
        RegWrite(APP_VERSION, "REG_SZ", UNINSTALL_KEY, "DisplayVersion")
        RegWrite(PUBLISHER, "REG_SZ", UNINSTALL_KEY, "Publisher")
        RegWrite(InstallPath, "REG_SZ", UNINSTALL_KEY, "InstallLocation")
        RegWrite(icon, "REG_SZ", UNINSTALL_KEY, "DisplayIcon")
        RegWrite('"' InstallPath '\Uninstall.exe"', "REG_SZ", UNINSTALL_KEY, "UninstallString")
        RegWrite("https://github.com/AILiteracyLab/Popper", "REG_SZ", UNINSTALL_KEY, "URLInfoAbout")
        RegWrite(sizeKb, "REG_DWORD", UNINSTALL_KEY, "EstimatedSize")
        RegWrite(1, "REG_DWORD", UNINSTALL_KEY, "NoModify")
        RegWrite(1, "REG_DWORD", UNINSTALL_KEY, "NoRepair")

        InstallDone := true
        if Upgrading {
            Status("Popper is up to date. Opening it again...", 100)
            return
        }
        Status("Popper is installed in " InstallPath ".`n`nIt lives in the tray, by the clock, and starts recording when a watched app takes your microphone.", 100)
        MainGui["Status"].Move(, , , 120)
        MainGui["CancelBtn"].Text := "&Finish"
        MainGui["CancelBtn"].Enabled := true
        MainGui["CancelBtn"].Focus()
    } catch as e {
        Status("Setup could not finish.", 0)
        Warn("Setup could not finish:`n`n" e.Message (e.Extra != "" ? "`n" e.Extra : ""))
        MainGui["CancelBtn"].Enabled := true
    }
}

CancelOrFinish() {
    if InstallDone {
        if Opts.launch
            try Run('"' ExePath '"', InstallPath)
        ExitApp()
    }
    if CurrentStep = 4 && !MainGui["CancelBtn"].Enabled
        return true  ; installing: ignore close
    ExitApp()
}

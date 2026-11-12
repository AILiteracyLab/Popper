#Requires AutoHotkey v2.0

/**
 * Tray - system tray icon and menu.
 * The icon turns red while recording. Clicking a "Transcript ready"
 * notification opens that transcript.
 */
class Tray {
    static IdleIcon := ""
    static RecIcon := ""
    static M_Open := "Open Popper"
    static M_Record := "Record now"
    static M_Stop := "Stop recording"
    static M_Pause := "Record calls automatically"
    static M_Folder := "Open transcripts folder"
    static M_Settings := "Settings"
    static M_Exit := "Exit"

    static Init() {
        this.IdleIcon := Util.AssetPath("icon.ico")
        this.RecIcon := Util.AssetPath("recording.ico")
        m := A_TrayMenu
        m.Delete()
        m.Add(this.M_Open, (*) => MainWindow.Show())
        m.Add()
        m.Add(this.M_Record, (*) => App.ToggleManual())
        m.Add(this.M_Pause, (*) => App.SetAutoRecord(!App.AutoRecord))
        m.Add()
        m.Add(this.M_Folder, (*) => Run(Sessions.Root()))
        m.Add(this.M_Settings, (*) => SettingsWindow.Show())
        m.Add()
        m.Add(this.M_Exit, (*) => Tray._Exit())
        m.Default := this.M_Open
        m.ClickCount := 1
        OnMessage(0x404, ObjBindMethod(this, "_OnNotify"))
        this.Update()
    }

    static Update() {
        m := A_TrayMenu
        recording := Recorder.Active
        try m.Rename(recording ? this.M_Record : this.M_Stop, recording ? this.M_Stop : this.M_Record)
        if App.AutoRecord
            m.Check(this.M_Pause)
        else
            m.Uncheck(this.M_Pause)
        icon := recording ? this.RecIcon : this.IdleIcon
        if icon != ""
            TraySetIcon(icon)
        else
            TraySetIcon("shell32.dll", recording ? 110 : 169)
        if recording
            A_IconTip := "Popper - recording " Recorder.AppName
        else if !App.AutoRecord
            A_IconTip := "Popper - automatic recording is off"
        else
            A_IconTip := "Popper - watching for calls"
    }

    static _OnNotify(wParam, lParam, msg, hwnd) {
        if (lParam & 0xFFFF) = 0x405  ; NIN_BALLOONUSERCLICK
            App.OpenLastTranscript()
    }

    static _Exit() {
        if Recorder.Active {
            if MsgBox("Popper is recording. Stop, save the recording, and exit?", APP_NAME, "YesNo Icon?") != "Yes"
                return
        }
        ExitApp()
    }
}

#Requires AutoHotkey v2.0

/**
 * MainWindow - the list of recordings and what Popper is doing now.
 *
 *   Popper                         (dot) Watching Teams, Zoom
 *   Transcribing with Home server (faster-whisper-medium)        Change
 *   [Record now] [Open transcript] [Open folder] [Retry] [Delete]
 *   +------------------------------------------------------------+
 *   | When            | App              | Length   | Status     |
 *   +------------------------------------------------------------+
 *   [x] Record calls automatically                [Settings]
 *
 * Closing the window leaves Popper running in the tray.
 */
class MainWindow {
    static Gui := ""
    static LV := ""
    static StatusText := ""
    static ServiceText := ""
    static ChangeLink := ""
    static HintText := ""
    static RecordBtn := ""
    static OpenBtn := ""
    static FolderBtn := ""
    static RetryBtn := ""
    static DeleteBtn := ""
    static AutoCheck := ""
    static SettingsBtn := ""
    static Rows := []
    static _sig := ""
    static _timer := ""
    static _toldTray := false

    static Show() {
        if this.Gui {
            this.Gui.Show()
            this.Refresh(true)
            return
        }
        DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        g := Gui("+Resize +MinSize640x380", "Popper")
        ThemeManager.Apply(g)
        c := ThemeManager.Colors()

        g.SetFont("Bold s16")
        g.Add("Text", "x20 y14 w140", "Popper")
        g.SetFont("Norm s10")
        this.StatusText := g.Add("Text", "x170 y20 w530 Right", "")

        this.ServiceText := g.Add("Text", "x20 y52 w560 c" c.muted, "")
        this.ChangeLink := g.Add("Link", "x600 y52 w100 Right", '<a id="svc">Change</a>')
        this.ChangeLink.OnEvent("Click", (*) => SettingsWindow.Show("Transcription"))

        this.RecordBtn := g.Add("Button", "x20 y84 w130 h30", "Record now")
        this.RecordBtn.OnEvent("Click", (*) => App.ToggleManual())
        this.OpenBtn := g.Add("Button", "x+8 yp w130 h30", "Open transcript")
        this.OpenBtn.OnEvent("Click", (*) => this._OpenSelected())
        this.FolderBtn := g.Add("Button", "x+8 yp w110 h30", "Open folder")
        this.FolderBtn.OnEvent("Click", (*) => this._OpenFolder())
        this.RetryBtn := g.Add("Button", "x+8 yp w80 h30", "Retry")
        this.RetryBtn.OnEvent("Click", (*) => this._Retry())
        this.DeleteBtn := g.Add("Button", "x+8 yp w80 h30", "Delete")
        this.DeleteBtn.OnEvent("Click", (*) => this._Delete())

        this.LV := g.Add("ListView", "x20 y124 w680 h300 -Multi +LV0x10000", ["When", "App", "Length", "Status"])
        if ThemeManager.IsDark()
            this.LV.Opt("+Background2A2A2A c" c.text)
        this.LV.ModifyCol(1, 160)
        this.LV.ModifyCol(2, 170)
        this.LV.ModifyCol(3, 100)
        this.LV.ModifyCol(4, 240)
        this.LV.OnEvent("DoubleClick", (*) => this._OpenSelected())
        this.LV.OnEvent("ItemSelect", (*) => this._UpdateButtons())

        this.HintText := g.Add("Text", "x20 y432 w680 c" c.muted, "")
        this.AutoCheck := g.Add("Checkbox", "x20 y460 w300", "Record calls automatically")
        this.AutoCheck.OnEvent("Click", (*) => App.SetAutoRecord(this.AutoCheck.Value = 1))
        this.SettingsBtn := g.Add("Button", "x600 y454 w100 h30", "Settings")
        this.SettingsBtn.OnEvent("Click", (*) => SettingsWindow.Show())

        g.OnEvent("Size", ObjBindMethod(this, "_OnSize"))
        g.OnEvent("Close", ObjBindMethod(this, "_OnClose"))
        g.OnEvent("Escape", ObjBindMethod(this, "_OnClose"))
        this.Gui := g
        this.Refresh(true)
        ThemeManager.Finish(g)
        g.Show("w720 h500" Util.ShowExtra)
        this._timer := ObjBindMethod(this, "Refresh")
        SetTimer(this._timer, 1500)
    }

    static Refresh(force := false) {
        if !this.Gui
            return
        if force = 0 && !DllCall("IsWindowVisible", "ptr", this.Gui.Hwnd)
            return
        c := ThemeManager.Colors()

        if Recorder.Active {
            this.StatusText.Opt("c" c.rec)
            this.StatusText.Value := Chr(0x25CF) " Recording " Recorder.AppName ", " Util.Length(Recorder.ElapsedSeconds())
        } else if !App.AutoRecord {
            this.StatusText.Opt("c" c.warn)
            this.StatusText.Value := "Automatic recording is off"
        } else {
            this.StatusText.Opt("c" c.ok)
            this.StatusText.Value := Chr(0x25CF) " Watching for calls in " this._WatchedSummary()
        }

        p := Profiles.Active()
        if IsObject(p) {
            this.ServiceText.Opt("c" c.muted)
            this.ServiceText.Value := "Transcribing with " Profiles.Describe(p) (Transcriber.Busy ? ". Working now." : "")
        } else {
            this.ServiceText.Opt("c" c.warn)
            this.ServiceText.Value := "No transcription service yet. Recordings wait until you add one."
        }

        this.RecordBtn.Text := Recorder.Active ? "Stop recording" : "Record now"
        this.AutoCheck.Value := App.AutoRecord ? 1 : 0

        rows := []
        sig := ""
        for s in Sessions.List() {
            started := s.Get("Started")
            row := [started != "" ? FormatTime(started, "ddd d MMM, HH:mm") : s.Name
                , s.Get("App"), Util.Length(s.DurationSeconds()), s.StatusText()]
            rows.Push({session: s, cells: row})
            sig .= s.Name "|" row[3] "|" row[4] "`n"
        }
        if force || sig != this._sig {
            selected := this._SelectedName()
            this.LV.Opt("-Redraw")
            this.LV.Delete()
            for r in rows {
                i := this.LV.Add(, r.cells*)
                if r.session.Name = selected
                    this.LV.Modify(i, "Select Focus")
            }
            this.LV.Opt("+Redraw")
            this.Rows := rows
            this._sig := sig
        }
        if rows.Length
            this.HintText.Value := "Double-click a recording to open its transcript, or select it and press Open folder for the audio."
        else
            this.HintText.Value := "No recordings yet. Popper starts recording when a call takes your microphone, or press Record now."
        this._UpdateButtons()
    }

    static _WatchedSummary() {
        names := []
        for app in Detector.WatchedApps()
            if app.enabled
                names.Push(app.name)
        if !names.Length
            return "no apps (add some in Settings)"
        out := ""
        for i, n in names {
            if i > 3 {
                out .= " and " (names.Length - 3) " more"
                break
            }
            out .= (i = 1 ? "" : ", ") n
        }
        return out
    }

    static _Selected() {
        row := this.LV.GetNext()
        return row && row <= this.Rows.Length ? this.Rows[row].session : ""
    }

    static _SelectedName() {
        s := this._Selected()
        return s ? s.Name : ""
    }

    static _UpdateButtons() {
        s := this._Selected()
        recordingThis := s && Recorder.Active && Recorder.Session && Recorder.Session.dir = s.dir
        st := s ? s.Get("Status") : ""
        this.OpenBtn.Enabled := (s && s.HasTranscript()) ? true : false
        this.FolderBtn.Enabled := s ? true : false
        this.RetryBtn.Enabled := (s && (st = "failed" || st = "partial")) ? true : false
        this.DeleteBtn.Enabled := (s && !recordingThis) ? true : false
    }

    static _OpenSelected() {
        s := this._Selected()
        if !s
            return
        if s.HasTranscript()
            Run(s.TranscriptPath())
        else
            Run(s.dir)
    }

    static _OpenFolder() {
        s := this._Selected()
        Run(s ? s.dir : Sessions.Root())
    }

    static _Retry() {
        s := this._Selected()
        if !s
            return
        if !DirExist(s.dir "\audio") {
            MsgBox("The audio for this recording has been deleted, so it cannot be transcribed again.", APP_NAME, "Icon!")
            return
        }
        s.ResetFailed()
        Transcriber.Resume()
        this.Refresh(true)
    }

    static _Delete() {
        s := this._Selected()
        if !s
            return
        if MsgBox("Delete the " s.Get("App") " recording from " this.LV.GetText(this.LV.GetNext(), 1) "?`n`nThe audio and transcript are deleted. This cannot be undone.", APP_NAME, "YesNo Icon! Default2") != "Yes"
            return
        try {
            DirDelete(s.dir, true)
        } catch as e {
            MsgBox("Could not delete the folder: " e.Message, APP_NAME, "Iconx")
        }
        this.Refresh(true)
    }

    static _OnSize(g, minMax, w, h) {
        if minMax = -1
            return
        this.StatusText.Move(170, , w - 190)
        this.ServiceText.Move(, , w - 180)
        this.ChangeLink.Move(w - 120)
        this.LV.Move(, , w - 40, h - 200)
        this.LV.ModifyCol(4, "AutoHdr")
        this.HintText.Move(, h - 68, w - 40)
        this.AutoCheck.Move(, h - 40)
        this.SettingsBtn.Move(w - 120, h - 46)
    }

    static _OnClose(*) {
        this.Gui.Hide()
        if !this._toldTray {
            this._toldTray := true
            TrayTip("Popper is still running in the tray and will record your next call.", APP_NAME, "Mute")
        }
        return true
    }
}

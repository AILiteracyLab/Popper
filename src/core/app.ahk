#Requires AutoHotkey v2.0

/**
 * App - ties detection, recording and transcription together.
 *
 * Every two seconds Tick() asks Windows which app holds the microphone.
 * A watched app seen on two ticks in a row starts a recording. When no
 * watched app has held the mic for StopAfterSeconds, the recording stops
 * and its last chunks go to the transcription queue.
 *
 * If the user stops or discards a recording, that app is left alone until
 * its call ends, so Popper does not start again ten seconds later.
 */
class App {
    static Suppressed := ""
    static SeenApp := ""
    static SeenCount := 0
    static IdleSince := 0
    static LastTranscript := ""
    static _hotkey := ""
    static RunKey := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

    static Start() {
        AppLog.Info("Popper " APP_VERSION " starting")
        ThemeManager.Load()
        Tray.Init()
        Transcriber.OnSessionDone := ObjBindMethod(this, "_OnSessionDone")
        Sessions.Recover()
        Sessions.Cleanup()
        this.ApplyHotkey()
        OnExit(ObjBindMethod(this, "_OnExit"))

        startupLaunch := false
        for arg in A_Args
            if RegExMatch(arg, "i)^[/-]{1,2}startup$")
                startupLaunch := true

        if AppConfig.GetBool("General", "FirstLaunch") {
            AppConfig.Set("General", "FirstLaunch", "0")
            SetTimer(ObjBindMethod(this, "ShowWelcome"), -300)
        } else if !(startupLaunch && AppConfig.GetBool("General", "StartMinimized")) {
            SetTimer(() => MainWindow.Show(), -200)
        }

        SetTimer(ObjBindMethod(this, "Tick"), 2000)
        SetTimer(() => Sessions.Cleanup(), 6 * 3600 * 1000)
        Transcriber.Kick()
        Updater.ScheduleAutoCheck()
    }

    static Tick() {
        try Recorder.CheckDevices()
        active := ""
        try active := Detector.ActiveApp()

        if !Recorder.Active {
            if active = "" {
                this.Suppressed := ""
                this.SeenCount := 0
                return
            }
            if active = this.Suppressed || !this.AutoRecord
                return
            if active = this.SeenApp {
                this.SeenCount++
            } else {
                this.SeenApp := active
                this.SeenCount := 1
            }
            if this.SeenCount >= 2
                this.StartRecording(active, true)
            return
        }

        if Recorder.Auto {
            if active = "" {
                if !this.IdleSince
                    this.IdleSince := A_TickCount
                else if A_TickCount - this.IdleSince >= AppConfig.GetInt("Detection", "StopAfterSeconds", 5, 600) * 1000
                    this.StopRecording(false, false)
            } else {
                this.IdleSince := 0
            }
        }
    }

    static StartRecording(appName, auto) {
        try {
            if !Recorder.Start(appName, auto)
                return
        } catch as e {
            AppLog.Error("Could not start recording: " e.Message)
            TrayTip("Popper could not start recording. " e.Message, APP_NAME, "Iconx")
            this.Suppressed := appName
            return
        }
        this.IdleSince := 0
        this.SeenCount := 0
        if AppConfig.GetBool("Detection", "ShowPill")
            Pill.Show(appName)
        else
            TrayTip("Recording " appName ". Popper will transcribe it when the call ends.", APP_NAME, "Mute")
        Tray.Update()
        MainWindow.Refresh()
    }

    ; byUser: the user pressed Stop or Discard, so leave this call alone.
    static StopRecording(discard, byUser := true) {
        if !Recorder.Active
            return
        appName := Recorder.AppName
        if byUser {
            ; Leave whichever watched app is on a call alone until it ends,
            ; even if this recording was started by hand.
            onCall := ""
            try onCall := Detector.ActiveApp()
            this.Suppressed := onCall != "" ? onCall : appName
        }
        s := ""
        try s := Recorder.Stop(discard)
        catch as e
            AppLog.Error("Stop failed: " e.Message)
        this.IdleSince := 0
        Pill.Hide()
        Tray.Update()
        MainWindow.Refresh()
        if !discard && s
            TrayTip("Saved the " appName " recording. The transcript appears in Popper when it is ready.", APP_NAME, "Mute")
    }

    static ToggleManual() {
        if Recorder.Active {
            this.StopRecording(false, true)
            return
        }
        active := ""
        try active := Detector.ActiveApp()
        this.StartRecording(active != "" ? active : "Recording", false)
    }

    static AutoRecord => AppConfig.GetBool("Detection", "AutoRecord")

    static SetAutoRecord(on) {
        AppConfig.Set("Detection", "AutoRecord", on ? "1" : "0")
        Tray.Update()
        MainWindow.Refresh()
    }

    static ShowWelcome() {
        MsgBox("
        (
Popper records calls on this computer and turns them into transcripts.

It starts by itself when Teams, Zoom or another app you choose takes your microphone, and it stops when the call ends.

Before you use it:
- Tell the people on the call that you are recording. The law may require it where you or they are, and your organisation may have its own rules.
- Audio goes only to the transcription service you set up, and transcripts stay on this computer.

Next, add a transcription service.
        )", "Welcome to Popper", "Iconi")
        MainWindow.Show()
        SettingsWindow.Show("Transcription")
    }

    static OpenLastTranscript() {
        if this.LastTranscript != "" && FileExist(this.LastTranscript)
            Run(this.LastTranscript)
        else
            MainWindow.Show()
    }

    static ApplyHotkey() {
        if this._hotkey != "" {
            try Hotkey(this._hotkey, "Off")
            this._hotkey := ""
        }
        key := AppConfig.Get("General", "Hotkey")
        if key != "" {
            try {
                Hotkey(key, (*) => App.ToggleManual(), "On")
                this._hotkey := key
            } catch as e {
                AppLog.Warn("Could not register hotkey " key ": " e.Message)
            }
        }
    }

    static IsStartupEnabled() {
        try {
            RegRead(this.RunKey, "Popper")
            return true
        }
        return false
    }

    static SetStartup(enabled) {
        if enabled {
            if A_IsCompiled
                cmd := '"' A_ScriptFullPath '" /startup'
            else
                cmd := '"' A_AhkPath '" "' A_ScriptFullPath '" /startup'
            RegWrite(cmd, "REG_SZ", this.RunKey, "Popper")
        } else {
            try RegDelete(this.RunKey, "Popper")
        }
    }

    static _OnSessionDone(s) {
        this.LastTranscript := s.TranscriptPath()
        st := s.Get("Status")
        if st = "failed"
            msg := "Transcription failed for " s.Get("App") ". Open Popper to retry."
        else if st = "partial"
            msg := "Transcript ready, with gaps: " s.Get("App") " call. Click to open."
        else
            msg := "Transcript ready: " s.Get("App") " call. Click to open."
        TrayTip(msg, APP_NAME, st = "failed" ? "Icon!" : "Iconi")
        MainWindow.Refresh()
    }

    static _OnExit(reason, code) {
        if Recorder.Active {
            try Recorder.Stop(false)
        }
        AppLog.Info("Popper exiting (" reason ")")
        return 0
    }
}

#Requires AutoHotkey v2.0

/**
 * SettingsWindow - tabbed settings in the style of the other AI Literacy Lab
 * tools. Tabs: General, Detection, Transcription, Audio, Output, About,
 * Disclaimer. Service profiles and watched apps are edited in their own small
 * dialogs; everything else is written when you press Save.
 */
class SettingsWindow {
    static Gui := ""
    static Tabs := ""
    static C := Map()
    static AppList := []
    static MicValues := []
    static SpkValues := []
    static TabNames := ["General", "Detection", "Transcription", "Audio", "Output", "About", "Disclaimer"]

    static Show(tabName := "") {
        if this.Gui {
            WinActivate(this.Gui)
            if tabName != ""
                this.Tabs.Choose(tabName)
            return
        }
        DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        ThemeManager.Load()
        g := Gui("-MaximizeBox", "Popper Settings")
        ThemeManager.Apply(g)
        this.Gui := g
        this.C := Map()
        this.Tabs := g.Add("Tab3", "x10 y10 w620 h450", this.TabNames)

        this.Tabs.UseTab("General"), this._General()
        this.Tabs.UseTab("Detection"), this._Detection()
        this.Tabs.UseTab("Transcription"), this._Transcription()
        this.Tabs.UseTab("Audio"), this._Audio()
        this.Tabs.UseTab("Output"), this._Output()
        this.Tabs.UseTab("About"), this._About()
        this.Tabs.UseTab("Disclaimer"), this._Disclaimer()
        this.Tabs.UseTab()

        save := g.Add("Button", "x400 y470 w110 h30 Default", "&Save")
        save.OnEvent("Click", (*) => this._Save())
        close := g.Add("Button", "x520 y470 w110 h30", "C&lose")
        close.OnEvent("Click", (*) => this.Close())
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())
        if tabName != ""
            this.Tabs.Choose(tabName)
        ThemeManager.Finish(g)
        g.Show("w640 h512" Util.ShowExtra)
    }

    static Close() {
        if this.Gui {
            this.Gui.Destroy()
            this.Gui := ""
        }
    }

    ; ---------------------------------------------------------------- General
    static _General() {
        g := this.Gui, x := 30, y := 50
        ThemeManager.Heading(g, "x" x " y" y, "Startup")
        y += 28
        this.C["Startup"] := g.Add("Checkbox", "x" x " y" y " w560", "Start Popper when I sign in to Windows")
        this.C["Startup"].Value := App.IsStartupEnabled()
        y += 26
        this.C["StartMinimized"] := g.Add("Checkbox", "x" x " y" y " w560", "When it starts with Windows, stay in the tray")
        this.C["StartMinimized"].Value := AppConfig.GetBool("General", "StartMinimized")
        y += 40

        ThemeManager.Heading(g, "x" x " y" y, "Names in transcripts")
        y += 28
        g.Add("Text", "x" x " y" y " w150", "Your name:")
        this.C["MyName"] := g.Add("Edit", "x" (x + 160) " y" (y - 3) " w220", AppConfig.Get("General", "MyName"))
        y += 30
        g.Add("Text", "x" x " y" y " w150", "Everyone else:")
        this.C["OthersName"] := g.Add("Edit", "x" (x + 160) " y" (y - 3) " w220", AppConfig.Get("General", "OthersName"))
        y += 30
        ThemeManager.Muted(g, "x" x " y" y " w560 h40", "Popper hears you through your microphone and everyone else through your speakers, so a transcript has two speakers.")
        y += 52

        ThemeManager.Heading(g, "x" x " y" y, "Appearance and shortcut")
        y += 28
        g.Add("Text", "x" x " y" y " w150", "Theme:")
        this.C["Theme"] := g.Add("DropDownList", "x" (x + 160) " y" (y - 3) " w120", ["Light", "Dark"])
        this.C["Theme"].Choose(ThemeManager.IsDark() ? 2 : 1)
        y += 32
        g.Add("Text", "x" x " y" y " w150", "Start or stop recording:")
        this.C["Hotkey"] := g.Add("Hotkey", "x" (x + 160) " y" (y - 3) " w220", AppConfig.Get("General", "Hotkey"))
        ThemeManager.Muted(g, "x" (x + 390) " y" y " w180", "Optional")
    }

    ; -------------------------------------------------------------- Detection
    static _Detection() {
        g := this.Gui, x := 30, y := 50
        this.C["AutoRecord"] := g.Add("Checkbox", "x" x " y" y " w560", "Start recording when one of these apps takes my microphone")
        this.C["AutoRecord"].Value := App.AutoRecord
        y += 28
        lv := g.Add("ListView", "x" x " y" y " w580 h170 Checked -Multi", ["App", "Matches"])
        if ThemeManager.IsDark()
            lv.Opt("+Background2A2A2A c" ThemeManager.Colors().text)
        this.C["Apps"] := lv
        this.AppList := Detector.WatchedApps()
        this._FillApps()
        lv.ModifyCol(1, 200)
        lv.ModifyCol(2, 330)
        lv.OnEvent("DoubleClick", (*) => this._EditApp())
        y += 178
        b := g.Add("Button", "x" x " y" y " w90 h28", "Add...")
        b.OnEvent("Click", (*) => this._AddApp())
        b := g.Add("Button", "x+8 yp w90 h28", "Edit...")
        b.OnEvent("Click", (*) => this._EditApp())
        b := g.Add("Button", "x+8 yp w90 h28", "Remove")
        b.OnEvent("Click", (*) => this._RemoveApp())
        b := g.Add("Button", "x+8 yp w210 h28", "Add an app that used the mic...")
        b.OnEvent("Click", (*) => this._PickRecent())
        y += 40
        g.Add("Text", "x" x " y" y " w330", "Stop recording when the call has ended for")
        this.C["StopAfter"] := g.Add("Edit", "x" (x + 335) " y" (y - 3) " w60 Number", AppConfig.GetInt("Detection", "StopAfterSeconds", 5, 600))
        g.Add("UpDown", "Range5-600 0x80", AppConfig.GetInt("Detection", "StopAfterSeconds", 5, 600))
        g.Add("Text", "x" (x + 402) " y" y " w100", "seconds")
        y += 32
        this.C["ShowPill"] := g.Add("Checkbox", "x" x " y" y " w560", "Show the recording bar with Stop and Discard buttons")
        this.C["ShowPill"].Value := AppConfig.GetBool("Detection", "ShowPill")
        y += 30
        ThemeManager.Muted(g, "x" x " y" y " w580 h60", "Popper reads the list Windows keeps of apps using the microphone, the same one behind the mic icon in the taskbar. A match is part of the app's name in that list. Browsers are off by default because they use the mic for more than calls.")
    }

    static _FillApps() {
        lv := this.C["Apps"]
        lv.Delete()
        for app in this.AppList {
            m := ""
            for x in app.matches
                m .= (m = "" ? "" : ", ") x
            lv.Add(app.enabled ? "Check" : "", app.name, m)
        }
    }

    ; Pick up check-box changes before editing the list.
    static _SyncChecks() {
        lv := this.C["Apps"]
        for app in this.AppList
            app.enabled := false
        row := 0
        while row := lv.GetNext(row, "C")
            if row <= this.AppList.Length
                this.AppList[row].enabled := true
    }

    static _AddApp(prefill := "") {
        this._SyncChecks()
        app := prefill ? prefill : {name: "", enabled: true, matches: []}
        AppEditor.Show(this.Gui, app, (edited) => (this.AppList.Push(edited), this._FillApps()))
    }

    static _EditApp() {
        row := this.C["Apps"].GetNext()
        if !row
            return
        this._SyncChecks()
        AppEditor.Show(this.Gui, this.AppList[row], (edited) => (this.AppList[row] := edited, this._FillApps()))
    }

    static _RemoveApp() {
        row := this.C["Apps"].GetNext()
        if !row
            return
        this._SyncChecks()
        this.AppList.RemoveAt(row)
        this._FillApps()
    }

    static _PickRecent() {
        entries := Detector.Entries()
        ; newest first
        Loop entries.Length - 1 {
            i := A_Index + 1
            while i > 1 && entries[i - 1].lastStart < entries[i].lastStart {
                t := entries[i], entries[i] := entries[i - 1], entries[i - 1] := t
                i--
            }
        }
        m := Menu()
        count := 0
        for e in entries {
            if count >= 15
                break
            label := e.label (e.inUse ? "  (using the mic now)" : "")
            key := e.key
            m.Add(label, ((k, *) => this._AddFromKey(k)).Bind(key))
            count++
        }
        if !count {
            MsgBox("Windows has no record of apps using the microphone yet. Join a test call in the app, then try again.", APP_NAME, "Iconi")
            return
        }
        m.Show()
    }

    static _AddFromKey(key) {
        label := Detector.Label(key)
        name := RegExReplace(label, "i)\.exe$", "")
        name := StrUpper(SubStr(name, 1, 1)) SubStr(name, 2)
        this._AddApp({name: name, enabled: true, matches: [Detector.SuggestMatch(key)]})
    }

    ; ---------------------------------------------------------- Transcription
    static _Transcription() {
        g := this.Gui, x := 30, y := 50
        ThemeManager.Heading(g, "x" x " y" y, "Transcription service")
        y += 28
        this.C["Profile"] := g.Add("DropDownList", "x" x " y" y " w260")
        this.C["Profile"].OnEvent("Change", (*) => this._ShowProfileInfo())
        b := g.Add("Button", "x" (x + 270) " y" (y - 1) " w70 h28", "Add...")
        b.OnEvent("Click", (*) => ProfileEditor.Show(this.Gui, "", (n) => this._FillProfiles(n)))
        b := g.Add("Button", "x+6 yp w70 h28", "Edit...")
        b.OnEvent("Click", (*) => this._EditProfile())
        b := g.Add("Button", "x+6 yp w70 h28", "Delete")
        b.OnEvent("Click", (*) => this._DeleteProfile())
        b := g.Add("Button", "x+6 yp w70 h28", "Test")
        b.OnEvent("Click", (*) => this._TestProfile())
        y += 36
        this.C["ProfileInfo"] := ThemeManager.Muted(g, "x" x " y" y " w580 h40", "")
        this._FillProfiles(Profiles.ActiveName())
        y += 50
        ThemeManager.Muted(g, "x" x " y" y " w580 h40", "Use any service that speaks the OpenAI transcription API: OpenAI, Groq, or your own server such as Speaches or faster-whisper-server. Add as many as you like.")
        y += 54

        ThemeManager.Heading(g, "x" x " y" y, "Accuracy")
        y += 28
        g.Add("Text", "x" x " y" y " w150", "Language:")
        this.C["Language"] := g.Add("Edit", "x" (x + 160) " y" (y - 3) " w80", AppConfig.Get("Transcription", "Language"))
        ThemeManager.Muted(g, "x" (x + 250) " y" y " w330", "A two-letter code such as en, or auto")
        y += 32
        g.Add("Text", "x" x " y" y " w580", "Names and terms to spell correctly, separated by commas:")
        y += 22
        this.C["Vocabulary"] := g.Add("Edit", "x" x " y" y " w580 h60 Multi", AppConfig.Get("Transcription", "Vocabulary"))
        y += 70
        this.C["Live"] := g.Add("Checkbox", "x" x " y" y " w580", "Transcribe during the call, so the transcript is ready sooner")
        this.C["Live"].Value := AppConfig.GetBool("Transcription", "LiveTranscribe")
    }

    static _FillProfiles(select := "") {
        dd := this.C["Profile"]
        dd.Delete()
        names := Profiles.Names()
        if names.Length {
            dd.Add(names)
            idx := 1
            for i, n in names
                if n = select
                    idx := i
            dd.Choose(idx)
        }
        this._ShowProfileInfo()
    }

    static _ShowProfileInfo() {
        name := this.C["Profile"].Text
        if name = "" {
            this.C["ProfileInfo"].Value := "No service yet. Press Add to set one up."
            return
        }
        p := Profiles.Get(name)
        this.C["ProfileInfo"].Value := "Server: " Profiles.Endpoint(p) "`nModel: " (p.model = "" ? "(server default)" : p.model) "    API key: " (p.key = "" ? "none" : "saved")
    }

    static _EditProfile() {
        name := this.C["Profile"].Text
        if name != ""
            ProfileEditor.Show(this.Gui, name, (n) => this._FillProfiles(n))
    }

    static _DeleteProfile() {
        name := this.C["Profile"].Text
        if name = ""
            return
        if MsgBox("Delete the service '" name "' and its saved API key?", APP_NAME, "YesNo Icon? Default2 Owner" this.Gui.Hwnd) != "Yes"
            return
        Profiles.Delete(name)
        this._FillProfiles(Profiles.ActiveName())
    }

    static _TestProfile() {
        name := this.C["Profile"].Text
        if name = ""
            return
        this.Gui.Opt("+Disabled")
        r := Profiles.Test(Profiles.Get(name))
        this.Gui.Opt("-Disabled")
        MsgBox(r.message, "Test " name, (r.ok ? "Iconi" : "Icon!") " Owner" this.Gui.Hwnd)
    }

    ; ------------------------------------------------------------------ Audio
    static _Audio() {
        g := this.Gui, x := 30, y := 50
        ThemeManager.Heading(g, "x" x " y" y, "Your microphone")
        y += 28
        this.C["RecordMic"] := g.Add("Checkbox", "x" x " y" y " w560", "Record my microphone")
        this.C["RecordMic"].Value := AppConfig.GetBool("Audio", "RecordMic")
        y += 28
        names := [], this.MicValues := []
        this._DeviceOptions(AudioDevices.FLOW_CAPTURE, names, this.MicValues)
        this.C["Mic"] := g.Add("DropDownList", "x" x " y" y " w560", names)
        this._ChooseValue(this.C["Mic"], this.MicValues, AppConfig.Get("Audio", "MicDevice"))
        y += 44

        ThemeManager.Heading(g, "x" x " y" y, "Call audio")
        y += 28
        names := [], this.SpkValues := []
        this._DeviceOptions(AudioDevices.FLOW_RENDER, names, this.SpkValues)
        this.C["Speaker"] := g.Add("DropDownList", "x" x " y" y " w560", names)
        this._ChooseValue(this.C["Speaker"], this.SpkValues, AppConfig.Get("Audio", "SpeakerDevice"))
        y += 32
        ThemeManager.Muted(g, "x" x " y" y " w580 h40", "Popper records what plays through this device. If your calls play through a headset that is not your Windows default, pick the headset, or choose the default for calls.")
        y += 54

        ThemeManager.Heading(g, "x" x " y" y, "Uploads")
        y += 28
        g.Add("Text", "x" x " y" y " w200", "Send audio in pieces of")
        this.C["Chunk"] := g.Add("Edit", "x" (x + 205) " y" (y - 3) " w50 Number", AppConfig.GetInt("Audio", "ChunkMinutes", 1, 10))
        g.Add("UpDown", "Range1-10 0x80", AppConfig.GetInt("Audio", "ChunkMinutes", 1, 10))
        g.Add("Text", "x" (x + 262) " y" y " w100", "minutes")
        y += 30
        ThemeManager.Muted(g, "x" x " y" y " w580 h40", "Shorter pieces make the transcript ready sooner after a call. Ten minutes is the most OpenAI accepts in one upload.")
    }

    static _DeviceOptions(flow, names, values) {
        names.Push("Windows default"), values.Push("default")
        names.Push("Windows default for calls"), values.Push("comms")
        for d in AudioDevices.List(flow) {
            names.Push(d.name != "" ? d.name : d.id)
            values.Push(d.id)
        }
    }

    static _ChooseValue(dd, values, value) {
        for i, v in values
            if v = value {
                dd.Choose(i)
                return
            }
        dd.Choose(1)
    }

    ; ----------------------------------------------------------------- Output
    static _Output() {
        g := this.Gui, x := 30, y := 50
        ThemeManager.Heading(g, "x" x " y" y, "Where recordings go")
        y += 28
        this.C["Folder"] := g.Add("Edit", "x" x " y" y " w400 r1 -Wrap", Sessions.Root())
        b := g.Add("Button", "x" (x + 408) " y" (y - 1) " w80 h26", "Browse...")
        b.OnEvent("Click", (*) => this._Browse())
        b := g.Add("Button", "x+6 yp w80 h26", "Open")
        b.OnEvent("Click", (*) => Run(this.C["Folder"].Value))
        y += 34
        ThemeManager.Muted(g, "x" x " y" y " w580 h40", "Each call gets its own folder with the transcript and the audio. Avoid a folder that syncs to the cloud if your recordings should stay on this computer.")
        y += 54

        ThemeManager.Heading(g, "x" x " y" y, "Keeping audio")
        y += 28
        g.Add("Text", "x" x " y" y " w200", "Delete audio after")
        this.C["KeepDays"] := g.Add("Edit", "x" (x + 205) " y" (y - 3) " w60 Number", AppConfig.GetInt("Output", "KeepAudioDays", 0, 3650))
        g.Add("UpDown", "Range0-3650 0x80", AppConfig.GetInt("Output", "KeepAudioDays", 0, 3650))
        g.Add("Text", "x" (x + 272) " y" y " w300", "days (0 keeps it)")
        y += 30
        ThemeManager.Muted(g, "x" x " y" y " w580", "Transcripts are never deleted. Only finished recordings lose their audio.")
        y += 40

        ThemeManager.Heading(g, "x" x " y" y, "Files")
        y += 28
        ThemeManager.Muted(g, "x" x " y" y " w580", "Every call gets transcript.md. Also save:")
        y += 26
        this.C["Vtt"] := g.Add("Checkbox", "x" x " y" y " w560", "Captions (transcript.vtt), for video players and Teams")
        this.C["Vtt"].Value := AppConfig.GetBool("Output", "WriteVtt")
        y += 26
        this.C["Txt"] := g.Add("Checkbox", "x" x " y" y " w560", "Plain text (transcript.txt)")
        this.C["Txt"].Value := AppConfig.GetBool("Output", "WriteTxt")
    }

    static _Browse() {
        folder := DirSelect("*" this.C["Folder"].Value, 3, "Choose where Popper saves recordings")
        if folder != ""
            this.C["Folder"].Value := folder
    }

    ; ------------------------------------------------------------------ About
    static _About() {
        g := this.Gui, x := 30, y := 50
        g.SetFont("Bold s14")
        g.Add("Text", "x" x " y" y " w560", "Popper " APP_VERSION)
        g.SetFont("Norm s10")
        y += 34
        g.Add("Text", "x" x " y" y " w560 h40", "A backup transcriber for calls. When someone forgets to record the meeting, you still have the transcript.")
        y += 50
        g.Add("Text", "x" x " y" y " w560", "(c) 2026 Jamie Bykov-Brett")
        y += 24
        g.Add("Link", "x" x " y" y " w560", '<a href="' APP_REPO '">GitHub repository</a>')
        y += 24
        ThemeManager.Muted(g, "x" x " y" y " w560", "Licensed under CC BY-NC-ND 4.0")
        y += 40
        ThemeManager.Heading(g, "x" x " y" y, "Files Popper keeps")
        y += 28
        g.Add("Text", "x" x " y" y " w560", "Settings and log:")
        y += 22
        g.Add("Link", "x" x " y" y " w560", '<a href="' AppConfig.AppDataDir '">' AppConfig.AppDataDir '</a>')
        y += 30
        g.Add("Text", "x" x " y" y " w560", "Recordings and transcripts:")
        y += 22
        g.Add("Link", "x" x " y" y " w560", '<a href="' Sessions.Root() '">' Sessions.Root() '</a>')
        y += 40
        ThemeManager.Heading(g, "x" x " y" y, "Updates")
        y += 30
        this.C["AutoUpdate"] := g.Add("Checkbox", "x" x " y" y " w400", "Check GitHub for a new version once a week")
        this.C["AutoUpdate"].Value := AppConfig.GetBool("Updates", "AutoCheck")
        g.Add("Button", "x450 y" (y - 5) " w160 h28", "Check &now").OnEvent("Click", (*) => (this.Gui.Opt("+OwnDialogs"), Updater.Check(true)))
    }

    static _Disclaimer() {
        text := "
        (
Popper is provided as is, without warranty of any kind.

RECORDING OTHER PEOPLE
Popper records your microphone and the audio your computer plays, which includes everyone on a call. Many places require you to tell people, or get their consent, before you record them. Your employer or client may have rules of their own. You are responsible for following them. A simple habit: say at the start of the call that you are taking a recording for your notes.

WHERE THE AUDIO GOES
Audio is saved in the recordings folder on this computer. It is sent only to the transcription service you set up, and that service's own terms apply to it. If you use your own server, the audio does not leave the machines you control.

WHAT POPPER DOES NOT DO
Popper does not send analytics, does not upload anything to its authors, and does not join calls as a bot. It reads the Windows list of apps using the microphone to know when a call starts. Once a week it asks GitHub for the latest version number, which you can turn off on the About tab.

ACCURACY
Transcripts are produced by a machine and contain mistakes, especially with names, numbers and overlapping speech. Check anything important against the audio.

API KEYS
Keys are encrypted with Windows DPAPI, so only your Windows account on this computer can read them.

The authors are not liable for any damages arising from the use of this software.
        )"
        this.Gui.Add("Edit", "x30 y50 w580 h390 ReadOnly Multi -WantReturn", text)
    }

    ; ------------------------------------------------------------------- Save
    static _Save() {
        c := this.C
        App.SetStartup(c["Startup"].Value = 1)
        AppConfig.Set("General", "StartMinimized", c["StartMinimized"].Value ? "1" : "0")
        AppConfig.Set("General", "MyName", Trim(c["MyName"].Value) = "" ? "Me" : Trim(c["MyName"].Value))
        AppConfig.Set("General", "OthersName", Trim(c["OthersName"].Value) = "" ? "Others" : Trim(c["OthersName"].Value))
        newTheme := c["Theme"].Value = 2 ? "dark" : "light"
        themeChanged := newTheme != ThemeManager.Current
        AppConfig.Set("General", "Theme", newTheme)
        AppConfig.Set("General", "Hotkey", c["Hotkey"].Value)

        AppConfig.Set("Detection", "AutoRecord", c["AutoRecord"].Value ? "1" : "0")
        this._SyncChecks()
        Detector.SaveWatchedApps(this.AppList)
        AppConfig.Set("Detection", "StopAfterSeconds", c["StopAfter"].Value)
        AppConfig.Set("Detection", "ShowPill", c["ShowPill"].Value ? "1" : "0")

        if c["Profile"].Text != ""
            Profiles.SetActive(c["Profile"].Text)
        lang := Trim(c["Language"].Value)
        AppConfig.Set("Transcription", "Language", lang)
        AppConfig.Set("Transcription", "Vocabulary", RegExReplace(Trim(c["Vocabulary"].Value), "\R+", ", "))
        AppConfig.Set("Transcription", "LiveTranscribe", c["Live"].Value ? "1" : "0")

        AppConfig.Set("Audio", "RecordMic", c["RecordMic"].Value ? "1" : "0")
        AppConfig.Set("Audio", "MicDevice", this.MicValues[c["Mic"].Value])
        AppConfig.Set("Audio", "SpeakerDevice", this.SpkValues[c["Speaker"].Value])
        AppConfig.Set("Audio", "ChunkMinutes", c["Chunk"].Value)

        folder := Trim(c["Folder"].Value)
        if folder != "" {
            try {
                if !DirExist(folder)
                    DirCreate(folder)
                AppConfig.Set("Output", "Folder", folder)
            } catch {
                MsgBox("Popper cannot create that folder. The recordings folder has not changed.", APP_NAME, "Icon! Owner" this.Gui.Hwnd)
            }
        }
        AppConfig.Set("Output", "KeepAudioDays", c["KeepDays"].Value)
        AppConfig.Set("Output", "WriteVtt", c["Vtt"].Value ? "1" : "0")
        AppConfig.Set("Output", "WriteTxt", c["Txt"].Value ? "1" : "0")
        AppConfig.Set("Updates", "AutoCheck", c["AutoUpdate"].Value ? "1" : "0")

        ThemeManager.Load()
        App.ApplyHotkey()
        Transcriber.Resume()
        Tray.Update()
        MainWindow.Refresh(true)
        note := Recorder.Active ? "`n`nDevice changes apply from the next recording." : ""
        if themeChanged
            note .= "`n`nThe new theme applies when you reopen Popper's windows."
        MsgBox("Settings saved." note, APP_NAME, "Iconi Owner" this.Gui.Hwnd)
    }
}

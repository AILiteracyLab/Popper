#Requires AutoHotkey v2.0

/**
 * Pill - a small always-on-top bar shown while recording.
 *
 *   (red dot) Recording Microsoft Teams   12:34   [Stop] [Discard] [-]
 *
 * Stop saves and transcribes. Discard deletes the audio. The dash hides the
 * pill; recording carries on and the tray icon stays red. Drag the pill by
 * its text to move it. It never takes focus from the call window.
 */
class Pill {
    static Gui := ""
    static TimeText := ""
    static _timer := ""
    static _dragHooked := false

    static Show(appName) {
        if this.Gui
            this.Hide()
        DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +Border +E0x08000000")  ; WS_EX_NOACTIVATE
        g.BackColor := "1A1A1A"
        g.MarginX := 10, g.MarginY := 6
        g.SetFont("s12 cFF3B30", "Segoe UI")
        g.Add("Text", "x10 y7 w18", Chr(0x25CF))
        g.SetFont("s10 cFFFFFF", "Segoe UI")
        label := "Recording " (StrLen(appName) > 22 ? SubStr(appName, 1, 21) "..." : appName)
        g.Add("Text", "x30 y9 w190", label)
        g.SetFont("s10 cAAAAAA", "Segoe UI")
        this.TimeText := g.Add("Text", "x222 y9 w52 Right", "0:00")
        g.SetFont("s9 c000000", "Segoe UI")
        b1 := g.Add("Button", "x284 y5 w54 h26", "Stop")
        b1.OnEvent("Click", (*) => App.StopRecording(false, true))
        b2 := g.Add("Button", "x342 y5 w64 h26", "Discard")
        b2.OnEvent("Click", (*) => Pill._Discard())
        b3 := g.Add("Button", "x410 y5 w26 h26", "-")
        b3.OnEvent("Click", (*) => Pill.Hide())
        this.Gui := g

        MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
        w := 446, h := 36
        x := AppConfig.Get("Pill", "X", ""), y := AppConfig.Get("Pill", "Y", "")
        if !IsInteger(x) || !IsInteger(y) || x < left || y < top || x > right - 50 || y > bottom - 20 {
            x := right - w - 16
            y := bottom - h - 16
        }
        g.Show("x" x " y" y " w" w " h" h " NoActivate" Util.ShowExtra)
        WinSetTransparent(235, g)
        if !this._dragHooked {
            OnMessage(0x201, ObjBindMethod(this, "_OnDrag"))
            this._dragHooked := true
        }
        this._timer := ObjBindMethod(this, "_Tick")
        SetTimer(this._timer, 1000)
    }

    static Hide() {
        if this._timer
            SetTimer(this._timer, 0)
        if this.Gui {
            try {
                WinGetPos(&x, &y, , , this.Gui)
                AppConfig.Set("Pill", "X", x)
                AppConfig.Set("Pill", "Y", y)
            }
            this.Gui.Destroy()
            this.Gui := ""
        }
    }

    static IsShown() => this.Gui != ""

    static _Tick() {
        if !this.Gui
            return
        s := Recorder.ElapsedSeconds()
        if s >= 3600
            this.TimeText.Value := Format("{}:{:02}:{:02}", s // 3600, Mod(s // 60, 60), Mod(s, 60))
        else
            this.TimeText.Value := Format("{}:{:02}", s // 60, Mod(s, 60))
    }

    static _Discard() {
        if Recorder.ElapsedSeconds() > 60 {
            if MsgBox("Discard this recording? The audio is deleted and nothing is transcribed.", APP_NAME, "YesNo Icon! 0x40000") != "Yes"
                return
        }
        App.StopRecording(true, true)
    }

    static _OnDrag(wParam, lParam, msg, hwnd) {
        if !this.Gui
            return
        ; Drag from the background or a text label, never from a button.
        onPill := hwnd = this.Gui.Hwnd
        if !onPill && DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") = this.Gui.Hwnd
            onPill := WinGetClass("ahk_id " hwnd) = "Static"
        if onPill
            PostMessage(0xA1, 2, , , "ahk_id " this.Gui.Hwnd)  ; WM_NCLBUTTONDOWN, HTCAPTION
    }
}

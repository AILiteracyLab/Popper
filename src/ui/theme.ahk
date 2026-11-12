#Requires AutoHotkey v2.0

/**
 * ThemeManager - light and dark colours, matching the other AI Literacy Lab
 * Windows tools. Set in Settings > General.
 */
class ThemeManager {
    static Current := "light"

    static Themes := Map(
        "light", {bg: "FFFFFF", text: "1F2328", muted: "666666", accent: "0066CC", rec: "D93025", ok: "1A7F37", warn: "9A6700"},
        "dark", {bg: "1E1E1E", text: "F0F0F0", muted: "AAAAAA", accent: "4FC3F7", rec: "FF5A4E", ok: "57D068", warn: "E3B341"}
    )

    static Load() {
        t := StrLower(AppConfig.Get("General", "Theme"))
        this.Current := this.Themes.Has(t) ? t : "light"
    }

    static Colors() => this.Themes[this.Current]
    static IsDark() => this.Current = "dark"

    static Apply(gui) {
        c := this.Colors()
        gui.BackColor := c.bg
        gui.SetFont("s10 c" c.text, "Segoe UI")
        ; Dark title bar on Windows 10 1809+ and 11
        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", gui.Hwnd, "int", 20, "int*", this.IsDark() ? 1 : 0, "int", 4)
    }

    ; Call after adding controls. In dark mode, edit boxes keep a white
    ; background unless told otherwise, which hides the light text.
    static Finish(gui) {
        if !this.IsDark()
            return
        for hwnd, ctrl in gui {
            if ctrl.Type = "Edit"
                ctrl.Opt("+Background2B2B2B")
        }
    }

    ; Section heading in the family style: bold, slightly larger.
    static Heading(gui, opts, text) {
        gui.SetFont("Bold s11")
        ctrl := gui.Add("Text", opts, text)
        gui.SetFont("Norm s10")
        return ctrl
    }

    static Muted(gui, opts, text) {
        ctrl := gui.Add("Text", opts " c" this.Colors().muted, text)
        return ctrl
    }
}

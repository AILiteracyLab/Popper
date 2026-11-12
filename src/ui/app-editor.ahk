#Requires AutoHotkey v2.0

/**
 * AppEditor - add or edit one watched app.
 */
class AppEditor {
    static Gui := ""
    static Owner := ""
    static OnSaved := ""
    static App := ""
    static C := Map()

    static Show(owner, app, onSaved) {
        if this.Gui {
            WinActivate(this.Gui)
            return
        }
        this.Owner := owner
        this.OnSaved := onSaved
        this.App := app
        g := Gui("+Owner" owner.Hwnd " -MinimizeBox", app.name = "" ? "Add an app" : "Edit " app.name)
        ThemeManager.Apply(g)
        this.Gui := g
        this.C := Map()
        m := ""
        for x in app.matches
            m .= (m = "" ? "" : ", ") x

        g.Add("Text", "x20 y20 w100", "Name:")
        this.C["Name"] := g.Add("Edit", "x125 y17 w330", app.name)
        g.Add("Text", "x20 y54 w100", "Matches:")
        this.C["Matches"] := g.Add("Edit", "x125 y51 w330", m)
        ThemeManager.Muted(g, "x125 y80 w330 h54", "Separate matches with commas. Popper records when any of them is part of the app's entry in the Windows microphone list, such as #zoom.exe or msteams_.")
        this.C["Enabled"] := g.Add("Checkbox", "x125 y138 w330", "Record calls in this app")
        this.C["Enabled"].Value := app.enabled ? 1 : 0
        save := g.Add("Button", "x259 y172 w96 h30 Default", "Save")
        save.OnEvent("Click", (*) => this._Save())
        cancel := g.Add("Button", "x359 y172 w96 h30", "Cancel")
        cancel.OnEvent("Click", (*) => this.Close())
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())
        owner.Opt("+Disabled")
        ThemeManager.Finish(g)
        g.Show("w475 h216" Util.ShowExtra)
    }

    static Close() {
        if this.Owner
            try this.Owner.Opt("-Disabled")
        if this.Gui {
            this.Gui.Destroy()
            this.Gui := ""
        }
        if this.Owner
            try WinActivate(this.Owner)
    }

    static _Save() {
        name := Trim(this.C["Name"].Value)
        if name = "" || RegExMatch(name, "[=\[\]]") {
            MsgBox("Give the app a name without = [ or ].", APP_NAME, "Icon! Owner" this.Gui.Hwnd)
            return
        }
        matches := []
        for x in StrSplit(this.C["Matches"].Value, ",")
            if Trim(x) != ""
                matches.Push(StrLower(Trim(x)))
        if !matches.Length {
            MsgBox("Add at least one match.", APP_NAME, "Icon! Owner" this.Gui.Hwnd)
            return
        }
        edited := {name: name, enabled: this.C["Enabled"].Value = 1, matches: matches}
        cb := this.OnSaved
        this.Close()
        cb(edited)
    }
}

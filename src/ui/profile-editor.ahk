#Requires AutoHotkey v2.0

/**
 * ProfileEditor - add or edit one transcription service.
 *
 * Picking a type fills in the usual address and model for it. Every field
 * stays editable, so any OpenAI-compatible server can be added.
 */
class ProfileEditor {
    static Gui := ""
    static Owner := ""
    static OnSaved := ""
    static OldName := ""
    static C := Map()

    static Show(owner, name, onSaved) {
        if this.Gui {
            WinActivate(this.Gui)
            return
        }
        this.Owner := owner
        this.OnSaved := onSaved
        this.OldName := name
        p := name != "" ? Profiles.Get(name) : {name: "", preset: Profiles.Presets[1].name, url: Profiles.Presets[1].url, model: Profiles.Presets[1].model, extra: Profiles.Presets[1].extra, key: ""}

        g := Gui("+Owner" owner.Hwnd " -MinimizeBox", name = "" ? "Add a transcription service" : "Edit " name)
        ThemeManager.Apply(g)
        this.Gui := g
        this.C := Map()
        x := 20, y := 20, lw := 110, fx := 135, fw := 380

        g.Add("Text", "x" x " y" y " w" lw, "Name:")
        this.C["Name"] := g.Add("Edit", "x" fx " y" (y - 3) " w" fw, p.name)
        y += 34
        g.Add("Text", "x" x " y" y " w" lw, "Type:")
        this.C["Preset"] := g.Add("DropDownList", "x" fx " y" (y - 3) " w" fw, Profiles.PresetNames())
        idx := Profiles.Presets.Length
        for i, pr in Profiles.Presets
            if pr.name = p.preset
                idx := i
        this.C["Preset"].Choose(idx)
        this.C["Preset"].OnEvent("Change", (*) => this._ApplyPreset())
        y += 34
        g.Add("Text", "x" x " y" y " w" lw, "Server URL:")
        this.C["Url"] := g.Add("Edit", "x" fx " y" (y - 3) " w" fw, p.url)
        y += 26
        ThemeManager.Muted(g, "x" fx " y" y " w" fw, "Popper adds /v1/audio/transcriptions to this address.")
        y += 30
        g.Add("Text", "x" x " y" y " w" lw, "API key:")
        this.C["Key"] := g.Add("Edit", "x" fx " y" (y - 3) " w" (fw - 80) " Password", name != "" ? CredentialManager.GetMasked("profile:" name) : "")
        show := g.Add("Button", "x" (fx + fw - 72) " y" (y - 4) " w72 h26", "Show")
        show.OnEvent("Click", (*) => this._ToggleKey(show))
        y += 26
        ThemeManager.Muted(g, "x" fx " y" y " w" fw, "Leave it empty if your server has no key.")
        y += 30
        g.Add("Text", "x" x " y" y " w" lw, "Model:")
        this.C["Model"] := g.Add("ComboBox", "x" fx " y" (y - 3) " w" (fw - 110), [p.model])
        this.C["Model"].Text := p.model
        lm := g.Add("Button", "x" (fx + fw - 102) " y" (y - 4) " w102 h26", "List models")
        lm.OnEvent("Click", (*) => this._ListModels())
        y += 36
        g.Add("Text", "x" x " y" y " w" lw, "Extra fields:")
        this.C["Extra"] := g.Add("Edit", "x" fx " y" (y - 3) " w" fw " h56 Multi", StrReplace(p.extra, ";", "`r`n"))
        y += 58
        ThemeManager.Muted(g, "x" fx " y" y " w" fw " h36", "One per line, sent with every upload. For example vad_filter=true on Speaches.")
        y += 44

        test := g.Add("Button", "x" x " y" y " w90 h30", "Test")
        test.OnEvent("Click", (*) => this._Test())
        save := g.Add("Button", "x" (fx + fw - 200) " y" y " w96 h30 Default", "Save")
        save.OnEvent("Click", (*) => this._Save())
        cancel := g.Add("Button", "x" (fx + fw - 96) " y" y " w96 h30", "Cancel")
        cancel.OnEvent("Click", (*) => this.Close())
        g.OnEvent("Close", (*) => this.Close())
        g.OnEvent("Escape", (*) => this.Close())
        owner.Opt("+Disabled")
        ThemeManager.Finish(g)
        g.Show("w" (fx + fw + 20) " h" (y + 46) Util.ShowExtra)
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

    static _ApplyPreset() {
        pr := Profiles.Presets[this.C["Preset"].Value]
        if pr.name = "Custom"
            return
        this.C["Url"].Value := pr.url
        this.C["Model"].Text := pr.model
        this.C["Extra"].Value := StrReplace(pr.extra, ";", "`r`n")
        if Trim(this.C["Name"].Value) = ""
            this.C["Name"].Value := StrSplit(pr.name, " (")[1]
    }

    static _ToggleKey(btn) {
        if btn.Text = "Show" {
            if CredentialManager.IsMasked(this.C["Key"].Value) && this.OldName != ""
                this.C["Key"].Value := CredentialManager.Retrieve("profile:" this.OldName)
            this.C["Key"].Opt("-Password")
            btn.Text := "Hide"
        } else {
            this.C["Key"].Opt("+Password")
            btn.Text := "Show"
        }
    }

    ; The profile as currently typed, with the real key resolved.
    static _Current() {
        p := {name: Trim(this.C["Name"].Value)}
        p.preset := this.C["Preset"].Text
        p.url := Trim(this.C["Url"].Value)
        p.model := Trim(this.C["Model"].Text)
        extra := ""
        for line in StrSplit(this.C["Extra"].Value, "`n", "`r")
            if InStr(line, "=")
                extra .= (extra = "" ? "" : ";") Trim(line)
        p.extra := extra
        k := this.C["Key"].Value
        if CredentialManager.IsMasked(k) && this.OldName != ""
            k := CredentialManager.Retrieve("profile:" this.OldName)
        p.key := Trim(k)
        return p
    }

    static _Validate(p) {
        if p.name = ""
            return "Give the service a name."
        if RegExMatch(p.name, "[|\[\]=;]")
            return "The name cannot contain | [ ] = or a semicolon."
        if !RegExMatch(p.url, "i)^https?://[^/\s]+")
            return "The server URL must start with http:// or https://"
        if p.name != this.OldName {
            for n in Profiles.Names()
                if n = p.name
                    return "There is already a service called " p.name "."
        }
        return ""
    }

    static _Test() {
        p := this._Current()
        err := this._Validate(p)
        if err != "" && !InStr(err, "already") {
            MsgBox(err, APP_NAME, "Icon! Owner" this.Gui.Hwnd)
            return
        }
        this.Gui.Opt("+Disabled")
        r := Profiles.Test(p)
        this.Gui.Opt("-Disabled")
        MsgBox(r.message, "Test", (r.ok ? "Iconi" : "Icon!") " Owner" this.Gui.Hwnd)
    }

    static _ListModels() {
        p := this._Current()
        if !RegExMatch(p.url, "i)^https?://") {
            MsgBox("Enter the server URL first.", APP_NAME, "Icon! Owner" this.Gui.Hwnd)
            return
        }
        this.Gui.Opt("+Disabled")
        r := Profiles.ListModels(p)
        this.Gui.Opt("-Disabled")
        if !r.ok {
            MsgBox(r.message, APP_NAME, "Icon! Owner" this.Gui.Hwnd)
            return
        }
        current := this.C["Model"].Text
        this.C["Model"].Delete()
        this.C["Model"].Add(r.models)
        this.C["Model"].Text := current != "" ? current : r.models[1]
        MsgBox("Found " r.models.Length " model" (r.models.Length = 1 ? "" : "s") ". Pick one from the Model list.", APP_NAME, "Iconi Owner" this.Gui.Hwnd)
    }

    static _Save() {
        p := this._Current()
        err := this._Validate(p)
        if err != "" {
            MsgBox(err, APP_NAME, "Icon! Owner" this.Gui.Hwnd)
            return
        }
        typed := this.C["Key"].Value
        if CredentialManager.IsMasked(typed)
            key := ""
        else if Trim(typed) = ""
            key := "-"
        else
            key := Trim(typed)
        Profiles.Save(p, this.OldName, key)
        cb := this.OnSaved
        name := p.name
        this.Close()
        if cb
            cb(name)
    }
}

#Requires AutoHotkey v2.0

/**
 * Updater - checks the GitHub releases of APP_REPO for a newer version.
 *
 * A release is a tag such as 0.2.0 or v0.2.0 with Popper-Setup.exe attached.
 * Installing downloads that file to %TEMP% and runs it with /upgrade, which
 * closes Popper, replaces the files in place and opens Popper again.
 *
 * The automatic check runs at most once a week, a minute after start, and
 * sends nothing but a plain request for the latest release.
 */
class Updater {
    static Latest := ""      ; newer version found, or ""
    static SetupUrl := ""
    static PageUrl := ""
    static M_Install := ""   ; tray menu item, once an update is found

    static Repo() => RegExReplace(APP_REPO, "i)^https?://github\.com/")

    static ScheduleAutoCheck() {
        if !AppConfig.GetBool("Updates", "AutoCheck")
            return
        last := AppConfig.Get("Updates", "LastCheck")
        if last != "" && RegExMatch(last, "^\d{14}$") && DateDiff(A_Now, last, "Days") < 7
            return
        SetTimer(() => this.Check(false), -60000)
    }

    ; Returns {ok, newer, version, error}. manual=true reports every outcome.
    static Check(manual) {
        r := this._Fetch()
        AppConfig.Set("Updates", "LastCheck", A_Now)
        if !r.ok {
            AppLog.Warn("Update check failed: " r.error)
            if manual
                MsgBox("Popper could not check for updates.`n`n" r.error, APP_NAME, "Icon!")
            return r
        }
        if !r.newer {
            if manual
                MsgBox("You have the latest version of Popper (" APP_VERSION ").", APP_NAME, "Iconi")
            return r
        }
        AppLog.Info("Update available: " r.version)
        this._AddTrayItem()
        if manual
            this.Offer()
        else
            TrayTip("Popper " r.version " is available. Choose `"" this.M_Install "`" in the tray menu.", APP_NAME, "Iconi")
        return r
    }

    static Offer() {
        if MsgBox("Popper " this.Latest " is available. You have " APP_VERSION ".`n`nInstall it now? Popper closes and opens again.", APP_NAME, "YesNo Iconi") = "Yes"
            this.Install()
    }

    static Install() {
        if Recorder.Active {
            MsgBox("Popper is recording a call. Install the update after the call ends.", APP_NAME, "Icon!")
            return
        }
        if !A_IsCompiled || this.SetupUrl = "" {
            ; Running from source, or the release has no installer attached.
            Run(this.PageUrl != "" ? this.PageUrl : APP_REPO "/releases")
            return
        }
        path := A_Temp "\Popper-Setup-" this.Latest ".exe"
        try FileDelete(path)
        cmd := Util.Quote(Util.CurlPath()) ' -sSL --fail --max-time 300 -A "Popper/' APP_VERSION '" -o ' Util.Quote(path) ' ' Util.Quote(this.SetupUrl)
        TrayTip("Downloading Popper " this.Latest "...", APP_NAME)
        r := Util.RunCapture(cmd)
        if r.exit != 0 || !this._LooksLikeExe(path) {
            AppLog.Warn("Update download failed: " Trim(r.out))
            if MsgBox("The download did not work. Open the releases page to download it yourself?", APP_NAME, "YesNo Icon!") = "Yes"
                Run(this.PageUrl)
            return
        }
        AppLog.Info("Running " path " /upgrade")
        Run(Util.Quote(path) " /upgrade")
        ExitApp()
    }

    static _Fetch() {
        url := "https://api.github.com/repos/" this.Repo() "/releases/latest"
        ; The status code format goes in a file: cmd would mangle the % inline.
        fmt := A_Temp "\popper-update-fmt.txt"
        Util.WriteText(fmt, "\n%{http_code}")
        cmd := Util.Quote(Util.CurlPath()) ' -sS --max-time 15 -A "Popper/' APP_VERSION '" -H "Accept: application/vnd.github+json" -w "@' fmt '" ' Util.Quote(url)
        r := Util.RunCapture(cmd)
        try FileDelete(fmt)
        if r.exit != 0
            return {ok: false, error: "No connection to GitHub (" Trim(r.out) ")."}
        out := RTrim(r.out, "`r`n")
        pos := InStr(out, "`n", , -1)
        code := pos ? Trim(SubStr(out, pos + 1)) : ""
        body := pos ? SubStr(out, 1, pos - 1) : out
        if code = "404"
            return {ok: false, error: "No releases have been published yet."}
        if code != "200"
            return {ok: false, error: "GitHub answered with HTTP " code "."}
        try data := JSON.Load(body)
        catch
            return {ok: false, error: "GitHub sent a reply Popper could not read."}

        version := RegExReplace(data.Has("tag_name") ? data["tag_name"] : "", "i)^v")
        this.PageUrl := data.Has("html_url") ? data["html_url"] : APP_REPO "/releases"
        this.SetupUrl := ""
        if data.Has("assets")
            for asset in data["assets"]
                if InStr(asset["name"], "Setup") && SubStr(asset["name"], -4) = ".exe"
                    this.SetupUrl := asset["browser_download_url"]
        newer := version != "" && this.Compare(version, APP_VERSION) > 0
        this.Latest := newer ? version : ""
        return {ok: true, newer: newer, version: version, error: ""}
    }

    ; 1 if a is newer than b, -1 if older, 0 if the same. "0.10.0" > "0.9.1".
    static Compare(a, b) {
        pa := StrSplit(RegExReplace(a, "[^\d.].*$"), "."), pb := StrSplit(RegExReplace(b, "[^\d.].*$"), ".")
        loop Max(pa.Length, pb.Length) {
            x := A_Index <= pa.Length && pa[A_Index] != "" ? Integer(pa[A_Index]) : 0
            y := A_Index <= pb.Length && pb[A_Index] != "" ? Integer(pb[A_Index]) : 0
            if x != y
                return x > y ? 1 : -1
        }
        return 0
    }

    static _LooksLikeExe(path) {
        if !FileExist(path) || FileGetSize(path) < 500000
            return false
        f := FileOpen(path, "r")
        sig := f.Read(2)
        f.Close()
        return sig = "MZ"
    }

    static _AddTrayItem() {
        name := "Install Popper " this.Latest
        if this.M_Install = name
            return
        if this.M_Install != ""
            try A_TrayMenu.Delete(this.M_Install)
        this.M_Install := name
        A_TrayMenu.Insert(Tray.M_Settings, name, (*) => Updater.Offer())
    }
}

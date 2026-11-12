#Requires AutoHotkey v2.0

/**
 * ConfigManager - INI settings in %AppData%\Popper\settings.ini
 *
 * Defaults live in code, so a missing key always has a sensible value and the
 * app runs with no settings file at all. The watched-apps list is seeded on
 * first run because it is a list the user edits, not a single value.
 */
class ConfigManager {
    FilePath := ""
    AppDataDir := ""

    static Defaults := Map(
        "General.FirstLaunch", "1",
        "General.StartMinimized", "1",
        "General.Theme", "light",
        "General.MyName", "Me",
        "General.OthersName", "Others",
        "General.Hotkey", "",
        "Detection.AutoRecord", "1",
        "Detection.StopAfterSeconds", "20",
        "Detection.ShowPill", "1",
        "Transcription.Language", "en",
        "Transcription.Vocabulary", "",
        "Transcription.LiveTranscribe", "1",
        "Audio.MicDevice", "default",
        "Audio.SpeakerDevice", "default",
        "Audio.RecordMic", "1",
        "Audio.ChunkMinutes", "5",
        "Audio.SilencePeak", "300",
        "Output.KeepAudioDays", "30",
        "Output.WriteVtt", "1",
        "Output.WriteTxt", "0",
        "Updates.AutoCheck", "1"
    )

    ; Name=enabled|match1,match2. A match is any part of the name Windows
    ; gives the app in its microphone privacy list.
    static DefaultApps := [
        ["Microsoft Teams", "1|msteams_,#ms-teams.exe,#teams.exe"],
        ["Zoom", "1|#zoom.exe"],
        ["Webex", "1|ciscocollabhost.exe,webex"],
        ["Slack", "1|#slack.exe,slack"],
        ["Google Meet in Chrome", "0|#chrome.exe"],
        ["Microsoft Edge", "0|#msedge.exe"],
        ["Firefox", "0|#firefox.exe"]
    ]

    __New(dir := "") {
        this.AppDataDir := dir != "" ? dir : A_AppData "\Popper"
        this.FilePath := this.AppDataDir "\settings.ini"
        if !DirExist(this.AppDataDir)
            DirCreate(this.AppDataDir)
        if !FileExist(this.FilePath) {
            for pair in ConfigManager.DefaultApps
                IniWrite(pair[2], this.FilePath, "Apps", pair[1])
        }
    }

    Get(section, key, defaultValue?) {
        if !IsSet(defaultValue) {
            k := section "." key
            defaultValue := ConfigManager.Defaults.Has(k) ? ConfigManager.Defaults[k] : ""
        }
        return IniRead(this.FilePath, section, key, defaultValue)
    }

    GetBool(section, key) => this.Get(section, key) = "1"

    GetInt(section, key, minValue := "", maxValue := "") {
        v := this.Get(section, key)
        v := IsInteger(v) ? Integer(v) : Integer(ConfigManager.Defaults[section "." key])
        if minValue != "" && v < minValue
            v := minValue
        if maxValue != "" && v > maxValue
            v := maxValue
        return v
    }

    Set(section, key, value) {
        IniWrite(value, this.FilePath, section, key)
    }

    Delete(section, key) {
        try IniDelete(this.FilePath, section, key)
    }

    DeleteSection(section) {
        try IniDelete(this.FilePath, section)
    }

    /**
     * Read a section as an ordered array of [key, value] pairs.
     * Order matters for the apps list, so this does not return a Map.
     */
    GetPairs(section) {
        pairs := []
        try content := IniRead(this.FilePath, section)
        catch
            return pairs
        for line in StrSplit(content, "`n", "`r") {
            eq := InStr(line, "=")
            if eq
                pairs.Push([Trim(SubStr(line, 1, eq - 1)), Trim(SubStr(line, eq + 1))])
        }
        return pairs
    }
}

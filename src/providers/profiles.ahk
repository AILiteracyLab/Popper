#Requires AutoHotkey v2.0

/**
 * Profiles - named transcription services the user can add, edit and switch.
 *
 * Any server that speaks the OpenAI audio transcription API works:
 * POST {url}/v1/audio/transcriptions with response_format=verbose_json.
 *
 * Stored in settings.ini:
 *   [Profiles]        Names=Home server|OpenAI   Active=Home server
 *   [Profile Home server]  Url=..., Model=..., Extra=vad_filter=true;temperature=0
 * The API key sits in [Credentials] under "profile:<name>", DPAPI-encrypted.
 */
class Profiles {
    static Presets := [
        {name: "Self-hosted (Speaches, faster-whisper-server)", url: "http://localhost:8000", model: "Systran/faster-whisper-small", extra: "vad_filter=true", needsKey: false},
        {name: "OpenAI", url: "https://api.openai.com", model: "whisper-1", extra: "", needsKey: true},
        {name: "Groq", url: "https://api.groq.com/openai", model: "whisper-large-v3-turbo", extra: "", needsKey: true},
        {name: "Custom", url: "", model: "", extra: "", needsKey: false}
    ]

    static PresetNames() {
        names := []
        for p in this.Presets
            names.Push(p.name)
        return names
    }

    static Names() {
        raw := AppConfig.Get("Profiles", "Names", "")
        names := []
        for n in StrSplit(raw, "|")
            if Trim(n) != ""
                names.Push(Trim(n))
        return names
    }

    static ActiveName() {
        names := this.Names()
        active := AppConfig.Get("Profiles", "Active", "")
        for n in names
            if n = active
                return n
        return names.Length ? names[1] : ""
    }

    static SetActive(name) => AppConfig.Set("Profiles", "Active", name)

    static Active() {
        name := this.ActiveName()
        return name = "" ? "" : this.Get(name)
    }

    static Get(name) {
        sec := "Profile " name
        p := {name: name}
        p.preset := AppConfig.Get(sec, "Preset", "Custom")
        p.url := AppConfig.Get(sec, "Url", "")
        p.model := AppConfig.Get(sec, "Model", "")
        p.extra := AppConfig.Get(sec, "Extra", "")
        p.key := CredentialManager.Retrieve("profile:" name)
        return p
    }

    /**
     * Save a profile. oldName is the name it had before editing, for renames.
     * key: the new key, or "" to keep what is stored, or "-" to clear it.
     */
    static Save(p, oldName := "", key := "") {
        names := this.Names()
        if oldName != "" && oldName != p.name {
            existingKey := CredentialManager.Retrieve("profile:" oldName)
            this.Delete(oldName, false)
            names := this.Names()
            if key = "" && existingKey != ""
                key := existingKey
        }
        found := false
        for n in names
            if n = p.name
                found := true
        if !found
            names.Push(p.name)
        this._SaveNames(names)
        sec := "Profile " p.name
        AppConfig.Set(sec, "Preset", p.preset)
        AppConfig.Set(sec, "Url", p.url)
        AppConfig.Set(sec, "Model", p.model)
        AppConfig.Set(sec, "Extra", p.extra)
        if key = "-"
            CredentialManager.Delete("profile:" p.name)
        else if key != ""
            CredentialManager.Store("profile:" p.name, key)
        if this.Names().Length = 1 || AppConfig.Get("Profiles", "Active", "") = oldName
            this.SetActive(p.name)
    }

    static Delete(name, clearActive := true) {
        names := []
        for n in this.Names()
            if n != name
                names.Push(n)
        this._SaveNames(names)
        AppConfig.DeleteSection("Profile " name)
        CredentialManager.Delete("profile:" name)
        if clearActive && AppConfig.Get("Profiles", "Active", "") = name
            this.SetActive(names.Length ? names[1] : "")
    }

    static _SaveNames(names) {
        s := ""
        for n in names
            s .= (s = "" ? "" : "|") n
        AppConfig.Set("Profiles", "Names", s)
    }

    static Endpoint(p) {
        url := RTrim(p.url, "/")
        if RegExMatch(url, "i)/audio/transcriptions$")
            return url
        if RegExMatch(url, "i)/v1$")
            return url "/audio/transcriptions"
        return url "/v1/audio/transcriptions"
    }

    static ModelsUrl(p) {
        return RegExReplace(this.Endpoint(p), "i)/audio/transcriptions$", "/models")
    }

    ; "a=b;c=d" -> [["a","b"], ["c","d"]]
    static ExtraFields(p) {
        fields := []
        for item in StrSplit(p.extra, ";") {
            eq := InStr(item, "=")
            if eq
                fields.Push([Trim(SubStr(item, 1, eq - 1)), Trim(SubStr(item, eq + 1))])
        }
        return fields
    }

    static Describe(p) {
        if !IsObject(p)
            return "No transcription service set up yet."
        host := RegExReplace(p.url, "i)^https?://([^/]+).*$", "$1")
        return p.name " (" host ", " p.model ")"
    }

    /**
     * Send one second of silence through the real transcription endpoint.
     * Returns {ok, message}.
     */
    static Test(p) {
        wav := A_Temp "\popper-test.wav"
        f := WavFile.Create(wav)
        f.RawWrite(Buffer(32000, 0), 32000)
        WavFile.Finish(f)
        started := A_TickCount
        r := Transcriber.RunSync(p, wav)
        try FileDelete(wav)
        secs := Round((A_TickCount - started) / 1000, 1)
        if r.code = 200
            return {ok: true, message: "Connected. The server answered in " secs " s."}
        return {ok: false, message: Transcriber.ExplainError(r.code, r.body, r.err)}
    }

    ; Model ids the server lists. Returns {ok, models[], message}.
    static ListModels(p) {
        out := A_Temp "\popper-models.json"
        cmd := Util.Quote(Util.CurlPath()) ' -sS --max-time 15 -A "Popper/' APP_VERSION '"'
        hdr := ""
        if p.key != "" {
            hdr := Transcriber.WriteHeaderFile(p.key)
            cmd .= ' -H "@' hdr '"'
        }
        cmd .= ' -o "' out '" "' this.ModelsUrl(p) '"'
        r := Util.RunCapture(cmd)
        if hdr != ""
            try FileDelete(hdr)
        models := []
        try {
            data := JSON.Load(FileRead(out, "UTF-8"))
            FileDelete(out)
            if data is Map && data.Has("data") {
                all := []
                for m in data["data"] {
                    id := m["id"]
                    all.Push(id)
                    task := m.Has("task") ? m["task"] : ""
                    if task = "automatic-speech-recognition" || RegExMatch(id, "i)whisper|transcribe|parakeet")
                        models.Push(id)
                }
                if !models.Length
                    models := all
            }
        }
        if models.Length
            return {ok: true, models: models, message: ""}
        return {ok: false, models: models, message: "The server did not return a model list. " Trim(r.out)}
    }
}

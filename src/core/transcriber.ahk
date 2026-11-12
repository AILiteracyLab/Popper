#Requires AutoHotkey v2.0

/**
 * Transcriber - sends finished chunks to the active profile, one at a time.
 *
 * Each upload runs in the Windows curl.exe as a separate hidden process, so a
 * slow server never freezes recording or the interface. The queue is the set
 * of session folders on disk: a chunk marked pending in session.ini is a job.
 * That makes the queue survive restarts, crashes and a laptop lid closing.
 *
 * Failure handling:
 *   cannot connect    wait and retry every minute, without limit
 *   401 / 403         pause until the user saves Settings
 *   429 / 5xx         back off, up to 6 tries
 *   other 4xx         2 tries, then mark the chunk failed
 */
class Transcriber {
    static Busy := false
    static Job := ""
    static RetryAt := 0
    static OnSessionDone := ""
    static _nextFn := ""
    static _checkFn := ""

    ; One bound function per timer, so SetTimer reschedules the same timer
    ; instead of starting a second one.
    static _NextTimer() {
        if !this._nextFn
            this._nextFn := ObjBindMethod(this, "_Next")
        return this._nextFn
    }

    static _CheckTimer() {
        if !this._checkFn
            this._checkFn := ObjBindMethod(this, "_Check")
        return this._checkFn
    }

    static Kick() {
        if this.Busy
            return
        SetTimer(this._NextTimer(), -200)
    }

    ; Called after Settings are saved: clear any pause and try again now.
    static Resume() {
        this.RetryAt := 0
        this.Kick()
    }

    static _Next() {
        Critical  ; no second _Next may start a duplicate upload mid-scan
        if this.Busy
            return
        if A_TickCount < this.RetryAt {
            SetTimer(this._NextTimer(), -(this.RetryAt - A_TickCount + 100))
            return
        }
        live := AppConfig.GetBool("Transcription", "LiveTranscribe")
        silence := AppConfig.GetInt("Audio", "SilencePeak", 0)
        profile := Profiles.Active()
        for s in Sessions.List() {
            st := s.Get("Status")
            if st != "processing" && !(st = "recording" && live)
                continue
            for pair in s.Chunks() {
                if pair[2] != "pending"
                    continue
                name := pair[1]
                if s.ChunkPeak(name) < silence {
                    s.SetChunk(name, "silent")
                    continue
                }
                if !IsObject(profile) {
                    s.Set("Waiting", "Waiting: add a transcription service in Settings")
                    return
                }
                this._Launch(s, name, profile)
                return
            }
            if st = "processing"
                this._Finalize(s)
        }
    }

    static _Launch(s, name, p) {
        hdr := ""
        cmd := this.BuildCommand(p, "audio\" name ".wav", "work\" name ".part", &hdr)
        full := A_ComSpec ' /c "' cmd ' > "work\' name '.code" 2> "work\' name '.err""'
        pid := 0
        try {
            Run(full, s.dir, "Hide", &pid)
        } catch as e {
            AppLog.Error("Could not start curl: " e.Message)
            if hdr != ""
                try FileDelete(hdr)
            this.RetryAt := A_TickCount + 60000
            this.Kick()
            return
        }
        this.Busy := true
        this.Job := {session: s, name: name, pid: pid, hdr: hdr, started: A_TickCount}
        s.Set("Waiting", "")
        SetTimer(this._CheckTimer(), 500)
    }

    static _Check() {
        j := this.Job
        if !IsObject(j) {
            SetTimer(this._CheckTimer(), 0)
            return
        }
        if ProcessExist(j.pid) {
            if A_TickCount - j.started > 960000
                try ProcessClose(j.pid)
            return
        }
        SetTimer(this._CheckTimer(), 0)
        if j.hdr != ""
            try FileDelete(j.hdr)
        s := j.session, name := j.name
        work := s.dir "\work\" name
        code := "", err := "", body := ""
        try code := Trim(FileRead(work ".code", "UTF-8"), " `r`n`t")
        try err := Trim(FileRead(work ".err", "UTF-8"), " `r`n`t")
        try body := FileRead(work ".part", "UTF-8")
        try FileDelete(work ".code")
        try FileDelete(work ".err")
        code := RegExMatch(code, "(\d{3})\s*$", &m) ? Integer(m[1]) : 0

        if code = 200 && this._Usable(body) {
            FileMove(work ".part", work ".json", true)
            s.SetChunk(name, "done")
            AppLog.Info("Transcribed " s.Name " / " name " in " Round((A_TickCount - j.started) / 1000) " s")
        } else {
            try FileDelete(work ".part")
            this._HandleFailure(s, name, code, body, err)
        }
        this.Busy := false
        this.Job := ""
        this.Kick()
    }

    static _Usable(body) {
        try {
            data := JSON.Load(body)
            return data is Map && (data.Has("segments") || data.Has("text"))
        }
        return false
    }

    static _HandleFailure(s, name, code, body, err) {
        msg := this.ExplainError(code, body, err)
        AppLog.Warn("Chunk " s.Name " / " name ": " msg)
        if code = 0 {
            s.Set("Waiting", "Waiting for the transcription service")
            this.RetryAt := A_TickCount + 60000
            return
        }
        if code = 401 || code = 403 {
            s.Set("Waiting", "Waiting: the service refused the API key")
            this.RetryAt := A_TickCount + 3600000
            return
        }
        tries := s.Attempts(name) + 1
        s.SetAttempts(name, tries)
        limit := (code = 429 || code >= 500) ? 6 : 2
        if tries >= limit {
            s.SetChunk(name, "failed")
            s.SetChunkError(name, msg)
            return
        }
        this.RetryAt := A_TickCount + Min(30000 * (2 ** (tries - 1)), 600000)
    }

    static _Finalize(s) {
        c := s.Counts()
        if c.pending > 0
            return
        try {
            Merger.Build(s)
        } catch as e {
            AppLog.Error("Could not build the transcript for " s.Name ": " e.Message)
            s.Set("Status", "failed")
            s.Set("Error", "could not build the transcript")
            return
        }
        if c.failed = 0 {
            s.Set("Status", "done")
        } else if c.done > 0 {
            s.Set("Status", "partial")
        } else {
            s.Set("Status", "failed")
            first := ""
            for pair in s.Chunks()
                if pair[2] = "failed" && first = ""
                    first := s.ChunkError(pair[1])
            s.Set("Error", first)
        }
        s.Set("Waiting", "")
        AppLog.Info("Session " s.Name " finished: " s.Get("Status"))
        if this.OnSessionDone {
            cb := this.OnSessionDone
            cb(s)
        }
    }

    /**
     * Build the curl command line. Paths may be relative to the working
     * directory the caller runs it in. hdr receives the temp header file
     * holding the API key, which the caller must delete.
     */
    static BuildCommand(p, wavPath, outPath, &hdr) {
        cmd := Util.Quote(Util.CurlPath()) ' -sS --max-time 900 -A "Popper/' APP_VERSION '" -X POST'
        hdr := ""
        if p.key != "" {
            hdr := this.WriteHeaderFile(p.key)
            cmd .= ' -H "@' hdr '"'
        }
        cmd .= ' -F "file=@' wavPath ';type=audio/wav"'
        if p.model != ""
            cmd .= ' -F "model=' p.model '"'
        cmd .= ' -F "response_format=verbose_json"'
        lang := Trim(AppConfig.Get("Transcription", "Language"))
        if lang != "" && lang != "auto"
            cmd .= ' -F "language=' lang '"'
        vocab := Trim(AppConfig.Get("Transcription", "Vocabulary"))
        if vocab != "" {
            promptFile := A_Temp "\popper-prompt.txt"
            Util.WriteText(promptFile, SubStr(vocab, 1, 800))
            cmd .= ' -F "prompt=<' promptFile '"'
        }
        for f in Profiles.ExtraFields(p)
            cmd .= ' -F "' f[1] '=' f[2] '"'
        fmt := A_Temp "\popper-fmt.txt"
        if !FileExist(fmt)
            Util.WriteText(fmt, "%{http_code}")
        cmd .= ' -w "@' fmt '" -o "' outPath '" "' Profiles.Endpoint(p) '"'
        return cmd
    }

    static WriteHeaderFile(key) {
        path := A_Temp "\popper-" A_TickCount "-" Random(100000, 999999) ".hdr"
        Util.WriteText(path, "Authorization: Bearer " key)
        return path
    }

    ; Blocking upload of one file, for Test buttons. Returns {code, body, err}.
    static RunSync(p, wavPath) {
        out := A_Temp "\popper-test.json"
        try FileDelete(out)
        hdr := ""
        cmd := this.BuildCommand(p, wavPath, out, &hdr)
        cmd := StrReplace(cmd, "--max-time 900", "--max-time 60")
        r := Util.RunCapture(cmd)
        if hdr != ""
            try FileDelete(hdr)
        body := ""
        try body := FileRead(out, "UTF-8")
        try FileDelete(out)
        code := RegExMatch(r.out, "(\d{3})\s*$", &m) ? Integer(m[1]) : 0
        return {code: code, body: body, err: code ? "" : Trim(r.out)}
    }

    static ExplainError(code, body, err) {
        detail := ""
        try {
            data := JSON.Load(body)
            if data is Map {
                if data.Has("error") {
                    e := data["error"]
                    detail := e is Map && e.Has("message") ? e["message"] : String(e)
                } else if data.Has("detail") {
                    d := data["detail"]
                    detail := d is String ? d : JSON.Dump(d)
                }
            }
        }
        if detail = "" && code != 0
            detail := SubStr(Trim(body), 1, 200)
        switch {
            case code = 0:
                base := "Could not reach the server."
                detail := err
            case code = 401 || code = 403:
                base := "The server refused the API key."
            case code = 404:
                base := "No transcription endpoint at that address. Check the server URL."
            case code = 413:
                base := "The server says the audio file is too large."
            case code = 429:
                base := "The server is rate limiting requests."
            case code >= 500:
                base := "The server had an error (" code ")."
            default:
                base := "The server answered " code "."
        }
        return detail != "" ? base " " SubStr(detail, 1, 300) : base
    }
}

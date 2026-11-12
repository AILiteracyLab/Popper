#Requires AutoHotkey v2.0

/**
 * Session - one recorded call, stored as a folder:
 *
 *   <Output folder>\2026-11-10 1402 Microsoft Teams\
 *     session.ini       status, times and per-chunk state
 *     audio\            mic-000.wav, system-000.wav, ...
 *     work\             raw transcription responses, one per chunk
 *     transcript.md     the result
 *
 * Status moves recording -> processing -> done | partial | failed.
 * Chunk state is pending, done, silent or failed.
 */
class Session {
    dir := ""
    ini := ""

    __New(dir) {
        this.dir := dir
        this.ini := dir "\session.ini"
    }

    Name => SubStr(this.dir, InStr(this.dir, "\", , -1) + 1)

    Get(key, def := "") => IniRead(this.ini, "Session", key, def)
    Set(key, value) => IniWrite(value, this.ini, "Session", key)

    AddChunk(name, frames, peak) {
        IniWrite("pending", this.ini, "Chunks", name)
        IniWrite(frames, this.ini, "Frames", name)
        IniWrite(peak, this.ini, "Peaks", name)
    }

    ChunkState(name) => IniRead(this.ini, "Chunks", name, "")
    SetChunk(name, state) => IniWrite(state, this.ini, "Chunks", name)
    ChunkPeak(name) => Integer(IniRead(this.ini, "Peaks", name, "0"))
    ChunkError(name) => IniRead(this.ini, "Errors", name, "")
    SetChunkError(name, msg) => IniWrite(msg, this.ini, "Errors", name)
    Attempts(name) => Integer(IniRead(this.ini, "Attempts", name, "0"))
    SetAttempts(name, n) => IniWrite(n, this.ini, "Attempts", name)

    ; Ordered array of [name, state].
    Chunks() {
        list := []
        try content := IniRead(this.ini, "Chunks")
        catch
            return list
        for line in StrSplit(content, "`n", "`r") {
            eq := InStr(line, "=")
            if eq
                list.Push([SubStr(line, 1, eq - 1), SubStr(line, eq + 1)])
        }
        return list
    }

    Counts() {
        c := {total: 0, pending: 0, done: 0, silent: 0, failed: 0}
        for pair in this.Chunks() {
            c.total++
            switch pair[2] {
                case "pending": c.pending++
                case "done": c.done++
                case "silent": c.silent++
                case "failed": c.failed++
            }
        }
        return c
    }

    DurationSeconds() {
        if this.Get("Status") = "recording" && Recorder.Active && Recorder.Session && Recorder.Session.dir = this.dir
            return Recorder.ElapsedSeconds()
        d := this.Get("DurationSec", "")
        if IsInteger(d)
            return Integer(d)
        started := this.Get("Started", ""), ended := this.Get("Ended", "")
        if started != "" && ended != ""
            return DateDiff(ended, started, "Seconds")
        return 0
    }

    TranscriptPath() => this.dir "\transcript.md"
    HasTranscript() => FileExist(this.TranscriptPath()) != ""

    StatusText() {
        st := this.Get("Status")
        switch st {
            case "recording":
                return "Recording"
            case "processing":
                c := this.Counts()
                waiting := this.Get("Waiting", "")
                if waiting != ""
                    return waiting
                if c.total = 0
                    return "Queued"
                return "Transcribing " (c.done + c.silent + c.failed) " of " c.total
            case "done":
                return "Done"
            case "partial":
                return "Done, with gaps"
            case "failed":
                return "Failed: " this.Get("Error", "see log")
        }
        return st
    }

    ResetFailed() {
        for pair in this.Chunks() {
            if pair[2] = "failed" {
                this.SetChunk(pair[1], "pending")
                this.SetAttempts(pair[1], 0)
            }
        }
        this.Set("Status", "processing")
        this.Set("Error", "")
        this.Set("Waiting", "")
    }
}

class Sessions {
    static Root() {
        root := AppConfig.Get("Output", "Folder", "")
        if root = ""
            root := EnvGet("USERPROFILE") "\Popper"
        if !DirExist(root)
            DirCreate(root)
        return root
    }

    static Create(appName, chunkSeconds) {
        root := this.Root()
        base := root "\" FormatTime(, "yyyy-MM-dd HHmm") " " Util.SafeName(appName)
        dir := base
        n := 2
        while DirExist(dir)
            dir := base " (" n++ ")"
        DirCreate(dir "\audio")
        DirCreate(dir "\work")
        s := Session(dir)
        s.Set("App", appName)
        s.Set("Started", A_Now)
        s.Set("ChunkSeconds", chunkSeconds)
        s.Set("Status", "recording")
        s.Set("Version", APP_VERSION)
        return s
    }

    ; Newest first.
    static List() {
        names := []
        Loop Files this.Root() "\*", "D" {
            if FileExist(A_LoopFileFullPath "\session.ini")
                names.Push(A_LoopFileName)
        }
        ; Folder names start with the date, so a reverse string sort is newest first.
        sorted := []
        for n in names
            sorted.Push(n)
        Loop sorted.Length - 1 {
            i := A_Index + 1
            while i > 1 && StrCompare(sorted[i - 1], sorted[i]) < 0 {
                t := sorted[i], sorted[i] := sorted[i - 1], sorted[i - 1] := t
                i--
            }
        }
        list := []
        root := this.Root()
        for n in sorted
            list.Push(Session(root "\" n))
        return list
    }

    /**
     * After a crash or power cut, sessions are left at "recording" with the
     * last chunk still open. Repair the files and queue them.
     */
    static Recover() {
        for s in this.List() {
            if s.Get("Status") != "recording"
                continue
            if Recorder.Active && Recorder.Session && Recorder.Session.dir = s.dir
                continue
            last := s.Get("Started")
            Loop Files s.dir "\audio\*.wav" {
                name := SubStr(A_LoopFileName, 1, -4)
                ; Read the time first: a stub under a second is deleted below.
                t := A_LoopFileTimeModified
                if StrCompare(t, last) > 0
                    last := t
                if s.ChunkState(name) = "" {
                    info := WavFile.Repair(A_LoopFileFullPath)
                    if info.frames >= 16000
                        s.AddChunk(name, info.frames, info.peak)
                    else
                        try FileDelete(A_LoopFileFullPath)
                }
            }
            s.Set("Ended", last)
            s.Set("Status", "processing")
            AppLog.Info("Recovered interrupted session " s.Name)
        }
    }

    ; Delete audio from finished sessions older than the retention window.
    static Cleanup() {
        days := AppConfig.GetInt("Output", "KeepAudioDays", 0)
        if days <= 0
            return
        for s in this.List() {
            st := s.Get("Status")
            if st != "done" && st != "partial"
                continue
            ended := s.Get("Ended", s.Get("Started"))
            if ended = "" || DateDiff(A_Now, ended, "Days") < days
                continue
            if DirExist(s.dir "\audio") {
                try {
                    DirDelete(s.dir "\audio", true)
                    AppLog.Info("Deleted audio older than " days " days: " s.Name)
                }
            }
        }
    }
}

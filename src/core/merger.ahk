#Requires AutoHotkey v2.0

/**
 * Merger - turns per-chunk transcription responses into one transcript.
 *
 * The mic track is you, the system track is everyone else, so each segment
 * gets its speaker from the track it came from. Chunk N of a track starts at
 * N x chunk length, because Track pads silence to keep wall-clock time.
 *
 * If you use speakers rather than a headset, your mic also hears the other
 * people. A mic segment whose words mostly appear in a system segment at the
 * same moment is that echo, and is dropped.
 */
class Merger {
    static Build(s) {
        chunkSec := Integer(s.Get("ChunkSeconds", "300"))
        mic := [], sys := []
        gaps := []
        for pair in s.Chunks() {
            name := pair[1], state := pair[2]
            parts := StrSplit(name, "-")
            kind := parts[1], idx := Integer(parts[2])
            offset := idx * chunkSec
            if state = "failed" {
                gaps.Push({kind: kind, start: offset, end: offset + chunkSec, reason: s.ChunkError(name)})
                continue
            }
            if state != "done"
                continue
            target := kind = "mic" ? mic : sys
            for seg in this._Segments(s.dir "\work\" name ".json", offset)
                target.Push(seg)
        }
        mic := this._DropEcho(mic, sys)
        merged := this._Interleave(mic, sys)
        turns := this._Turns(merged)
        this._WriteMarkdown(s, turns, gaps)
        if AppConfig.GetBool("Output", "WriteVtt")
            this._WriteVtt(s, turns)
        if AppConfig.GetBool("Output", "WriteTxt")
            this._WriteTxt(s, turns)
        return turns.Length
    }

    static Speaker(kind) {
        return AppConfig.Get("General", kind = "mic" ? "MyName" : "OthersName")
    }

    static _Segments(path, offset) {
        out := []
        data := JSON.Load(FileRead(path, "UTF-8"))
        if !(data is Map)
            return out
        if data.Has("segments") && data["segments"] is Array && data["segments"].Length {
            for seg in data["segments"] {
                text := Trim(seg["text"])
                if text = ""
                    continue
                ; Whisper's own rule for "this was silence": high no-speech
                ; probability and low confidence. Drops "Thank you." ghosts.
                nsp := seg.Has("no_speech_prob") ? this._Num(seg["no_speech_prob"]) : 0
                alp := seg.Has("avg_logprob") ? this._Num(seg["avg_logprob"]) : 0
                if nsp > 0.6 && alp < -1.0
                    continue
                out.Push({start: offset + this._Num(seg["start"]), end: offset + this._Num(seg["end"]), text: text})
            }
        } else if data.Has("text") && Trim(data["text"]) != "" {
            out.Push({start: offset, end: offset, text: Trim(data["text"])})
        }
        return out
    }

    static _Num(v) => IsNumber(v) ? v + 0 : 0

    static _Words(text) {
        words := Map()
        for w in StrSplit(RegExReplace(StrLower(text), "[^a-z0-9']+", " "), " ")
            if StrLen(w) >= 3
                words[w] := true
        return words
    }

    static _DropEcho(mic, sys) {
        if !sys.Length
            return mic
        kept := []
        j := 1
        for m in mic {
            mw := this._Words(m.text)
            echo := false
            if mw.Count >= 2 {
                while j <= sys.Length && sys[j].end < m.start - 2
                    j++
                k := j
                while k <= sys.Length && sys[k].start <= m.end + 2 {
                    sw := this._Words(sys[k].text)
                    hit := 0
                    for w in mw
                        if sw.Has(w)
                            hit++
                    if hit / mw.Count >= 0.6 {
                        echo := true
                        break
                    }
                    k++
                }
            }
            if !echo
                kept.Push(m)
        }
        return kept
    }

    static _Interleave(mic, sys) {
        out := []
        i := 1, j := 1
        while i <= mic.Length || j <= sys.Length {
            if j > sys.Length || (i <= mic.Length && mic[i].start <= sys[j].start) {
                seg := mic[i++], seg.kind := "mic"
            } else {
                seg := sys[j++], seg.kind := "system"
            }
            out.Push(seg)
        }
        return out
    }

    ; Join consecutive segments from one speaker into a turn.
    static _Turns(segs) {
        turns := []
        for seg in segs {
            if turns.Length {
                last := turns[turns.Length]
                if last.kind = seg.kind && seg.start - last.end < 3 {
                    last.text .= " " seg.text
                    last.end := Max(last.end, seg.end)
                    continue
                }
            }
            turns.Push({kind: seg.kind, start: seg.start, end: seg.end, text: seg.text})
        }
        return turns
    }

    static _Title(s) {
        started := s.Get("Started")
        return s.Get("App") " call, " FormatTime(started, "ddd d MMM yyyy, HH:mm")
    }

    static _WriteMarkdown(s, turns, gaps) {
        me := this.Speaker("mic"), them := this.Speaker("system")
        p := Profiles.Active()
        md := "# " this._Title(s) "`n`n"
        md .= "| | |`n|---|---|`n"
        md .= "| Length | " Util.Length(s.DurationSeconds()) " |`n"
        md .= "| Speakers | " me " (your microphone), " them " (call audio) |`n"
        md .= "| Transcribed by | " (IsObject(p) ? p.name " (" p.model ")" : "unknown") " |`n"
        md .= "| Recorded by | Popper " APP_VERSION " |`n`n"
        md .= "Machine transcript. Check names and numbers before you rely on them.`n`n"
        if gaps.Length {
            md .= "Missing audio:`n`n"
            for g in gaps
                md .= "- " Util.Clock(g.start) " to " Util.Clock(g.end) ", " this.Speaker(g.kind) ": " g.reason "`n"
            md .= "`n"
        }
        md .= "---`n`n"
        if !turns.Length
            md .= "No speech was found in this recording.`n"
        for t in turns
            md .= "**[" Util.Clock(t.start) "] " this.Speaker(t.kind) ":** " t.text "`n`n"
        Util.WriteText(s.dir "\transcript.md", md)
    }

    static _WriteVtt(s, turns) {
        vtt := "WEBVTT`n`n"
        for t in turns {
            endT := t.end > t.start ? t.end : t.start + 2
            vtt .= this._VttTime(t.start) " --> " this._VttTime(endT) "`n<v " this.Speaker(t.kind) ">" t.text "`n`n"
        }
        Util.WriteText(s.dir "\transcript.vtt", vtt)
    }

    static _WriteTxt(s, turns) {
        txt := this._Title(s) "`n`n"
        for t in turns
            txt .= "[" Util.Clock(t.start) "] " this.Speaker(t.kind) ": " t.text "`n"
        Util.WriteText(s.dir "\transcript.txt", txt)
    }

    static _VttTime(sec) {
        ms := Round(Mod(sec, 1) * 1000)
        if ms >= 1000
            ms := 999
        return Util.Clock(sec) "." Format("{:03}", ms)
    }
}

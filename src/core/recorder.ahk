#Requires AutoHotkey v2.0

/**
 * WavFile - 16 kHz mono 16-bit WAV writer.
 *
 * The header goes in first with placeholder sizes, so a file cut short by a
 * crash still opens. Sessions.Recover() patches the real sizes later.
 */
class WavFile {
    static Create(path) {
        f := FileOpen(path, "w", "CP0")
        f.RawWrite(WavFile.Header(0x7FFFFF00), 44)
        return f
    }

    static Header(dataBytes) {
        h := Buffer(44, 0)
        NumPut("uint", 0x46464952, h, 0)       ; "RIFF"
        NumPut("uint", 36 + dataBytes, h, 4)
        NumPut("uint", 0x45564157, h, 8)       ; "WAVE"
        NumPut("uint", 0x20746D66, h, 12)      ; "fmt "
        NumPut("uint", 16, h, 16)
        NumPut("ushort", 1, h, 20)             ; PCM
        NumPut("ushort", 1, h, 22)             ; mono
        NumPut("uint", 16000, h, 24)
        NumPut("uint", 32000, h, 28)
        NumPut("ushort", 2, h, 32)
        NumPut("ushort", 16, h, 34)
        NumPut("uint", 0x61746164, h, 36)      ; "data"
        NumPut("uint", dataBytes, h, 40)
        return h
    }

    static Finish(f) {
        dataBytes := f.Length - 44
        f.Pos := 4
        f.WriteUInt(36 + dataBytes)
        f.Pos := 40
        f.WriteUInt(dataBytes)
        f.Close()
        return dataBytes // 2
    }

    ; Fix the sizes of a file left open by a crash. Returns {frames, peak}.
    static Repair(path) {
        f := FileOpen(path, "rw", "CP0")
        size := f.Length
        dataBytes := size > 44 ? size - 44 : 0
        f.Pos := 4
        f.WriteUInt(36 + dataBytes)
        f.Pos := 40
        f.WriteUInt(dataBytes)
        f.Close()
        return {frames: dataBytes // 2, peak: WavFile.Peak(path)}
    }

    ; Loudness of the loudest second of a 16 kHz mono 16-bit WAV, in dBFS,
    ; from every 4th sample. -100 for an empty file.
    static LoudestSecondDb(path) {
        f := FileOpen(path, "r", "CP0")
        size := f.Length
        if size <= 44 {
            f.Close()
            return -100
        }
        f.Pos := 44
        buf := Buffer(size - 44)
        f.RawRead(buf, size - 44)
        f.Close()
        count := (size - 44) // 2
        best := 0
        sum := 0, n := 0
        i := 0
        while i < count {
            v := NumGet(buf, i * 2, "short")
            sum += v * v
            n++
            if n = 4000 {  ; one second at 16 kHz, every 4th sample
                if sum > best
                    best := sum
                sum := 0, n := 0
            }
            i += 4
        }
        if n > 0 && sum * 4000 / n > best
            best := sum * 4000 / n
        return best > 0 ? 10 * Log(best / 4000 / 1073741824) : -100
    }

    ; Sampled peak (every 40th sample) of a 16-bit WAV.
    static Peak(path) {
        f := FileOpen(path, "r", "CP0")
        size := f.Length
        if size <= 44 {
            f.Close()
            return 0
        }
        f.Pos := 44
        buf := Buffer(size - 44)
        f.RawRead(buf, size - 44)
        f.Close()
        peak := 0
        count := (size - 44) // 2
        i := 0
        while i < count {
            v := Abs(NumGet(buf, i * 2, "short"))
            if v > peak
                peak := v
            i += 40
        }
        return peak
    }
}

/**
 * Track - one capture stream written to a run of WAV chunks.
 *
 * The track keeps to wall-clock time. Loopback capture delivers nothing while
 * the call is silent, so the track pads with zeros whenever it falls more than
 * half a second behind. Chunk N therefore always starts at N x chunk length,
 * which is what lets the two tracks line up in the transcript.
 */
class Track {
    static RATE := 16000

    kind := ""
    dir := ""
    deviceSetting := ""
    chunkCap := 0
    onChunk := ""
    stream := ""
    file := ""
    chunkIndex := 0
    framesInChunk := 0
    totalFrames := 0
    startQpc := 0
    peak := 0
    lastReopen := 0
    zeroBuf := ""

    __New(kind, dir, chunkSeconds, deviceSetting, onChunk) {
        this.kind := kind
        this.dir := dir
        this.chunkCap := chunkSeconds * Track.RATE
        this.deviceSetting := deviceSetting
        this.onChunk := onChunk
        this.zeroBuf := Buffer(Track.RATE * 2, 0)
    }

    Start(startQpc) {
        this.startQpc := startQpc
        this._OpenChunk()
        this._OpenStream()
    }

    Poll() {
        if this.stream {
            try {
                this.stream.Read(this)
            } catch as e {
                AppLog.Warn(this.kind ": capture stopped (" e.Message "), reopening")
                try this.stream.Close()
                this.stream := ""
                this.lastReopen := A_TickCount
            }
        } else if A_TickCount - this.lastReopen > 2000 {
            this.lastReopen := A_TickCount
            this._OpenStream()
        }
        expected := Floor(Util.SecondsSince(this.startQpc) * Track.RATE)
        behind := expected - this.totalFrames
        if behind > Track.RATE // 2
            this.WriteSilence(behind - Track.RATE // 10)
    }

    ; Follow the Windows default device when the user plugs in a headset.
    CheckDefaultDevice() {
        if !this.stream || (this.deviceSetting != "default" && this.deviceSetting != "comms")
            return
        try {
            flow := this.kind = "system" ? AudioDevices.FLOW_RENDER : AudioDevices.FLOW_CAPTURE
            current := AudioDevices.GetId(AudioDevices.Resolve(flow, this.deviceSetting))
            if current != this.stream.deviceId {
                AppLog.Info(this.kind ": default device changed, switching")
                try this.stream.Read(this)
                this.stream.Close()
                this.stream := ""
                this._OpenStream()
            }
        }
    }

    DeviceName() => this.stream ? this.stream.deviceName : ""

    Write(ptr, frames) {
        while frames > 0 {
            n := Min(frames, this.chunkCap - this.framesInChunk)
            this.file.RawWrite({Ptr: ptr, Size: n * 2}, n * 2)
            i := 0
            while i < n {
                v := Abs(NumGet(ptr, i * 2, "short"))
                if v > this.peak
                    this.peak := v
                i += 40
            }
            ptr += n * 2
            frames -= n
            this._Advance(n)
        }
    }

    WriteSilence(frames) {
        while frames > 0 {
            n := Min(frames, Track.RATE, this.chunkCap - this.framesInChunk)
            this.file.RawWrite(this.zeroBuf, n * 2)
            frames -= n
            this._Advance(n)
        }
    }

    Finish() {
        if this.stream {
            try this.stream.Read(this)
            this.stream.Close()
            this.stream := ""
        }
        this._CloseChunk(true)
    }

    _Advance(n) {
        this.framesInChunk += n
        this.totalFrames += n
        if this.framesInChunk >= this.chunkCap {
            this._CloseChunk(false)
            this.chunkIndex++
            this._OpenChunk()
        }
    }

    _ChunkName() => this.kind "-" Format("{:03}", this.chunkIndex)

    _OpenChunk() {
        this.file := WavFile.Create(this.dir "\audio\" this._ChunkName() ".wav")
        this.framesInChunk := 0
        this.peak := 0
    }

    _CloseChunk(final) {
        if !this.file
            return
        name := this._ChunkName()
        path := this.dir "\audio\" name ".wav"
        frames := WavFile.Finish(this.file)
        this.file := ""
        ; A final chunk under a second long has nothing worth sending.
        if final && frames < Track.RATE {
            try FileDelete(path)
            return
        }
        cb := this.onChunk
        cb(name, frames, this.peak)
    }

    _OpenStream() {
        s := CaptureStream(this.kind, this.deviceSetting)
        try {
            s.Open()
            this.stream := s
        } catch as e {
            this.stream := ""
            AppLog.Warn(this.kind ": could not open device (" e.Message ")")
        }
    }
}

/**
 * Recorder - one recording session made of a mic track and a system track.
 */
class Recorder {
    static Active := false
    static Session := ""
    static Tracks := []
    static AppName := ""
    static Auto := false
    static StartTick := 0
    static _timer := ""

    static Start(appName, auto) {
        if this.Active
            return false
        chunkSeconds := AppConfig.GetInt("Audio", "ChunkMinutes", 1, 10) * 60
        this.Session := Sessions.Create(appName, chunkSeconds)
        this.AppName := appName
        this.Auto := auto
        this.Tracks := []
        onChunk := ObjBindMethod(this, "_OnChunk")
        this.Tracks.Push(Track("system", this.Session.dir, chunkSeconds, AppConfig.Get("Audio", "SpeakerDevice"), onChunk))
        if AppConfig.GetBool("Audio", "RecordMic")
            this.Tracks.Push(Track("mic", this.Session.dir, chunkSeconds, AppConfig.Get("Audio", "MicDevice"), onChunk))
        startQpc := Util.Qpc()
        for t in this.Tracks
            t.Start(startQpc)
        this.Active := true
        this.StartTick := A_TickCount
        this._timer := ObjBindMethod(this, "_Poll")
        SetTimer(this._timer, 40)
        names := ""
        for t in this.Tracks
            names .= (names = "" ? "" : ", ") t.kind "=" (t.DeviceName() = "" ? "none" : t.DeviceName())
        AppLog.Info("Recording started for " appName (auto ? " (automatic)" : " (manual)") ": " names)
        return true
    }

    static Stop(discard := false) {
        Critical  ; the poll timer must not write while the tracks close
        if !this.Active
            return ""
        SetTimer(this._timer, 0)
        for t in this.Tracks
            t.Finish()
        this.Active := false
        s := this.Session
        this.Session := ""
        this.Tracks := []
        seconds := (A_TickCount - this.StartTick) // 1000
        if discard {
            try DirDelete(s.dir, true)
            AppLog.Info("Recording discarded after " seconds " s")
            return ""
        }
        s.Set("Ended", A_Now)
        s.Set("DurationSec", seconds)
        s.Set("Status", "processing")
        AppLog.Info("Recording stopped after " seconds " s")
        Transcriber.Kick()
        return s
    }

    static ElapsedSeconds() => this.Active ? (A_TickCount - this.StartTick) // 1000 : 0

    static CheckDevices() {
        if this.Active {
            for t in this.Tracks
                t.CheckDefaultDevice()
        }
    }

    static _Poll() {
        Critical  ; a Stop button must not close a file mid-write
        if !this.Active
            return
        for t in this.Tracks
            t.Poll()
    }

    static _OnChunk(name, frames, peak) {
        if !this.Session
            return
        this.Session.AddChunk(name, frames, peak)
        if AppConfig.GetBool("Transcription", "LiveTranscribe")
            Transcriber.Kick()
    }
}

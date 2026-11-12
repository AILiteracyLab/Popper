#Requires AutoHotkey v2.0

/**
 * WASAPI audio capture through raw COM vtable calls.
 *
 * Two kinds of stream:
 *   mic    - a capture endpoint (your microphone)
 *   system - a render endpoint opened in loopback mode (what you hear)
 *
 * Every stream is delivered to its sink as 16 kHz, mono, signed 16-bit PCM.
 * Windows does the conversion when it can (AUTOCONVERTPCM). If the device
 * refuses, the stream opens in the device's own mix format and this class
 * downmixes and resamples in script.
 */

class AudioDevices {
    static CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
    static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    static PKEY_FriendlyName := "{A45C254E-DF1C-4EFD-8020-67D146A850E0}"

    static FLOW_RENDER := 0
    static FLOW_CAPTURE := 1

    static Enumerator() => ComObject(this.CLSID_MMDeviceEnumerator, this.IID_IMMDeviceEnumerator)

    /**
     * List active devices. flow: 0 = speakers, 1 = microphones.
     * Returns an array of {id, name}.
     */
    static List(flow) {
        devices := []
        try {
            en := this.Enumerator()
            pCol := 0
            ComCall(3, en, "int", flow, "uint", 1, "ptr*", &pCol)  ; EnumAudioEndpoints, DEVICE_STATE_ACTIVE
            col := ComValue(13, pCol)
            count := 0
            ComCall(3, col, "uint*", &count)  ; GetCount
            Loop count {
                pDev := 0
                ComCall(4, col, "uint", A_Index - 1, "ptr*", &pDev)  ; Item
                dev := ComValue(13, pDev)
                devices.Push({id: this.GetId(dev), name: this.GetName(dev)})
            }
        } catch as e {
            AppLog.Warn("Device list failed: " e.Message)
        }
        return devices
    }

    /**
     * Resolve a device setting to an IMMDevice.
     * setting: "default", "comms" or a device id.
     */
    static Resolve(flow, setting) {
        en := this.Enumerator()
        p := 0
        if setting != "default" && setting != "comms" && setting != "" {
            try {
                ComCall(5, en, "wstr", setting, "ptr*", &p)  ; GetDevice
                dev := ComValue(13, p)
                state := 0
                ComCall(6, dev, "uint*", &state)  ; GetState
                if state = 1                      ; DEVICE_STATE_ACTIVE
                    return dev
                AppLog.Warn("Saved device is unplugged or disabled, using the Windows default")
            } catch {
                AppLog.Warn("Saved device not found, using the Windows default")
            }
            p := 0
        }
        role := setting = "comms" ? 2 : 0  ; eCommunications : eConsole
        ComCall(4, en, "int", flow, "int", role, "ptr*", &p)  ; GetDefaultAudioEndpoint
        return ComValue(13, p)
    }

    static GetId(dev) {
        pId := 0
        ComCall(5, dev, "ptr*", &pId)
        id := StrGet(pId, "UTF-16")
        DllCall("ole32\CoTaskMemFree", "ptr", pId)
        return id
    }

    static GetName(dev) {
        name := ""
        try {
            pStore := 0
            ComCall(4, dev, "uint", 0, "ptr*", &pStore)  ; OpenPropertyStore(STGM_READ)
            store := ComValue(13, pStore)
            key := Buffer(20, 0)
            DllCall("ole32\CLSIDFromString", "wstr", this.PKEY_FriendlyName, "ptr", key)
            NumPut("uint", 14, key, 16)
            pv := Buffer(24, 0)
            ComCall(5, store, "ptr", key, "ptr", pv)  ; GetValue
            if NumGet(pv, 0, "ushort") = 31  ; VT_LPWSTR
                name := StrGet(NumGet(pv, 8, "ptr"), "UTF-16")
            DllCall("ole32\PropVariantClear", "ptr", pv)
        }
        return name
    }
}

class CaptureStream {
    static IID_IAudioClient := "{1CB9AD4C-DBFA-4C32-B178-C2F568A703B2}"
    static IID_IAudioCaptureClient := "{C8ADBD64-E71E-48A0-A4DE-185C395CD317}"

    static RATE := 16000
    static LOOPBACK := 0x00020000
    static AUTOCONVERT := 0x80000000 | 0x08000000  ; AUTOCONVERTPCM | SRC_DEFAULT_QUALITY
    static BUFFER_HNS := 40000000                  ; 4 s of device buffer

    kind := ""
    deviceSetting := ""
    deviceId := ""
    deviceName := ""
    client := ""
    capture := ""
    converting := false
    srcRate := 16000
    srcChannels := 1
    srcFloat := false
    srcBytes := 2
    srcBlock := 2
    phase := 0.0
    convBuf := ""

    __New(kind, deviceSetting) {
        this.kind := kind
        this.deviceSetting := deviceSetting
    }

    Open() {
        flow := this.kind = "system" ? AudioDevices.FLOW_RENDER : AudioDevices.FLOW_CAPTURE
        dev := AudioDevices.Resolve(flow, this.deviceSetting)
        this.deviceId := AudioDevices.GetId(dev)
        this.deviceName := AudioDevices.GetName(dev)
        baseFlags := this.kind = "system" ? CaptureStream.LOOPBACK : 0

        ; First choice: ask Windows for 16 kHz mono 16-bit directly.
        this.client := this._Activate(dev)
        fmt := CaptureStream.PcmFormat()
        try {
            ComCall(3, this.client, "int", 0, "uint", baseFlags | CaptureStream.AUTOCONVERT
                , "int64", CaptureStream.BUFFER_HNS, "int64", 0, "ptr", fmt, "ptr", 0)
            this.converting := false
        } catch as e {
            ; Fallback: the device's own format, converted in script.
            AppLog.Info(this.kind ": auto-convert refused (" e.Message "), converting in script")
            this.client := this._Activate(dev)
            pMix := 0
            ComCall(8, this.client, "ptr*", &pMix)  ; GetMixFormat
            this._ReadMixFormat(pMix)
            try {
                ComCall(3, this.client, "int", 0, "uint", baseFlags
                    , "int64", CaptureStream.BUFFER_HNS, "int64", 0, "ptr", pMix, "ptr", 0)
            } finally {
                DllCall("ole32\CoTaskMemFree", "ptr", pMix)
            }
            this.converting := true
            this.phase := 0.0
        }

        pCap := 0
        ComCall(14, this.client, "ptr", Util.Guid(CaptureStream.IID_IAudioCaptureClient), "ptr*", &pCap)  ; GetService
        this.capture := ComValue(13, pCap)
        ComCall(10, this.client)  ; Start
        AppLog.Info(this.kind ": opened '" this.deviceName "'" (this.converting ? " (" this.srcRate " Hz, " this.srcChannels " ch, script conversion)" : ""))
    }

    Close() {
        if this.client {
            try ComCall(11, this.client)  ; Stop
        }
        this.capture := ""
        this.client := ""
    }

    /**
     * Drain every waiting packet into sink.Write(ptr, frames) or
     * sink.WriteSilence(frames). Frames are 16 kHz mono 16-bit.
     * Throws if the device has gone away.
     */
    Read(sink) {
        Loop {
            n := 0
            ComCall(5, this.capture, "uint*", &n)  ; GetNextPacketSize
            if n = 0
                return
            pData := 0, frames := 0, flags := 0, devPos := 0, qpcPos := 0
            ComCall(3, this.capture, "ptr*", &pData, "uint*", &frames, "uint*", &flags, "int64*", &devPos, "int64*", &qpcPos)  ; GetBuffer
            silent := flags & 0x2
            if !this.converting {
                if silent
                    sink.WriteSilence(frames)
                else
                    sink.Write(pData, frames)
            } else {
                if silent {
                    sink.WriteSilence(this._OutCount(frames))
                } else {
                    out := this._Convert(pData, frames)
                    if out
                        sink.Write(this.convBuf.Ptr, out)
                }
            }
            ComCall(4, this.capture, "uint", frames)  ; ReleaseBuffer
        }
    }

    _Activate(dev) {
        p := 0
        ComCall(3, dev, "ptr", Util.Guid(CaptureStream.IID_IAudioClient), "uint", 23, "ptr", 0, "ptr*", &p)  ; Activate, CLSCTX_ALL
        return ComValue(13, p)
    }

    static PcmFormat() {
        fmt := Buffer(18, 0)
        NumPut("ushort", 1, fmt, 0)                        ; WAVE_FORMAT_PCM
        NumPut("ushort", 1, fmt, 2)                        ; mono
        NumPut("uint", CaptureStream.RATE, fmt, 4)
        NumPut("uint", CaptureStream.RATE * 2, fmt, 8)
        NumPut("ushort", 2, fmt, 12)                       ; block align
        NumPut("ushort", 16, fmt, 14)                      ; bits
        NumPut("ushort", 0, fmt, 16)
        return fmt
    }

    _ReadMixFormat(p) {
        tag := NumGet(p, 0, "ushort")
        this.srcChannels := NumGet(p, 2, "ushort")
        this.srcRate := NumGet(p, 4, "uint")
        this.srcBlock := NumGet(p, 12, "ushort")
        bits := NumGet(p, 14, "ushort")
        if tag = 0xFFFE  ; WAVE_FORMAT_EXTENSIBLE: first dword of SubFormat is the real tag
            tag := NumGet(p, 24, "uint")
        this.srcFloat := tag = 3
        this.srcBytes := bits // 8
        if !((this.srcFloat && bits = 32) || (!this.srcFloat && bits = 16))
            throw Error("Unsupported device format: tag " tag ", " bits " bits")
    }

    _OutCount(frames) {
        ratio := this.srcRate / CaptureStream.RATE
        count := 0
        pos := this.phase
        while pos < frames {
            count++
            pos += ratio
        }
        this.phase := pos - frames
        return count
    }

    _Convert(pData, frames) {
        ratio := this.srcRate / CaptureStream.RATE
        need := (Ceil(frames / ratio) + 4) * 2
        if !this.convBuf || this.convBuf.Size < need
            this.convBuf := Buffer(need, 0)
        ch := this.srcChannels, bps := this.srcBytes, block := this.srcBlock
        isFloat := this.srcFloat
        buf := this.convBuf
        n := 0
        pos := this.phase
        while pos < frames {
            base := Floor(pos) * block
            sum := 0.0
            Loop ch {
                off := base + (A_Index - 1) * bps
                sum += isFloat ? NumGet(pData, off, "float") : NumGet(pData, off, "short") / 32768
            }
            v := Round(sum / ch * 32767)
            v := v > 32767 ? 32767 : v < -32768 ? -32768 : v
            NumPut("short", v, buf, n * 2)
            n++
            pos += ratio
        }
        this.phase := pos - frames
        return n
    }
}

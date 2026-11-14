#Requires AutoHotkey v2.0

/**
 * Detector - spots a call by watching which app holds the microphone.
 *
 * Windows records microphone use per app under CapabilityAccessManager, the
 * same list that drives the privacy icon in the taskbar. An app is using the
 * mic right now when its LastUsedTimeStop is 0. Store apps (new Teams) are
 * listed by package name, desktop apps under NonPackaged by exe path with
 * each backslash written as #.
 *
 * No audio is read here, and nothing is sent anywhere.
 */
class Detector {
    ; Not "Base": every object has a built-in Base property.
    static RegRoot := "Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone"

    /**
     * Every app Windows has seen use the mic, plus any app recording now.
     * Returns an array of {key, label, inUse, lastStart}.
     */
    static Entries() {
        list := []
        for sub in ["", "\NonPackaged"] {
            path := this.RegRoot sub
            try {
                Loop Reg "HKCU\" path, "K" {
                    name := A_LoopRegName
                    if name = "NonPackaged"
                        continue
                    stop := this._Qword(path "\" name, "LastUsedTimeStop")
                    start := this._Qword(path "\" name, "LastUsedTimeStart")
                    if start = ""
                        continue
                    list.Push({key: name, label: this.Label(name), inUse: start > 0 && stop = 0, lastStart: start})
                }
            }
        }
        ; Some Windows builds stop updating that list. Ask the audio engine
        ; which apps are recording right now as well, and trust either source.
        live := Map()
        try live := this.LiveCaptureKeys()
        for e in list {
            k := StrLower(e.key)
            if live.Has(k) {
                e.inUse := true
                live.Delete(k)
            }
        }
        now := 0
        DllCall("GetSystemTimeAsFileTime", "int64*", &now)
        for k, key in live
            list.Push({key: key, label: this.Label(key), inUse: true, lastStart: now})
        return list
    }

    static IID_IAudioSessionManager2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
    static IID_IAudioSessionControl2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"

    /**
     * Apps with an active capture session on any microphone, straight from
     * the Windows audio engine. Keys use the registry's NonPackaged form,
     * the exe path with each backslash written as #.
     * Returns a Map of lowercase key -> key.
     */
    static LiveCaptureKeys() {
        keys := Map()
        en := AudioDevices.Enumerator()
        pCol := 0
        ComCall(3, en, "int", 1, "uint", 1, "ptr*", &pCol)  ; EnumAudioEndpoints(eCapture, ACTIVE)
        col := ComValue(13, pCol)
        count := 0
        ComCall(3, col, "uint*", &count)  ; GetCount
        Loop count {
            try {
                pDev := 0
                ComCall(4, col, "uint", A_Index - 1, "ptr*", &pDev)  ; Item
                dev := ComValue(13, pDev)
                pMgr := 0
                ComCall(3, dev, "ptr", Util.Guid(this.IID_IAudioSessionManager2), "uint", 23, "ptr", 0, "ptr*", &pMgr)  ; Activate
                mgr := ComValue(13, pMgr)
                pEnum := 0
                ComCall(5, mgr, "ptr*", &pEnum)  ; GetSessionEnumerator
                sessions := ComValue(13, pEnum)
                n := 0
                ComCall(3, sessions, "int*", &n)  ; GetCount
                Loop n {
                    try {
                        pCtl := 0
                        ComCall(4, sessions, "int", A_Index - 1, "ptr*", &pCtl)  ; GetSession
                        ctl := ComValue(13, pCtl)
                        state := 0
                        ComCall(3, ctl, "int*", &state)  ; GetState
                        if state != 1  ; AudioSessionStateActive
                            continue
                        ctl2 := ComObjQuery(ctl, this.IID_IAudioSessionControl2)
                        pid := 0
                        ComCall(14, ctl2, "uint*", &pid)  ; GetProcessId
                        if pid = 0
                            continue
                        key := StrReplace(ProcessGetPath(pid), "\", "#")
                        keys[StrLower(key)] := key
                    }
                }
            }
        }
        return keys
    }

    ; The watched app that is on a call now, or "".
    static ActiveApp() {
        self := this._SelfKey()
        apps := this.WatchedApps()
        for e in this.Entries() {
            if !e.inUse || StrLower(e.key) = self
                continue
            k := StrLower(e.key)
            for app in apps {
                if !app.enabled
                    continue
                for m in app.matches {
                    if m != "" && InStr(k, m)
                        return app.name
                }
            }
        }
        return ""
    }

    ; [{name, enabled, matches[]}] from the [Apps] section.
    static WatchedApps() {
        apps := []
        for pair in AppConfig.GetPairs("Apps") {
            parts := StrSplit(pair[2], "|", , 2)
            matches := []
            if parts.Length > 1 {
                for m in StrSplit(parts[2], ",")
                    if Trim(m) != ""
                        matches.Push(StrLower(Trim(m)))
            }
            apps.Push({name: pair[1], enabled: parts[1] = "1", matches: matches})
        }
        return apps
    }

    static SaveWatchedApps(apps) {
        AppConfig.DeleteSection("Apps")
        for app in apps {
            m := ""
            for x in app.matches
                m .= (m = "" ? "" : ",") x
            AppConfig.Set("Apps", app.name, (app.enabled ? "1" : "0") "|" m)
        }
    }

    ; A readable name and a suggested match for a registry key.
    static Label(key) {
        if InStr(key, "#") {
            exe := SubStr(key, InStr(key, "#", , -1) + 1)
            return exe
        }
        us := InStr(key, "_")
        return us ? SubStr(key, 1, us - 1) : key
    }

    static SuggestMatch(key) {
        if InStr(key, "#")
            return "#" StrLower(SubStr(key, InStr(key, "#", , -1) + 1))
        us := InStr(key, "_")
        return StrLower(us ? SubStr(key, 1, us) : key)
    }

    static _SelfKey() {
        exe := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
        return StrLower(StrReplace(exe, "\", "#"))
    }

    static _Qword(subKey, valueName) {
        val := 0
        size := 8
        ; HKEY_CURRENT_USER is a sign-extended handle on 64-bit; RRF_RT_QWORD
        r := DllCall("advapi32\RegGetValueW", "ptr", -2147483647, "wstr", subKey, "wstr", valueName
            , "uint", 0x48, "ptr", 0, "int64*", &val, "uint*", &size, "int")
        return r = 0 ? val : ""
    }
}

#Requires AutoHotkey v2.0

/**
 * Small helpers shared across modules.
 */
class Util {
    static _qpf := 0
    ; Appended to every window's Show options. The UI test sets it to place
    ; windows off-screen; it is empty in normal use.
    static ShowExtra := ""

    static Qpc() {
        c := 0
        DllCall("QueryPerformanceCounter", "int64*", &c)
        return c
    }

    static QpcFreq() {
        if !this._qpf {
            f := 0
            DllCall("QueryPerformanceFrequency", "int64*", &f)
            this._qpf := f
        }
        return this._qpf
    }

    static SecondsSince(qpc) => (this.Qpc() - qpc) / this.QpcFreq()

    static Guid(str) {
        buf := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "wstr", str, "ptr", buf, "hresult")
        return buf
    }

    ; 3725 -> "01:02:05"
    static Clock(seconds) {
        s := Floor(seconds)
        return Format("{:02}:{:02}:{:02}", s // 3600, Mod(s // 60, 60), Mod(s, 60))
    }

    ; 3725 -> "1 h 2 min", 95 -> "1 min 35 s"
    static Length(seconds) {
        s := Floor(seconds)
        if s >= 3600
            return (s // 3600) " h " Mod(s // 60, 60) " min"
        if s >= 60
            return (s // 60) " min " Mod(s, 60) " s"
        return s " s"
    }

    ; Keep a name safe for folder names and for curl's -F parser.
    static SafeName(name) {
        name := RegExReplace(name, "[^A-Za-z0-9 ._-]", "")
        name := Trim(RegExReplace(name, "\s+", " "))
        return name = "" ? "Call" : SubStr(name, 1, 40)
    }

    ; Overwrite a file with UTF-8 text and no byte order mark.
    static WriteText(path, text) {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(text)
        f.Close()
    }

    static ReadText(path) {
        return FileRead(path, "UTF-8")
    }

    static CurlPath() {
        p := A_WinDir "\System32\curl.exe"
        return FileExist(p) ? p : "curl.exe"
    }

    static AssetPath(name) {
        for dir in [A_ScriptDir "\assets", A_ScriptDir "\..\assets"] {
            if FileExist(dir "\" name)
                return dir "\" name
        }
        return ""
    }

    ; Run a command hidden and wait. Returns {exit, out}. Timers keep running.
    static RunCapture(cmdLine, workDir := "") {
        tmp := A_Temp "\popper-" A_TickCount "-" Random(1000, 9999) ".out"
        exitCode := RunWait(A_ComSpec ' /c "' cmdLine ' > "' tmp '" 2>&1"', workDir, "Hide")
        out := ""
        try out := FileRead(tmp, "UTF-8")
        try FileDelete(tmp)
        return {exit: exitCode, out: out}
    }

    static Quote(s) => '"' s '"'
}

#Requires AutoHotkey v2.0

/**
 * AppLog - plain-text log at %AppData%\Popper\popper.log
 *
 * The log never records transcript text or API keys. It rolls over at 1 MB,
 * keeping one previous file.
 */
class AppLog {
    static Path := A_AppData "\Popper\popper.log"

    static Write(level, msg) {
        try {
            if FileExist(this.Path) && FileGetSize(this.Path) > 1048576
                FileMove(this.Path, this.Path ".old", true)
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " [" level "] " msg "`n", this.Path, "UTF-8")
        }
    }

    static Info(msg) => this.Write("info", msg)
    static Warn(msg) => this.Write("warn", msg)
    static Error(msg) => this.Write("error", msg)
}

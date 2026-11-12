#Requires AutoHotkey v2.0

/**
 * CredentialManager - API keys encrypted with Windows DPAPI
 *
 * DPAPI ties the ciphertext to the current Windows user on this machine, so
 * copying settings.ini to another account or computer does not leak the key.
 * Keys are stored base64-encoded in the [Credentials] section of settings.ini.
 */
class CredentialManager {
    static Section := "Credentials"

    static Store(name, key) {
        if key = "" {
            this.Delete(name)
            return true
        }
        enc := this._Protect(key)
        if enc = ""
            return false
        AppConfig.Set(this.Section, name, enc)
        return true
    }

    static Retrieve(name) {
        enc := AppConfig.Get(this.Section, name, "")
        return enc = "" ? "" : this._Unprotect(enc)
    }

    static Delete(name) {
        AppConfig.Delete(this.Section, name)
    }

    static GetMasked(name) {
        key := this.Retrieve(name)
        if key = ""
            return ""
        return StrLen(key) > 4 ? "********" SubStr(key, -4) : "****"
    }

    static IsMasked(text) => RegExMatch(text, "^\*{4,}.{0,4}$")

    static _Protect(text) {
        size := StrPut(text, "UTF-8") - 1
        data := Buffer(size + 1, 0)
        StrPut(text, data, "UTF-8")
        blobIn := this._Blob(data.Ptr, size)
        blobOut := Buffer(A_PtrSize * 2, 0)
        if !DllCall("crypt32\CryptProtectData", "ptr", blobIn, "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "uint", 1, "ptr", blobOut)
            return ""
        cb := NumGet(blobOut, 0, "uint")
        pb := NumGet(blobOut, A_PtrSize, "ptr")
        b64 := this._ToBase64(pb, cb)
        DllCall("LocalFree", "ptr", pb)
        return b64
    }

    static _Unprotect(b64) {
        raw := this._FromBase64(b64)
        if !raw
            return ""
        blobIn := this._Blob(raw.Ptr, raw.Size)
        blobOut := Buffer(A_PtrSize * 2, 0)
        if !DllCall("crypt32\CryptUnprotectData", "ptr", blobIn, "ptr", 0, "ptr", 0, "ptr", 0, "ptr", 0, "uint", 1, "ptr", blobOut)
            return ""
        cb := NumGet(blobOut, 0, "uint")
        pb := NumGet(blobOut, A_PtrSize, "ptr")
        text := StrGet(pb, cb, "UTF-8")
        DllCall("LocalFree", "ptr", pb)
        return text
    }

    static _Blob(ptr, size) {
        blob := Buffer(A_PtrSize * 2, 0)
        NumPut("uint", size, blob, 0)
        NumPut("ptr", ptr, blob, A_PtrSize)
        return blob
    }

    static _ToBase64(ptr, size) {
        flags := 0x40000001  ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
        chars := 0
        DllCall("crypt32\CryptBinaryToStringW", "ptr", ptr, "uint", size, "uint", flags, "ptr", 0, "uint*", &chars)
        out := Buffer(chars * 2, 0)
        DllCall("crypt32\CryptBinaryToStringW", "ptr", ptr, "uint", size, "uint", flags, "ptr", out, "uint*", &chars)
        return StrGet(out, "UTF-16")
    }

    static _FromBase64(b64) {
        size := 0
        if !DllCall("crypt32\CryptStringToBinaryW", "str", b64, "uint", 0, "uint", 1, "ptr", 0, "uint*", &size, "ptr", 0, "ptr", 0)
            return ""
        buf := Buffer(size, 0)
        if !DllCall("crypt32\CryptStringToBinaryW", "str", b64, "uint", 0, "uint", 1, "ptr", buf, "uint*", &size, "ptr", 0, "ptr", 0)
            return ""
        return buf
    }
}

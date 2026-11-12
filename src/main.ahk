#Requires AutoHotkey v2.0
#SingleInstance Force

; Set DPI awareness before any GUI is created
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

;@Ahk2Exe-SetName Popper
;@Ahk2Exe-SetDescription Backup meeting transcription for Windows
;@Ahk2Exe-SetVersion 0.1.0
;@Ahk2Exe-SetCopyright Copyright (c) 2026 Jamie Bykov-Brett
;@Ahk2Exe-SetCompanyName Bykov-Brett Enterprises

global APP_NAME := "Popper"
global APP_VERSION := "0.1.0"
global APP_REPO := "https://github.com/AILiteracyLab/Popper"

; Core
#Include lib\cJson.ahk
#Include core\config.ahk
#Include core\credentials.ahk
#Include core\applog.ahk
#Include core\util.ahk
#Include core\wasapi.ahk
#Include core\recorder.ahk
#Include core\detector.ahk
#Include core\sessions.ahk
#Include core\transcriber.ahk
#Include core\merger.ahk
#Include core\updater.ahk

; Providers
#Include providers\profiles.ahk

; UI
#Include ui\theme.ahk
#Include ui\tray.ahk
#Include ui\pill.ahk
#Include ui\main-window.ahk
#Include ui\settings.ahk
#Include ui\profile-editor.ahk
#Include ui\app-editor.ahk

; Controller
#Include core\app.ahk

global AppConfig := ConfigManager()
App.Start()
Persistent

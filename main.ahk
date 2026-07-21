#Requires AutoHotkey v2.0
#SingleInstance Force

#DllLoad "msftedit.dll"
#Include const.ahk
#Include сompilerWrapper.ahk
#Include IDE.ahk
#Include MCF_GUI.ahk

try global new_thread_check_update := Worker(" ; новый поток для проверки ласт версии (релиза) MCF.
(
    Persistent(true)
    global lastRequest := true
    CheckForUpdates(owner, repo, currentV, infoSuccess := true) {
        global lastRequest
        if (lastRequest) {
            lastRequest := false
            try {
                http := ComObject("WinHttp.WinHttpRequest.5.1")
                http.Open("GET", "https://github.com/" owner "/" repo "/releases/latest", false) ; обычная ссылка на Latest, не API (ибо есть проблемы с лимитами)
                http.Send()
                finalUrl := http.Option(1) ; итоговый URL после всех перенаправлений (Option(1) это свойство URL)
            } catch as er {
                return MsgBox("An unknown error occurred while checking for updates.``n" er.Message,, 0x10)
            }

            if RegExMatch(finalUrl, "tag/v?([^/]+)$", &m) { ; ".../releases/tag/v1.0.1" или ".../releases/tag/1.0.1" (v игнорируется)
                latestV := m[1]
                if (VerCompare(latestV, currentV) > 0) {
                    choice := MsgBox("New version available: " latestV "``nWant to watch the release?",, 0x44)
                    if (choice == "Yes") {
                        Run(finalUrl)
                    }
                } else {
                    if (infoSuccess) {
                        MsgBox("You have the latest version installed: " latestV,, 0x40)
                    }
                }
            } else {
                MsgBox("No releases found.",, 0x30)
            }
            lastRequest := true
        }
    }
)",, "MCF check update")


class main {
    __New() {
        global GLOBAL_INI_FILE, GLOBAL_WORKING_DIR, GLOBAL_WORKING_OUTPUT_DIR
        ; DirCreate(GLOBAL_WORKING_DIR)
        ; DirCreate(GLOBAL_WORKING_OUTPUT_DIR)

        defaultTempDir     := GLOBAL_WORKING_DIR
        defaultSettingsIni := GLOBAL_INI_FILE
        defaultOutputDir   := GLOBAL_WORKING_OUTPUT_DIR
        newTempDirPath     := RegRead("HKCU\Software\MCF", "TEMP_DIR", "")
        newSettingsIniPath := RegRead("HKCU\Software\MCF", "TEMP_SETTINGS_INI", "")
        newOutputDir       := RegRead("HKCU\Software\MCF", "TEMP_OUTPUT", "")

        try {
            DirCreate(newTempDirPath)
            GLOBAL_WORKING_DIR := newTempDirPath
        } catch {
            DirCreate(defaultTempDir)
            GLOBAL_WORKING_DIR := defaultTempDir
        }

        try {
            SplitPath(newSettingsIniPath,,,&ext)
            if (ext == "ini") {
                FileAppend("", newSettingsIniPath, "UTF-16")
                GLOBAL_INI_FILE := newSettingsIniPath
            } else {
                GLOBAL_INI_FILE := defaultSettingsIni
            }
        } catch {
            GLOBAL_INI_FILE := defaultSettingsIni
        }

        ; try {
        ;     DirCreate(newOutputDir)
        ;     GLOBAL_WORKING_OUTPUT_DIR := newOutputDir
        ; } catch {
        ;     GLOBAL_WORKING_OUTPUT_DIR := defaultOutputDir
        ; }

        if (IniRead(GLOBAL_INI_FILE, "SETTINGS", "CHECK_AUTO_UPDATE", false)) {
            new_thread_check_update.AsyncCall("CheckForUpdates", "Vedette1", "MCF.ahk", GLOBAL_MCF_VERSION, false)
        }
        GuiMcode()
    }
}
main()
#Requires AutoHotkey v2.0
#SingleInstance Force

#DllLoad "msftedit.dll"
#Include const.ahk
#Include сompilerWrapper.ahk
#Include IDE.ahk
#Include MCF_GUI.ahk

global new_thread_check_update := Worker(FileRead("threads\CheckForUpdates.ahk"),, "MCF check update") ; новый поток для проверки ласт версии (релиза) MCF.


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

        if (IniRead(GLOBAL_INI_FILE, "SETTINGS", "CHECK_AUTO_UPDATE", false)) {
            new_thread_check_update.AsyncCall("CheckForUpdates", "Vedette1", "MCF.ahk", GLOBAL_MCF_VERSION, false)
        }
        GuiMcode()
    }
}
main()
#Requires AutoHotkey v2.0
#SingleInstance Force

#DllLoad "msftedit.dll"

#Include const.ahk
#Include сompilerWrapper.ahk
#Include IDE.ahk
#Include MCF_GUI.ahk


class main {
    __New() {
        global GLOBAL_INI_FILE, GLOBAL_WORKING_DIR, GLOBAL_WORKING_OUTPUT_DIR
        DirCreate(GLOBAL_WORKING_DIR)
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

        try {
            DirCreate(newOutputDir)
            GLOBAL_WORKING_OUTPUT_DIR := newOutputDir
        } catch {
            GLOBAL_WORKING_OUTPUT_DIR := defaultOutputDir
        }

        m := GuiMcode()
    }
}
main()
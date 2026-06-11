#Requires AutoHotkey v2.0
#SingleInstance Force

#DllLoad "msftedit.dll"

#Include const.ahk
#Include сompilerWrapper.ahk
#Include IDE.ahk
#Include MCF_GUI.ahk


class main {
    __New() {
        DirCreate(GLOBAL_WORKING_DIR)
        DirCreate(GLOBAL_WORKING_OUTPUT_DIR)
        m := GuiMcode()
    }
}
main()
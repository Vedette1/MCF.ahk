#Requires AutoHotkey v2.0
#SingleInstance Force

#DllLoad "msftedit.dll"
#DllLoad "dbghelp.dll"
#Include const.ahk
#Include MCF_GUI.ahk
#Include threads\CheckForUpdates.ahk
try global new_thread_check_update := Worker(new_script_thread_check_update,, "MCF check update") ; новый поток для проверки ласт версии (релиза) MCF.


class main {
    __New() {
        if (IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "CHECK_AUTO_UPDATE", false)) {
            new_thread_check_update.AsyncCall("CheckForUpdates", "Vedette1", "MCF.ahk", Const.GLOBAL_MCF_VERSION, false)
        }
        GuiMcode()
    }
}
main()
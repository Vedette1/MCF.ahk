#Requires AutoHotkey v2.0
#SingleInstance Force

#Include const.ahk
#Include Lib\IDE.ahk
#Include Lib\CustomListView.ahk
#Include Lib\MCODE.ahk
#Include Lib\GuiReSizer.ahk
#Include Lib\CustomTitleBarWindow.ahk
#Include Lib\MyCtrl.ahk
#Include сompilerWrapper.ahk
#Include Static_Library_Viewer.ahk
#Include MCF.ahk


Join(arr, sep) => (arr.Length) ? ((s := '', i := 0, [(_ => (s .= arr[++i] . sep, i < arr.Length))*], Trim(s, sep))) : ""
GUIDataToArray(text) => StrSplit(RegExReplace(text, "(?m)^\h+|\h*//.*"), "`n", "`r").Filter((T) => T != "")

; Переводит многострочный текст из Edit в объект Map.
ParseEditToMap(text) {
    resultMap := Map()
    cleanText := RegExReplace(text, "(?m)^\h+|\h*//.*")
    for line in StrSplit(cleanText, "`n", "`r") {
        if (Trim(line) == "")
            continue
        parts := StrSplit(line, "->", " `t", 2)
        if (parts.Length == 2) {
            resultMap[parts[1]] := parts[2]
        }
    }
    return resultMap
}

/**
 * @param data Данные (Map при toEdit = false, либо String при toEdit = true)
 * @param toEdit Направление: false = в INI строку, true = в текст для Edit
 */
FormatIniData(data, toEdit := false) {
    if (toEdit) {
        return StrReplace(data, "|", "`r`n")
    } 

    iniStr := ""
    for line in StrSplit(data, "`n", "`r") {
        if (Trim(line) == "")
            continue
        iniStr .= line "|"
    }
    return RTrim(iniStr, "|")
}


QPC() {
    static c := 0, f := (DllCall("QueryPerformanceFrequency", "int64*", &c), c /= 1000)
    return (DllCall("QueryPerformanceCounter", "int64*", &c), c / f)
}


class GuiMcode {
    static borderСolor := "303030"
    static mainColor   := "005343"
    static decor       := "005343"

    static ARR_FLAGS           := ["GCC (x64)", "GCC (x64) Mcode", "GCC (x86)", "GCC (x86) Mcode", "MSVC (x64_x86)"]
    static IMPORT_DLL          := "User32|Kernel32|ntdll|Gdi32|Advapi32|msvcrt|Shell32|Ole32|OleAut32|Comctl32|Shlwapi|Ws2_32|Iphlpapi|Version|Secur32|Winmm|Imm32|Uxtheme|Setupapi|Crypt32|ucrtbase"
    static DYNAMIC_LINKING     := "malloc|memset|memcpy"
    static SEARCH_SYMBOLS      := "___chkstk_ms|__main"
    static SEARCH_SYMBOLS_DIR  := "...\gcc\x86_64-w64-mingw32\10.3.0\libgcc.a"
    static SEARCH_SYMBOLS_INFO := "Important: The character search is extremely slow!`nThe search can take either a couple of seconds or a couple of minutes (depending on the number and size of files).`nTherefore, wait for the end of the algorithm."

    static STATIC_LIBRARIES    := "
    (
        // For example ["ctrl + /" comment / uncomment]:
        // D:\GCC_tdm64-gcc-9.2.0\x86_64-w64-mingw32\lib\libmingwex.a
        // D:\GCC_tdm64-gcc-9.2.0\lib\gcc\x86_64-w64-mingw32\10.3.0\libgcc.a
    )"

    static STATIC_SUBSTITUTION := "
    (
        // Substitution of symbols: [original] -> [new]
        // _Znwy -> ??2@YAPEAX_K@Z
        // _ZdlPv -> ??3@YAXPEAX@Z
    )"

    static DYNAMIC_SUBSTITUTION := "
    (
        // Substitution of symbols: [original] -> [new]
        // _Znwy -> ??2@YAPEAX_K@Z
        // _ZdlPv -> ??3@YAXPEAX@Z
    )"

    __New() {
        MCODE.DarkMode()
        this.CreateMainGUI()
        this.CreateSettingsGUI()
        ; this.CreateSetPathGUI()
        this.CreateCOFFinfoGUI()
        this.CreateSLPGUI()
        this.CreateLogGUI()
        this.CreateSearchSymbolsGUI()
        this.Events()
        this.mainG.Show("w1288 h656")
    }


    CreateMainGUI() {
        this.mainG := Gui("+Resize +MinSize760x480")
        this.mainG.SetFont("s9 cffffff", "consolas")
        this.mainG.BackColor := 0x010101
        CustomTitleBarWindow(this.mainG, GuiMcode.mainColor,,,,true)

        this.mainG.AddText("x10 y46 BackgroundTrans c12abd1", "Objdump flags:")
        this.mainG.SetFont("s11 c11b1a9")
        this.flags        := this.mainG.AddEdit("Background101010", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "FLAGS", "-m64 -O2"))
        this.sourceFile   := this.mainG.AddEdit("Background101010", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SOURCE_FILE", "Mcode[.c / .cpp] || Mcode[.o / .obj] (CHANGE)"))
        this.objdumpFlags := this.mainG.AddEdit("Background101010", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_FLAGS", "-D -C -M intel"))
        this.mainG.SetFont("s9 cffffff")

        this.browseSourceFile := this.mainG.AddButton(, "Browse Src")
        this.mainG.SetFont("s10 cffffff")
        this.setFlagsDDLBtn   := this.mainG.AddButton(, "x64 (Mcode)")
        this.setFlagsDDL      := this.mainG.AddDropDownList("Choose1 0x04000000 0x0210", GuiMcode.ARR_FLAGS)
        this.mainG.SetFont("s7", "calibri")
        this.addFlagsDDl      := this.mainG.AddButton("Center", "• • •")
        this.mainG.SetFont("s9 cffffff", "consolas")
        this.copyTable        := this.mainG.AddButton(, "Copy`ntable`n->")
        
        this.waitSectionObjdumpBtn   := this.mainG.AddButton(, "No sections")
        this.waitSectionObjdump      := this.mainG.AddDropDownList("Choose1 0x04000000 0x0210", ["No sections"])
        this.generateMcodeFromSrc    := this.mainG.AddButton(, "Generate Mcode from source")
        this.copyCode                := this.mainG.AddButton(, "Copy code from source")
        this.generateMcodeFromEditor := this.mainG.AddButton(, "Generate Mcode from editor")
        this.parseBytes              := this.mainG.AddButton(, "Parse bytes → Mcode formats")

        this.copyHex      := this.mainG.AddButton(, "Copy Hex")
        this.copyBase64   := this.mainG.AddButton(, "Copy Base64")
        this.copyCompress := this.mainG.AddButton(, "Copy Compress")

        this.setModeDDLBtn := this.mainG.AddButton("x10 y5 w135 h22", "GCC")
        this.setModeDDL    := this.mainG.AddDropDownList("x10 y5 Choose1 0x04000000 0x0210", ["GCC", "MSVC x64", "MSVC x86"])
        this.settings      := this.mainG.AddButton("x155 y5 h22", "Settings")
        this.COFFinfo      := this.mainG.AddButton("x237 y5 h22", "COFF info")
        this.showSLP       := this.mainG.AddButton("x326 y5 h22", "Static Library Viewer")
        this.copyMcodeFunc := this.mainG.AddButton("x403 y5 h22", "Copy Mcode Func")

        this.objdumpRE  := this.mainG.AddRichEdit("Consolas", 11, "0xffffff", "0x101010")
        this.cppRE      := this.mainG.AddRichEdit("Consolas", 11, "0xffffff", "0x101010")
        this.warningRE  := this.mainG.AddRichEdit("Consolas", 9,  "0x98e6e6", "0x101010")
        this.infoRE     := this.mainG.AddRichEdit("Consolas", 9,  "0x551b19", "0x101010")
        this.hexRE      := this.mainG.AddRichEdit("Consolas", 9,  "0x11b1a9", "0x101010")
        this.base64RE   := this.mainG.AddRichEdit("Consolas", 9,  "0x11b1a9", "0x101010")
        this.compressRE := this.mainG.AddRichEdit("Consolas", 9,  "0x11b1a9", "0x101010") ; 0x12abd1
        this.menuWarningRE := Menu()

        GuiReSizer.Opt(this.mainG.AddText("Background" GuiMcode.decor), "x0 y-170 wp1 h2")
        GuiReSizer.Opt(this.mainG.AddText("Background" GuiMcode.decor), "xp0.4 x132 y-168 w2 h168")
        GuiReSizer.Opt(this.mainG.AddText("Background" GuiMcode.decor), "xp0.4 x24 y160 w2 h-170")
        GuiReSizer.Opt(this.mainG.AddText("Background" GuiMcode.decor), "x0 y158 wp1 h2")
        GuiReSizer.Opt(this.mainG.AddText("Background" GuiMcode.decor), "xp0.4 x192 y111 w2 h47")
        GuiReSizer.Opt(this.mainG.AddText("Background" GuiMcode.decor), "xp0.4 x132 y111 w60 h2")
        GuiReSizer.Opt(this.mainG.AddText("Background" GuiMcode.decor), "xp0.4 x132 y31 w2 h80")
        GuiReSizer.Opt(this.copyCompress,           "xp0.4 x22 y-54  w100 h44")
        GuiReSizer.Opt(this.copyBase64,             "xp0.4 x22 y-106 w100 h44")
        GuiReSizer.Opt(this.copyHex,                "xp0.4 x22 y-158 w100 h44")
        GuiReSizer.Opt(this.infoRE,                 "xp0.4 x204 y41 w-9 h107")
        GuiReSizer.Opt(this.compressRE,             "x10 y-54  wp0.4 w4 h44")
        GuiReSizer.Opt(this.base64RE,               "x10 y-106 wp0.4 w4 h44")
        GuiReSizer.Opt(this.hexRE,                  "x10 y-158 wp0.4 w4 h44")
        GuiReSizer.Opt(this.warningRE,              "xp0.4 x144 y-158 w-9 h148")
        GuiReSizer.Opt(this.objdumpRE,              "x10 y200 wp0.4 w4  h-180")
        GuiReSizer.Opt(this.cppRE,                  "xp0.4 x36 y200 w-9 h-180")
        GuiReSizer.Opt(this.waitSectionObjdumpBtn,   "x10 y170 wp0.2 h22")
        GuiReSizer.Opt(this.waitSectionObjdump,      "x10 y170 wp0.2 h22")
        GuiReSizer.Opt(this.generateMcodeFromSrc,    "xp0.2 x20 y170 wp-0.6 w15 h22")
        GuiReSizer.Opt(this.copyCode,                "xp0.4 x36 y170 wp-0.4 h22")
        GuiReSizer.Opt(this.generateMcodeFromEditor, "xp0.6 x10 y170 wp0.2  h22")
        GuiReSizer.Opt(this.parseBytes,              "xp0.8 x19 y170 w-9   h22")
        GuiReSizer.Opt(this.sourceFile,              "x10 y82  wp0.4 w4 h24")
        GuiReSizer.Opt(this.objdumpFlags,            "x116 y41 wp-0.6 w122 h24")
        GuiReSizer.Opt(this.flags,                   "x10 y123 wp0.4 w4 h24")
        GuiReSizer.Opt(this.browseSourceFile,        "xp0.4 x22 y82 w100  h24")
        GuiReSizer.Opt(this.setFlagsDDLBtn,          "xp0.4 x22 y123 w137 h24")
        GuiReSizer.Opt(this.setFlagsDDL,             "xp0.4 x22 y123 w137 h24")
        GuiReSizer.Opt(this.addFlagsDDl,             "xp0.4 x157 y123 w24 h24")
        GuiReSizer.Opt(this.copyTable,               "xp0.4 x144 y41 w50 h60")
        GuiReSizer.Opt(this.copyMcodeFunc,           "x-268 y5 h22")
        this.setFlagsDDL.Function        := (CtrlObj, GuiObj) => PostMessage(0x0153, -1, 18, CtrlObj)
        this.waitSectionObjdump.Function := (CtrlObj, GuiObj) => PostMessage(0x0153, -1, 16, CtrlObj)

        MCODE.CustomButton(this.setModeDDLBtn,           "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766}, true)
        MCODE.CustomButton(this.COFFinfo,                "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        MCODE.CustomButton(this.showSLP,                 "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        MCODE.CustomButton(this.settings,                "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        MCODE.CustomButton(this.copyMcodeFunc,           "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        MCODE.CustomButton(this.browseSourceFile,        "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.setFlagsDDLBtn,          "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}, true)
        MCODE.CustomButton(this.addFlagsDDl,             "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.copyTable,               "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.waitSectionObjdumpBtn,   "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}, true)
        MCODE.CustomButton(this.generateMcodeFromSrc,    "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.copyCode,                "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.generateMcodeFromEditor, "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.parseBytes,              "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.copyHex,                 "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.copyBase64,              "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.copyCompress,            "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}) ; 0x32606b

        MCODE.CustomDDL(this.setFlagsDDL,             "0x141414", "0xa3bed1", "0x1f3a3a")
        MCODE.CustomDDL(this.waitSectionObjdump,      "0x141414", "0xa3bed1", "0x1f3a3a")
        MCODE.CustomDDL(this.setModeDDL,              "0x141414", "0xa3bed1", "0x1f3a3a")

        IDE(this.cppRE, RTF.CSyntax)
        IDE(this.objdumpRE, RTF.ObjdumpHighlight)

        if (IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SAVE_LAST_CODE", 0) && FileExist(Const.GLOBAL_LAST_CODE)) {
            RTF.ReplaceSel(FileRead(Const.GLOBAL_LAST_CODE), RTF.CSyntax, this.cppRE)
        } else {
            RTF.ReplaceSel(GLOBAL_C_CODE, RTF.CSyntax, this.cppRE)
        }
    }


    CreateSettingsGUI() {
        SwitchPage(GuiCtrlObj, pageName) {
            static currentPage := ""
            if (currentPage = pageName)
                return

            for _, pageControls in Pages {
                for ctrl in pageControls {
                    ctrl.Visible := false
                }
            }
            for ctrl in Pages[pageName] {
                ctrl.Visible := true
            }
            for ctrl in [this.general_settings, this.linker_settings, this.compiler_settings, this.change_MCF_paths_settings, this.customize_theme_settings, this.hotkey_settings, this.reference_settings] {
                MCODE.CustomButton(ctrl, btnColors1*)
            }
            MCODE.CustomButton(GuiCtrlObj, "0x216e5f", "0xfeffff")
            DllCall("user32\SendMessage", "Ptr", this.settingsG.Hwnd, "UInt", 0x0127, "Ptr", 0x0001 | ((0x0001 | 0x0002) << 16), "Ptr", 0)
            currentPage := pageName
        }

        GetCtrl() {
            ctrls := []
            static i := 16 ; Количество контролов которые не будет скрыты
            for hwnd, ctrl in this.settingsG {
                if (A_Index >= i) {
                    i++
                    ctrls.Push(ctrl)
                }
            }
            return ctrls
        }

        Pages := Map(), Pages.Default := []
        btnColors1 := ["0x060606", "0x12abd1",, 3, {HOT: "0x1f3a3a"}]
        btnColors2 := ["0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: "0x2a2766"}]
        btnColors3 := ["0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: "0x1f3a3a"}]
        btnColors4 := ["0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"}]

        this.settingsG := Gui("-DPIScale")
        this.settingsG.SetFont("s11", "Consolas")
        this.settingsG.BackColor := 0x060606
        CustomTitleBarWindow(this.settingsG, "005343",,,,true)
        this.settingsG.AddText("x12 y27 c12abd1 BackgroundTrans", ASCII_MCODE).SetFont("s10")
        this.settingsG.AddText("x10 y129 w231 h282 Background005343")
        this.settingsG.AddText("x241 y31 w2 h614   Background005343")
        this.settingsG.AddText("x10 y617 c12abd1", "MCF version: " Const.GLOBAL_MCF_VERSION)

        this.settingsG.SetFont("s10", "Consolas")
        this.general_settings          := this.settingsG.AddButton("x12 y131 w229 h38 Left", "  General Settings")
        this.linker_settings           := this.settingsG.AddButton("x12 y171 w229 h38 Left", "  Linker Settings")
        this.compiler_settings         := this.settingsG.AddButton("x12 y211 w229 h38 Left", "  Compiler Settings")
        this.change_MCF_paths_settings := this.settingsG.AddButton("x12 y251 w229 h38 Left", "  Change MCF paths")
        this.customize_theme_settings  := this.settingsG.AddButton("x12 y291 w229 h38 Left", "  Customize theme")
        this.hotkey_settings           := this.settingsG.AddButton("x12 y331 w229 h38 Left", "  Hotkey Settings")
        this.reference_settings        := this.settingsG.AddButton("x12 y371 w229 h38 Left", "  Reference")
        this.settingsG.SetFont("s11", "Consolas")

        this.settingsG.SetFont("s9", "Consolas")
        this.showTempDir    := this.settingsG.AddButton("x10 y5  h22", "Show temp dir")
        this.checkUpdate    := this.settingsG.AddButton("x127 y5 h22", "Check update")

        ; =================================== GENERAL SETTINGS ===================================

        this.settingsG.SetFont("s11", "Consolas")
        this.settingsG.AddText("x253 y43  c0x9AA7B0", "MSVC x64 path:")
        this.settingsG.AddText("x253 y77  c0x9AA7B0", "MSVC x86 path:")
        this.settingsG.AddText("x253 y111 c0x9AA7B0", "GCC path:")
        this.settingsG.AddText("x253 y145 c0x9AA7B0", "Clang path:")
        this.settingsG.AddText("x253 y179 c0x9AA7B0", "Zig path:")
        this.settingsG.AddText("x253 y213 c0x9AA7B0", "Objdump path:")

        this.MSVCPathX64   := this.settingsG.AddEdit("x373 y41  w747 h24 Background101010 c11b1a9", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X64", "\VC\Auxiliary\Build\vcvars64.bat"))
        this.MSVCPathX86   := this.settingsG.AddEdit("x373 y75  w747 h24 Background101010 c11b1a9", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X86", "\VC\Auxiliary\Build\vcvars32.bat"))
        this.GCCPath       := this.settingsG.AddEdit("x373 y109 w747 h24 Background101010 c11b1a9", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "GCC_PATH",      "\bin\x86_64-w64-mingw32-gcc-10.3.0.exe [change]"))
        this.ClangPath     := this.settingsG.AddEdit("x373 y143 w747 h24 Background101010 c11b1a9", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "CLANG_PATH",    "Clang support is not yet implemented."))
        this.ZigPath       := this.settingsG.AddEdit("x373 y177 w747 h24 Background101010 c11b1a9", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "ZIG_PATH",      "Zig support is not yet implemented."))
        this.objdumpPath   := this.settingsG.AddEdit("x373 y211 w747 h24 Background101010 c11b1a9", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_PATH",  "\bin\objdump.exe [change]"))
        this.settingsG.SetFont("s9", "Consolas")
        this.browseMSVCX64 := this.settingsG.AddButton("x1130 y41  w120 h24", "Browse MSVC x64")
        this.browseMSVCX86 := this.settingsG.AddButton("x1130 y75  w120 h24", "Browse MSVC x86")
        this.browseGCC     := this.settingsG.AddButton("x1130 y109 w120 h24", "Browse GCC")
        this.browseClang   := this.settingsG.AddButton("x1130 y143 w120 h24", "Browse Clang")
        this.browseZig     := this.settingsG.AddButton("x1130 y177 w120 h24", "Browse Zig")
        this.browseObjdump := this.settingsG.AddButton("x1130 y211 w120 h24", "Browse Objdump")
        this.settingsG.SetFont("s11", "Consolas")

        this.generateObjdump         := this.settingsG.AddButton("x253 y261 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "GENERATE_OBJDUMP",           "✔")), this.settingsG.AddText("x281 y261 c0x12abd1", "Generate disassembler")
        this.displayObjdump          := this.settingsG.AddButton("x253 y293 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_OBJDUMP",            "✔")), this.settingsG.AddText("x281 y293 c0x12abd1", "Display disassembler")
        this.objdumpHighlighting     := this.settingsG.AddButton("x253 y325 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_HIGHLIGHTING",       "✔")), this.settingsG.AddText("x281 y325 c0x12abd1", "Disassembler highlighting")
        this.displayHexMcode         := this.settingsG.AddButton("x253 y357 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_HEX_MCODE",          "✔")), this.settingsG.AddText("x281 y357 c0x12abd1", "Display Hex Mcode")
        this.displayBase64Mcode      := this.settingsG.AddButton("x253 y389 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_BASE64_MCODE",       "")),  this.settingsG.AddText("x281 y389 c0x12abd1", "Display Base64 Mcode")
        this.displayCompressMcode    := this.settingsG.AddButton("x253 y421 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_COMPRESS_MCODE",     "")),  this.settingsG.AddText("x281 y421 c0x12abd1", "Display Compress Mcode")
        this.displayFullOffsetTable  := this.settingsG.AddButton("x253 y453 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_FULL_OFFSET_TABLE",  "✔")), this.settingsG.AddText("x281 y453 c0x12abd1", "Display full offset table")
        this.showCommentsOffsetTable := this.settingsG.AddButton("x253 y485 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SHOW_COMMENTS_OFFSET_TABLE", "✔")), this.settingsG.AddText("x281 y485 c0x12abd1", "Show comments for the offset table")
        this.multilineOutputLength   := this.settingsG.AddEdit("x453 y517 w62 h22 Background101010 c11b1a9 Center Number", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "MULTILINE_OUTPUT_LENGTH", "176")), this.settingsG.AddText("x253 y518 c0x9AA7B0", "Multiline output length:")
        this.demangleSymbols         := this.settingsG.AddButton("x253 y549 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DEMANGLE_SYMBOLS",          "")),  this.settingsG.AddText("x281 y549 c0x12abd1", "Demangle symbol names in the offset table")
        this.demangleSignatures      := this.settingsG.AddButton("x253 y581 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DEMANGLE_SIGNATURES",       "")),  this.settingsG.AddText("x281 y581 c0x12abd1", "Demangle function signatures")
        this.checkAutoUpdate         := this.settingsG.AddButton("x253 y613 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "CHECK_AUTO_UPDATE",          "")),  this.settingsG.AddText("x281 y613 c0x12abd1", "Check for updates on startup")
        this.saveLastCode            := this.settingsG.AddButton("x631 y261 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SAVE_LAST_CODE", "✔")), this.settingsG.AddText("x659 y261 c0x12abd1", "Save last code")

        this.settingsG.AddText("x241 y249 w1100 h2 Background005343")
        this.settingsG.AddText("x619 y250 h400 w2  Background005343")
        Pages["General"] := GetCtrl()

        ; =================================== LINKER SETTINGS ===================================

        this.settingsG.AddText("x681 y31 w2 h121 Background005343")
        this.settingsG.AddText("x243 y152 w1100 h2 Background005343")

        this.settingsG.AddText("x434 y390  c0x9AA7B0", "Static Lib (.a / .lib)")
        this.settingsG.AddText("x820 y390  c0x9AA7B0", "Dynamic linking symbols")
        this.settingsG.AddText("x1100 y390 c0x9AA7B0", "Import Dll")
        this.settingsG.AddText("x428 y160 c0x9AA7B0", "Static Symbol Substitution")
        this.settingsG.AddText("x873 y160 c0x9AA7B0", "Dynamic Symbol Substitution")

        this.dynamicLinkingAuto  := this.settingsG.AddButton("x253 y41 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DYNAMIC_LINKING_AUTO", "✔")), this.settingsG.AddText("x281 y41 c0x12abd1", "Link all static symbols dynamically (if possible)")
        this.removeLastAlignment := this.settingsG.AddButton("x253 y73 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "REMOVE_LAST_ALIGNMENT", "")), this.settingsG.AddText("x281 y73 c0x12abd1", "Remove last alignment [not implemented]")
        this.entryPoint          := this.settingsG.AddEdit("x356 y105 w80 h22  Background101010 c11b1a9 Center Number", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "ENTRY_POINT", 0x0)), this.settingsG.AddText("x253 y106 c0x12abd1 BackgroundTrans", "Entry Point:            (decimal number)")
        this.ignoreSections      := this.settingsG.AddEdit("x826 y41 w424 h24  Background101010 c11b1a9", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "IGNORE_SECTION", ".xdata|.pdata|.rdata$zzz")), this.settingsG.AddText("x691 y42 c0x12abd1", "Ignore Sections:")

        this.staticLibrariesRE   := this.settingsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x253  y414 w520 h221 0x00000080")
        this.dynamicLinkingRE    := this.settingsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x783  y414 w250 h221 0x00000080")
        this.importDllsRE        := this.settingsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x1043 y414 w207 h221 0x00000080")

        this.staticSubstitution  := this.settingsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x253 y184 w493 h200 0x00000080")
        this.dynamicSubstitution := this.settingsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x756 y184 w494 h200 0x00000080")
        Pages["Linker"] := GetCtrl()


        ; =================================== COMPILER SETTINGS ===================================

        this.settingsG.AddText("x253 y41 c0xc44444", "Keep in mind that 90% of these settings are simply compiler flags. `nFurthermore, most of these settings will only be relevant for GCC, and possibly Clang; MSVC is supported indirectly.")
        this.cFileMode         := this.settingsG.AddButton("x253 y90 w18 h18",  IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "C_FILE_MODE",         "")) , this.settingsG.AddText("x281 y90 c0x12abd1", "C file mode")
        this.cppFileMode       := this.settingsG.AddButton("x253 y124 w18 h18",  IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "CPP_FILE_MODE",       "✔")), this.settingsG.AddText("x281 y124 c0x12abd1", "Cpp file mode")
        this.removeDbgSection  := this.settingsG.AddButton("x253 y158 w18 h18",  IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "REMOVE_DBG_SECTION",  "")),  this.settingsG.AddText("x281 y158 c0x12abd1", "Remove dbg section (-fno-ident)")
        this.optimizeSizeMcode := this.settingsG.AddButton("x253 y192 w18 h18",  IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "OPTIMIZE_SIZE_MCODE", "")),  this.settingsG.AddText("x281 y192 c0x12abd1", "Optimize Mcode size as much as possible (-falign-functions=1 -falign-jumps=1 -falign-loops=1 -falign-labels=1)")
        this.defineNoDebug     := this.settingsG.AddButton("x253 y226 w18 h18",  IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DEFINE_NO_DEBUG", "")),      this.settingsG.AddText("x281 y226 c0x12abd1", "Define no debug (-DNDEBUG)")
        Pages["Compiler"] := GetCtrl()

        ; =================================== CHANGE_PATHS SETTINGS ===================================

        this.settingsG.AddText("x253 y41 c0xc44444", "IMPORTANT: If you change any setting below, you must close this window and restart the program.")
        this.setPathTempDir     := this.settingsG.AddEdit("x364 y71   w886 h24 Background101010 c11b1a9", Const.GLOBAL_WORKING_DIR), this.settingsG.AddText("x253 y73  c0x12abd1", "Temp Dir:")
        this.setPathSettingsIni := this.settingsG.AddEdit("x364 y105  w886 h24 Background101010 c11b1a9", Const.GLOBAL_INI_FILE), this.settingsG.AddText("x253 y107  c0x12abd1", "Settings ini:")
        this.setPathCacheDir    := this.settingsG.AddEdit("x364 y139  w886 h24 Background101010 c11b1a9", Const.GLOBAL_WORKING_CACHE_DIR), this.settingsG.AddText("x253 y141 c0x12abd1", "Cache Dir:")
        Pages["Change_Paths"] := GetCtrl()

        ; =================================== CUSTOMIZE_THEME SETTINGS ===================================

        this.settingsG.AddText("x253 y41 c0xc44444", "There should have been theme settings here, but I'm too lazy to do that, and why would I need it?")
        Pages["Customize_Theme"] := GetCtrl()

        ; =================================== HOTKEY SETTINGS ===================================

        this.settingsG.AddText("x253 y41 c0xc44444", "Someday there will be key settings here... But that won't be anytime soon...")
        Pages["Hotkey"] := GetCtrl()

        ; =================================== REFERENCE SETTINGS ===================================
        this.settingsG.AddText("x253 y41 c0xc44444", "Perhaps there will be something like documentation or a description of the program here.")
        Pages["Reference"] := GetCtrl()


        MCODE.CustomButton(this.general_settings, btnColors1*)
        MCODE.CustomButton(this.linker_settings, btnColors1*)
        MCODE.CustomButton(this.compiler_settings, btnColors1*)
        MCODE.CustomButton(this.change_MCF_paths_settings, btnColors1*)
        MCODE.CustomButton(this.customize_theme_settings, btnColors1*)
        MCODE.CustomButton(this.hotkey_settings, btnColors1*)
        MCODE.CustomButton(this.reference_settings, btnColors1*)

        MCODE.CustomButton(this.browseMSVCX64, btnColors3*)
        MCODE.CustomButton(this.browseMSVCX86, btnColors3*)
        MCODE.CustomButton(this.browseGCC,     btnColors3*)
        MCODE.CustomButton(this.browseClang,   btnColors3*)
        MCODE.CustomButton(this.browseZig,     btnColors3*)
        MCODE.CustomButton(this.browseObjdump, btnColors3*)

        MCODE.CustomButton(this.generateObjdump, btnColors4*)
        MCODE.CustomButton(this.displayObjdump, btnColors4*)
        MCODE.CustomButton(this.objdumpHighlighting, btnColors4*)
        MCODE.CustomButton(this.displayHexMcode, btnColors4*)
        MCODE.CustomButton(this.displayBase64Mcode, btnColors4*)
        MCODE.CustomButton(this.displayCompressMcode, btnColors4*)
        MCODE.CustomButton(this.displayFullOffsetTable, btnColors4*)
        MCODE.CustomButton(this.showCommentsOffsetTable, btnColors4*)
        MCODE.CustomButton(this.demangleSymbols, btnColors4*)
        MCODE.CustomButton(this.demangleSignatures, btnColors4*)
        MCODE.CustomButton(this.checkAutoUpdate, btnColors4*)
        MCODE.CustomButton(this.saveLastCode, btnColors4*)
        MCODE.CustomButton(this.dynamicLinkingAuto, btnColors4*)
        MCODE.CustomButton(this.removeLastAlignment, btnColors4*)
        MCODE.CustomButton(this.ignoreSections, btnColors4*)
        MCODE.CustomButton(this.cFileMode, btnColors4*)
        MCODE.CustomButton(this.cppFileMode, btnColors4*)
        MCODE.CustomButton(this.removeDbgSection, btnColors4*)
        MCODE.CustomButton(this.optimizeSizeMcode, btnColors4*)
        MCODE.CustomButton(this.defineNoDebug, btnColors4*)

        MCODE.CustomButton(this.showTempDir, btnColors2*)
        MCODE.CustomButton(this.checkUpdate, btnColors2*)


        this.general_settings.OnEvent("Click",          (GuiCtrlObj, Info, Href?) => SwitchPage(GuiCtrlObj, "General"))
        this.linker_settings.OnEvent("Click",           (GuiCtrlObj, Info, Href?) => SwitchPage(GuiCtrlObj, "Linker"))
        this.compiler_settings.OnEvent("Click",         (GuiCtrlObj, Info, Href?) => SwitchPage(GuiCtrlObj, "Compiler"))
        this.change_MCF_paths_settings.OnEvent("Click", (GuiCtrlObj, Info, Href?) => SwitchPage(GuiCtrlObj, "Change_Paths"))
        this.customize_theme_settings.OnEvent("Click",  (GuiCtrlObj, Info, Href?) => SwitchPage(GuiCtrlObj, "Customize_Theme"))
        this.hotkey_settings.OnEvent("Click",           (GuiCtrlObj, Info, Href?) => SwitchPage(GuiCtrlObj, "Hotkey"))
        this.reference_settings.OnEvent("Click",        (GuiCtrlObj, Info, Href?) => SwitchPage(GuiCtrlObj, "Reference"))

        IDE(this.staticLibrariesRE,   RTF.Comments)
        IDE(this.dynamicLinkingRE,    RTF.Comments)
        IDE(this.importDllsRE,        RTF.Comments)
        IDE(this.staticSubstitution,  RTF.Comments)
        IDE(this.dynamicSubstitution, RTF.Comments)

        RTF.ReplaceSel(Join(StrSplit(IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "STATIC_LIBRARIES", GuiMcode.STATIC_LIBRARIES), "|"), "`n"), RTF.Comments, this.staticLibrariesRE)
        RTF.ReplaceSel(Join(StrSplit(IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DYNAMIC_LINKING_SELECTIVELY", GuiMcode.DYNAMIC_LINKING), "|"), "`n"), RTF.Comments, this.dynamicLinkingRE)
        RTF.ReplaceSel(Join(StrSplit(IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "IMPORT_DLLS", GuiMcode.IMPORT_DLL), "|"), "`n"), RTF.Comments, this.importDllsRE)
        RTF.ReplaceSel(FormatIniData(IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "STATIC_SUBSTITUTION", GuiMcode.STATIC_SUBSTITUTION), true), RTF.Comments, this.staticSubstitution)
        RTF.ReplaceSel(FormatIniData(IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "DYNAMIC_SUBSTITUTION", GuiMcode.DYNAMIC_SUBSTITUTION), true), RTF.Comments, this.dynamicSubstitution)
        
        SwitchPage(this.general_settings, "General")
    }


    CreateCOFFinfoGUI() {
        this.COFFG := Gui("+Resize +MinSize760x480")
        this.COFFG.SetFont("s11", "Consolas")
        this.COFFG.BackColor := 0x060606
        CustomTitleBarWindow(this.COFFG, "005343",,,,true)

        this.copyMcodeRE           := this.CreateRichEdit(this.COFFG, "Consolas", 9, "0x11b1a9", "0x101010")
        this.COFFG.SetFont("s9", "Consolas")
        this.copyMcodeHex          := this.COFFG.AddButton(, "Copy Hex this Section")
        this.hexDumpRE             := this.CreateRichEdit(this.COFFG, "Consolas", 11, "0xffffff", "0x101010")
        this.COFFinfoRE            := this.CreateRichEdit(this.COFFG, "Consolas", 11, "0xffffff", "0x101010")
        this.waitSectionHexDumpBtn := this.COFFG.AddButton(, "No sections")
        this.waitSectionHexDump    := this.COFFG.AddDropDownList("Choose1 0x04000000 0x0210", ["No sections"])
        this.displayAllCOFFInfo    := this.COFFG.AddButton("x10 y5 h22", "Display all info")

        GuiReSizer.Opt(this.copyMcodeRE,           "x10 y-54 w-180 h44")
        GuiReSizer.Opt(this.copyMcodeHex,          "x-170 y-54 w160 h44")
        GuiReSizer.Opt(this.COFFG.AddText("Background" GuiMcode.decor), "x0 y-66 wp1 h2")
        GuiReSizer.Opt(this.COFFG.AddText("Background" GuiMcode.decor), "xp0.5 y31 x70 w2 h-66")
        GuiReSizer.Opt(this.hexDumpRE,             "x10 y76 wp0.5 w50 h-76")
        GuiReSizer.Opt(this.COFFinfoRE,            "xp0.5 x82 y41 w-10 h-76")
        GuiReSizer.Opt(this.waitSectionHexDumpBtn, "x10 y41 wp0.5 w50")
        GuiReSizer.Opt(this.waitSectionHexDump,    "x10 y41 wp0.5 w50")
        this.waitSectionHexDump.Function := (CtrlObj, GuiObj) => PostMessage(0x0153, -1, 19, CtrlObj)

        MCODE.CustomButton(this.displayAllCOFFInfo,        "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        MCODE.CustomButton(this.copyMcodeHex,              "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.waitSectionHexDumpBtn,     "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}, true)
        MCODE.CustomDDL(this.waitSectionHexDump,        "0x141414", "0xa3bed1", "0x1f3a3a")

        IDE(this.hexDumpRE, RTF.HexDump)
        IDE(this.COFFinfoRE, RTF.CoffSyntax)
    }


    CreateSLPGUI() {
        this.slpG := Gui("+Resize +MinSize760x380", "Static Library Viewer")
        this.slpG.BackColor := 0x010101
        CustomTitleBarWindow(this.slpG, "005343",,,,true)

        this.slpG.SetFont("s9 cffffff", "Consolas")
        this.slpG.AddText("x10 y44 h21 c0x00ccff", "Library:")
        this.statusSL  := this.slpG.AddText("c0xa3bed1", "The static library (.a / .lib) is not loaded...")
        this.lvAR      := this.slpG.AddListView("-HScroll -Grid -Multi", ["Symbol", "Object", "Offset", "Size", "IsThin"])
        this.btnLoadSL := this.slpG.AddButton(, "Download") ; x890 y41  w100 h24
        this.btnSaveSL := this.slpG.AddButton(, "Extract")
        this.slpG.SetFont("s11")
        this.loadSL  := this.slpG.AddEdit("c11b1a9 Background101010", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "LOAD_SLP_STATIC_LIB", "(.a / .lib) File"))
        this.saveSL  := this.slpG.AddEdit("c11b1a9 Background101010")

        this.lvAR.ModifyCol(1, "380 Text Left")
        this.lvAR.ModifyCol(2, "300 Text Left")
        this.lvAR.ModifyCol(3, "100 Integer Left")
        this.lvAR.ModifyCol(4, "110 Integer Left")
        this.lvAR.ModifyCol(5, "69  Integer Left")

        GuiReSizer.Opt(this.loadSL,    "x74 y41 w-110 h24")
        GuiReSizer.Opt(this.btnLoadSL,   "x-100 y41 w-10 h24")
        GuiReSizer.Opt(this.lvAR,      "x10 y75 w-10 h-84")
        GuiReSizer.Opt(this.saveSL,    "x53 y-74 w-110 h24")
        GuiReSizer.Opt(this.btnSaveSL, "x-100 y-74 w-10 h24")
        this.slpG.SetFont("s9")
        GuiReSizer.Opt(this.slpG.AddText("c0x00ccff", "Save:"), "x10 y-70 h21")
        GuiReSizer.Opt(this.slpG.AddText("Background005343"), "x0 y-40 wp1 h2")
        GuiReSizer.Opt(this.statusSL, "x10 y-28 wp1")
        this.slpG.SetFont("s11")

        MCODE.CustomButton(this.btnLoadSL,   "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.btnSaveSL, "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.lvAR.SetTheme("0x101010", "0xa3bed1", {SELECTED: "", HOT: "0x1f3a3a"}, "0x101010", "0x00ccff", "0x005343", {SELECTED: "0x1c2f31", HOT: "0x066e6e"}) ; 0x077ed3
    }


    CreateLogGUI() {
        this.logG := Gui("+Resize +MinSize400x240", "Log MCF")
        this.logG.BackColor := 0x010101
        CustomTitleBarWindow(this.logG, "005343",,,,true)
        this.logLinkerRE := this.CreateRichEdit(this.logG, "Consolas", 11, "0xffffff", "0x101010",, "The log will be displayed only after Mcode generation...")
    }


    CreateSearchSymbolsGUI() {
        this.searchSymbolsG := Gui("", "Search for symbols")
        this.searchSymbolsG.SetFont("s11 cffffff", "consolas")
        CustomTitleBarWindow(this.searchSymbolsG, GuiMcode.mainColor,,,,true)
        this.searchSymbolsG.BackColor := 0x010101

        this.searchSymbolsG.AddText("x45 y41 c0x9AA7B0", "=== Symbols for searching ===")
        this.searchSymbolsG.AddText("x460 y41 c0x9AA7B0", "=== Paths to files / directories ===")
        this.searchSymbolsG.SetFont("s10")

        this.edit_symbols_RE         := this.searchSymbolsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x10  y72 w300 h100 0x00000080")
        this.edit_dir_file_RE        := this.searchSymbolsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x320 y72 w600 h100 0x00000080")
        this.btn_select_file         := this.searchSymbolsG.AddButton("x930 y72  w120 h24", "Browse file")
        this.btn_select_dir          := this.searchSymbolsG.AddButton("x930 y110 w120 h24", "Browse dir")
        this.btn_clear_paths         := this.searchSymbolsG.AddButton("x930 y148 w120 h24", "Clear the paths")
        this.lv_viewing_symbols      := this.searchSymbolsG.AddListView("x10 y192 w801 h236 -HScroll -Grid -Multi", ["Symbol", "Path", "Object", "Offset", "Size", "IsThin"])
        this.edit_output_paths_RE    := this.searchSymbolsG.AddRichEdit("Consolas", 10, "0x11b1a9", "0x101010", "x10 y450 w1040 h100 0x00000080")
        
        this.searchSymbolsG.SetFont("s11")
        this.btnBox_find_all         := this.searchSymbolsG.AddButton("x821 y192 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_FIND_ALL",         ""))
        this.btnBox_recursive_search := this.searchSymbolsG.AddButton("x821 y224 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_RECURSIVE_SEARCH", ""))
        this.btnBox_search_static    := this.searchSymbolsG.AddButton("x821 y256 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_SEARCH_STATIC",   "✔"))
        this.btnBox_search_dynamic   := this.searchSymbolsG.AddButton("x821 y288 w18 h18", IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_SEARCH_DYNAMIC",   ""))
        this.searchSymbolsG.SetFont("s10")
        this.btn_search_symbols      := this.searchSymbolsG.AddButton("x821 y398 w229 h30", "Search symbols")
        this.searchSymbolsG.AddText("x851 y193 c0x12abd1", "Search all matches")
        this.searchSymbolsG.AddText("x851 y225 c0x12abd1", "Recursive search")
        this.searchSymbolsG.AddText("x851 y257 c0x12abd1", "Static symbol search (ar)")
        this.searchSymbolsG.AddText("x851 y289 c0x12abd1", "Dynamic symbol search (dll)")


        this.lv_viewing_symbols.ModifyCol(1, "100 Text Left")
        this.lv_viewing_symbols.ModifyCol(2, "370 Text Left")
        this.lv_viewing_symbols.ModifyCol(3, "100 Text Left")
        this.lv_viewing_symbols.ModifyCol(4, "70 Integer Left")
        this.lv_viewing_symbols.ModifyCol(5, "70 Integer Left")
        this.lv_viewing_symbols.ModifyCol(6, "70 Integer Left")

        this.searchSymbolsG.AddText("x0 y182 w1060 h2 Background005343")
        this.searchSymbolsG.AddText("x0 y438 w1060 h2 Background005343")

        this.menu_search_symbols := Menu()

        MCODE.CustomButton(this.btn_select_file,    "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.btn_select_dir,     "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.btn_clear_paths,    "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        MCODE.CustomButton(this.btn_search_symbols, "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})

        MCODE.CustomButton(this.btnBox_find_all,         "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        MCODE.CustomButton(this.btnBox_recursive_search, "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        MCODE.CustomButton(this.btnBox_search_static,    "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        MCODE.CustomButton(this.btnBox_search_dynamic,   "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})

        this.lv_viewing_symbols.SetTheme("0x101010", "0xa3bed1", {SELECTED: "", HOT: "0x1f3a3a"}, "0x101010", "0x00ccff", "0x005343", {SELECTED: "0x1c2f31", HOT: "0x066e6e"})

        RTF.ReplaceSel(Join(StrSplit(IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SEARCH_SYMBOLS",     GuiMcode.SEARCH_SYMBOLS), "|"), "`n"), RTF.Comments, this.edit_symbols_RE)
        RTF.ReplaceSel(Join(StrSplit(IniRead(Const.GLOBAL_INI_FILE, "SETTINGS", "SEARCH_SYMBOLS_DIR", GuiMcode.SEARCH_SYMBOLS_DIR), "|"), "`n"), RTF.Comments, this.edit_dir_file_RE)
        RTF.ReplaceSel(GuiMcode.SEARCH_SYMBOLS_INFO, RTF.ErrorLog, this.edit_output_paths_RE)

        IDE(this.edit_symbols_RE,      RTF.Comments)
        IDE(this.edit_dir_file_RE,     RTF.Comments)
        IDE(this.edit_output_paths_RE, RTF.Comments)
    }


    CreateRichEdit(Gui, FontName := "Consolas", FontSize := 11, TextColor := "0x5f2e2e", BgColor := "0x161616", Opt := "", Text := "") {
        static ES_MULTILINE       := 0x0004
        static ES_WANTRETURN      := 0x1000
        static ES_AUTOVSCROLL     := 0x0040
        static WS_VSCROLL         := 0x200000
        static WS_HSCROLL         := 0x100000
        static ES_DISABLENOSCROLL := 0x00002000

        static EM_SETCHARFORMAT := 0x0444
        static SCF_ALL          := 0x0004
        static CFM_COLOR        := 0x40000000
        static CFM_FACE         := 0x20000000
        static CFM_SIZE         := 0x80000000
        static CFE_AUTOCOLOR    := 0x40000000

        RE := Gui.AddCustom("ClassRichEdit50w " Opt " " ES_MULTILINE | ES_WANTRETURN | ES_AUTOVSCROLL | WS_VSCROLL | ES_DISABLENOSCROLL, Text)

        dwMask := 0
        cf := Buffer(116, 0), NumPut("UInt", 116, cf, 0) ; CHARFORMAT2

        if (TextColor != "") {
            dwMask |= CFM_COLOR
            NumPut("UInt", RGBtoBGR(TextColor), cf, 20)  ; crTextColor
        } if (FontSize > 0) {
            dwMask |= CFM_SIZE
            NumPut("Int", FontSize * 20, cf, 12)  ; yHeight
        } if (FontName != "") {
            dwMask |= CFM_FACE
            StrPut(FontName, cf.Ptr + 26, 32, "UTF-16")  ; szFaceName
        }
        
        NumPut("UInt", dwMask, cf, 4) ; dwMask
        SendMessage(EM_SETCHARFORMAT, SCF_ALL, cf.Ptr,, RE)
        SendMessage(0x443, 0, RGBtoBGR(BgColor), RE)
        DllCall("uxtheme\SetWindowTheme", "Ptr", RE.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
        DisableRichEditBeep(RE)

        RGBtoBGR(rgbClr) => ((rgbClr & 0xFF) << 16) | (((rgbClr >> 8) & 0xFF) << 8) | ((rgbClr >> 16) & 0xFF)
        DisableRichEditBeep(RE) {
            static EM_GETOLEINTERFACE := 0x43C, TXTBIT_ALLOWBEEP := 0x800, TXTBIT_MULTILINE := 0x2, IID_ITextServices := "{8D33F740-CF58-11CE-A89D-00AA006CADC5}"
            DllCall("SendMessage", "Ptr", RE.Hwnd, "UInt", EM_GETOLEINTERFACE, "Ptr", 0, "Ptr*", &IRichEditOle := 0)
            TxtSrv := ComObjQuery(IRichEditOle, IID_ITextServices)
            ComCall(19, TxtSrv, "int", TXTBIT_ALLOWBEEP | TXTBIT_MULTILINE, "int", TXTBIT_MULTILINE, "UInt")
        }
        return RE
    }


    Events() {
        ;########################################################## main ########################################################
        this.mainG.OnEvent("Size", GuiReSizer)
        this.mainG.OnEvent("Close", (*) {
            IniWrite(this.objdumpFlags.Text,   Const.GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_FLAGS")
            IniWrite(this.sourceFile.Text,     Const.GLOBAL_INI_FILE, "SETTINGS", "SOURCE_FILE")
            IniWrite(this.flags.Text,          Const.GLOBAL_INI_FILE, "SETTINGS", "FLAGS")

            if (this.saveLastCode.Text) {
                try FileDelete(Const.GLOBAL_LAST_CODE)
                FileAppend(this.cppRE.Text, Const.GLOBAL_LAST_CODE)
            }

            ExitApp()
        })

        this.settings.OnEvent("Click",      (*) => this.settingsG.Show("w1260 h614"))
        this.copyMcodeFunc.OnEvent("Click", (*) => A_Clipboard := GLOBAL_MCODE_FUNC_FINAL)
        this.showSLP.OnEvent("Click",       (*) => this.slpG.Show("w1000 h450"))
        this.COFFinfo.OnEvent("Click",      (*) => this.COFFG.Show("w1200 h640"))

        this.browseSourceFile.OnEvent("Click", (*) => this.sourceFile.Text := (sel := FileSelect(,,, "C/C++/o/obj Files (*.c; *.cpp; *.o; *.obj)")) ? sel : this.sourceFile.Text)
        this.addFlagsDDl.OnEvent("Click",      (*) => MsgBox("not implemented..."))
        this.copyTable.OnEvent("Click",        (*) => A_Clipboard := this.infoRE.Text)

        this.setFlagsDDL.OnEvent("Change", (*) {
            this.setFlagsDDLBtn.Text := this.setFlagsDDL.Text
            switch this.setFlagsDDL.Text {
                case "GCC (x64)"        : this.flags.Text := "-m64 -O2"
                case "GCC (x64) Mcode"  : this.flags.Text := "-m64 -O2 -fPIC -fno-stack-protector -fno-plt -fno-asynchronous-unwind-tables"
                case "GCC (x86)"        : this.flags.Text := "-m32 -O2"
                case "GCC (x86) Mcode"  : this.flags.Text := "-m32 -O2 -fPIC -fno-stack-protector -fno-plt -fno-asynchronous-unwind-tables"
                case "MSVC (x64_x86)"   : this.flags.Text := "/O2 /GS- /EHs-c-"
            }
        })

        this.setModeDDL.OnEvent("Change",           (*) => this.setModeDDLBtn.Text := this.setModeDDL.Text)
        this.waitSectionObjdumpBtn.OnEvent("Click", (*) => SendMessage(0x014F, 1, 0, this.waitSectionObjdump))
        this.setFlagsDDLBtn.OnEvent("Click",        (*) => SendMessage(0x014F, 1, 0, this.setFlagsDDL))
        this.setModeDDLBtn.OnEvent("Click",         (*) => SendMessage(0x014F, 1, 0, this.setModeDDL))
        this.waitSectionObjdump.OnEvent("Change",   (*) {
            this.waitSectionObjdumpBtn.Text := this.waitSectionObjdump.Text
            this.objdumpRE.Text := ""
            if (this.HasOwnProp("objdump")) {
                RTF.ReplaceSel(this.objdump[this.waitSectionObjdump.Text], RTF.ObjdumpHighlight, this.objdumpRE, this.objdumpHighlighting.Text != "" ? true : false)
            } else {
                RTF.ReplaceSel("Objdump...`nSections [disassembler] will be displayed after you generate Mcode.", RTF.Log, this.objdumpRE)
            }
        })

        this.generateMcodeFromEditor.OnEvent("Click", (*) => this.GenerateMcode(this.cppRE.Text))
        this.generateMcodeFromSrc.OnEvent("Click",    (*) {
            if !(FileExist(this.sourceFile.Text))
                return this.Error_log("Invalid SRC path: " this.sourceFile.Text)
            this.GenerateMcode(this.sourceFile.Text)
        })
        this.parseBytes.OnEvent("Click", (*) {
            er := Binary.ExtractHexBytes(this.cppRE.Text)
            if (er is Error) {
                this.hexRE.Text      := er.Message
                this.base64RE.Text   := er.Message
                this.compressRE.Text := er.Message
            } else {
                this.hexRE.Text      := er
                this.base64RE.Text   := Binary.HexToBase64(er)
                this.compressRE.Text := SubStr(Binary.HexToCompressedBase64(er), 9)
            }
        })

        this.copyCode.OnEvent("Click", (*) {
            SplitPath(this.sourceFile.Text,,, &ext)
            if (ext == "c" || ext == "cpp" && FileExist(this.sourceFile.Text)) {
                this.cppRE.Text := ""
                RTF.ReplaceSel(FileRead(this.sourceFile.Text), RTF.CSyntax, this.cppRE)
            }
        })

        this.copyHex.OnEvent("Click",      (*) => A_Clipboard := CopyFormatMcode(this.HasOwnProp("mcode") && this.mcode.hex))
        this.copyBase64.OnEvent("Click",   (*) => A_Clipboard := CopyFormatMcode(this.HasOwnProp("mcode") && this.mcode.base64))
        this.copyCompress.OnEvent("Click", (*) => A_Clipboard := CopyFormatMcode(this.HasOwnProp("mcode") && this.mcode.compress))

        this.warningRE.OnMessage(0x7B, (wParam, lParam, msg, hwnd) { ; WM_CONTEXTMENU = 0x7B
            this.menuWarningRE.Show()
            return 0
        })

        CopyFormatMcode(str) {
            if (this.HasOwnProp("cf")) {
                mcode := this.cf.is64 ? 'x64 := "`n(`n' : 'x86 := "`n(`n'
                mcode .= RegExReplace(str, "(.{" Integer(this.multilineOutputLength.Text) "})", "$1`n") . '`n)"`n'
                mcode .= "ptr := GetMcodePtr(" (this.cf.is64 ? 'x64' : ', x86') ")"
                return mcode
            }
        }


        this.menuWarningRE.Add("Show Linking log", (*) {
            this.logG.Show("w700 h260")
            this.logLinkerRE.Text := "Please wait... Loading log."

            if (FileExist(Const.GLOBAL_MCF_LINKER_LOG)) {
                MCFLog := FileRead(Const.GLOBAL_MCF_LINKER_LOG)
            } else MCFLog := ""

            if (MCFLog != "") {
                this.logLinkerRE.Text := ""
                RTF.ReplaceSel(MCFLog, RTF.VsCodeAhk, this.logLinkerRE)
            } else {
                this.logLinkerRE.Text := "The log will be displayed only after Mcode generation..."
            }
        })

        this.menuWarningRE.Add("Search for unresolved symbols", (*) => this.searchSymbolsG.Show("w1060 h529"))

        ;########################################################## settings ####################################################

        this.settingsG.OnEvent("Close", (*) {
            IniWrite(this.MSVCPathX64.Text, Const.GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X64")
            IniWrite(this.MSVCPathX86.Text, Const.GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X86")
            IniWrite(this.ClangPath.Text,   Const.GLOBAL_INI_FILE, "SETTINGS", "CLANG_PATH")
            IniWrite(this.ZigPath.Text,     Const.GLOBAL_INI_FILE, "SETTINGS", "ZIG_PATH")
            IniWrite(this.GCCPath.Text,     Const.GLOBAL_INI_FILE, "SETTINGS", "GCC_PATH")
            IniWrite(this.objdumpPath.Text, Const.GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_PATH")

            IniWrite(this.generateObjdump.Text         != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "GENERATE_OBJDUMP")
            IniWrite(this.displayObjdump.Text          != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_OBJDUMP")
            IniWrite(this.objdumpHighlighting.Text     != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_HIGHLIGHTING")
            IniWrite(this.displayHexMcode.Text         != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_HEX_MCODE")
            IniWrite(this.displayBase64Mcode.Text      != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_BASE64_MCODE")
            IniWrite(this.displayCompressMcode.Text    != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_COMPRESS_MCODE")
            IniWrite(this.displayFullOffsetTable.Text  != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_FULL_OFFSET_TABLE")
            IniWrite(this.showCommentsOffsetTable.Text != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "SHOW_COMMENTS_OFFSET_TABLE")
            IniWrite(this.checkAutoUpdate.Text         != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "CHECK_AUTO_UPDATE")
            IniWrite(this.multilineOutputLength.Text, Const.GLOBAL_INI_FILE, "SETTINGS", "MULTILINE_OUTPUT_LENGTH")

            IniWrite(this.cFileMode.Text           != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "C_FILE_MODE")
            IniWrite(this.cppFileMode.Text         != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "CPP_FILE_MODE")
            IniWrite(this.removeDbgSection.Text    != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "REMOVE_DBG_SECTION")
            IniWrite(this.optimizeSizeMcode.Text   != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "OPTIMIZE_SIZE_MCODE")
            IniWrite(this.defineNoDebug.Text       != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DEFINE_NO_DEBUG")
            IniWrite(this.demangleSymbols.Text     != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DEMANGLE_SYMBOLS")
            IniWrite(this.demangleSignatures.Text  != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DEMANGLE_SIGNATURES")
            IniWrite(this.saveLastCode.Text        != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "SAVE_LAST_CODE")
            IniWrite(this.dynamicLinkingAuto.Text  != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "DYNAMIC_LINKING_AUTO")
            IniWrite(this.removeLastAlignment.Text != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "REMOVE_LAST_ALIGNMENT")
            IniWrite(this.entryPoint.Text    , Const.GLOBAL_INI_FILE, "SETTINGS", "ENTRY_POINT")
            IniWrite(this.ignoreSections.Text, Const.GLOBAL_INI_FILE, "SETTINGS", "IGNORE_SECTION")
            IniWrite(Join(StrSplit(RegExReplace(this.importDllsRE.Text, "\R+", "`n"), "`n"), "|"), Const.GLOBAL_INI_FILE, "SETTINGS", "IMPORT_DLLS")
            IniWrite(Join(StrSplit(RegExReplace(this.dynamicLinkingRE.Text, "\R+", "`n"), "`n"), "|"), Const.GLOBAL_INI_FILE, "SETTINGS", "DYNAMIC_LINKING_SELECTIVELY")
            IniWrite(Join(StrSplit(RegExReplace(this.staticLibrariesRE.Text, "\R+", "`n"), "`n"), "|"), Const.GLOBAL_INI_FILE, "SETTINGS", "STATIC_LIBRARIES")
            IniWrite(FormatIniData(this.staticSubstitution.Text), Const.GLOBAL_INI_FILE, "SETTINGS", "STATIC_SUBSTITUTION")
            IniWrite(FormatIniData(this.dynamicSubstitution.Text), Const.GLOBAL_INI_FILE, "SETTINGS", "DYNAMIC_SUBSTITUTION")

            RegWrite(Const.GLOBAL_WORKING_DIR       := this.setPathTempDir.Text,     "REG_SZ", "HKCU\Software\MCF", "TEMP_DIR")
            RegWrite(Const.GLOBAL_INI_FILE          := this.setPathSettingsIni.Text, "REG_SZ", "HKCU\Software\MCF", "TEMP_SETTINGS_INI")
            RegWrite(Const.GLOBAL_WORKING_CACHE_DIR := this.setPathCacheDir.Text,    "REG_SZ", "HKCU\Software\MCF", "TEMP_CACHE")
        })

        this.showTempDir.OnEvent("Click",    (*) => Run(Const.GLOBAL_WORKING_DIR))
        this.checkUpdate.OnEvent("Click",    (*) => new_thread_check_update.AsyncCall("CheckForUpdates", "Vedette1", "MCF.ahk", Const.GLOBAL_MCF_VERSION, true))

        this.browseMSVCX64.OnEvent("Click", (*) => this.MSVCPathX64.Text    := (sel := FileSelect(,,, "Bat File (*.bat)")) ? sel : this.MSVCPathX64.Text)
        this.browseMSVCX86.OnEvent("Click", (*) => this.MSVCPathX86.Text    := (sel := FileSelect(,,, "Bat File (*.bat)")) ? sel : this.MSVCPathX86.Text)
        this.browseGCC.OnEvent("Click",     (*) => this.GCCPath.Text        := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.GCCPath.Text)
        this.browseClang.OnEvent("Click",   (*) => this.ClangPath.Text      := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.ClangPath.Text)
        this.browseZig.OnEvent("Click",     (*) => this.ZigPath.Text        := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.ZigPath.Text)
        this.browseObjdump.OnEvent("Click", (*) => this.objdumpPath.Text    := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.objdumpPath.Text)

        this.generateObjdump.OnEvent("Click",         (*) => this.generateObjdump.Text         := this.generateObjdump.Text         ? "" : "✔")
        this.displayObjdump.OnEvent("Click",          (*) => this.displayObjdump.Text          := this.displayObjdump.Text          ? "" : "✔")
        this.objdumpHighlighting.OnEvent("Click",     (*) => this.objdumpHighlighting.Text     := this.objdumpHighlighting.Text     ? "" : "✔")
        this.displayHexMcode.OnEvent("Click",         (*) => this.displayHexMcode.Text         := this.displayHexMcode.Text         ? "" : "✔")
        this.displayBase64Mcode.OnEvent("Click",      (*) => this.displayBase64Mcode.Text      := this.displayBase64Mcode.Text      ? "" : "✔")
        this.displayCompressMcode.OnEvent("Click",    (*) => this.displayCompressMcode.Text    := this.displayCompressMcode.Text    ? "" : "✔")
        this.displayFullOffsetTable.OnEvent("Click",  (*) => this.displayFullOffsetTable.Text  := this.displayFullOffsetTable.Text  ? "" : "✔")
        this.showCommentsOffsetTable.OnEvent("Click", (*) => this.showCommentsOffsetTable.Text := this.showCommentsOffsetTable.Text ? "" : "✔")
        this.demangleSymbols.OnEvent("Click",         (*) => this.demangleSymbols.Text         := this.demangleSymbols.Text         ? "" : "✔")
        this.demangleSignatures.OnEvent("Click",      (*) => this.demangleSignatures.Text      := this.demangleSignatures.Text      ? "" : "✔")
        this.saveLastCode.OnEvent("Click",            (*) => this.saveLastCode.Text            := this.saveLastCode.Text            ? "" : "✔")
        this.checkAutoUpdate.OnEvent("Click",         (*) => this.checkAutoUpdate.Text         := this.checkAutoUpdate.Text         ? "" : "✔")
        this.cFileMode.OnEvent("Click",               (*) => (this.cFileMode.Text              := "✔", this.cppFileMode.Text       := ""))
        this.cppFileMode.OnEvent("Click",             (*) => (this.cppFileMode.Text            := "✔", this.cFileMode.Text         := ""))
        this.removeDbgSection.OnEvent("Click",        (*) => this.removeDbgSection.Text        := this.removeDbgSection.Text        ? "" : "✔")
        this.optimizeSizeMcode.OnEvent("Click",       (*) => this.optimizeSizeMcode.Text       := this.optimizeSizeMcode.Text       ? "" : "✔")
        this.defineNoDebug.OnEvent("Click",           (*) => this.defineNoDebug.Text           := this.defineNoDebug.Text           ? "" : "✔")
        this.dynamicLinkingAuto.OnEvent("Click",      (*) => this.dynamicLinkingAuto.Text      := this.dynamicLinkingAuto.Text      ? "" : "✔")
        this.removeLastAlignment.OnEvent("Click",     (*) => this.removeLastAlignment.Text     := this.removeLastAlignment.Text     ? "" : "✔")

        ;####################################################### COFF info ######################################################

        this.COFFG.OnEvent("Size", GuiReSizer)
        this.waitSectionHexDumpBtn.OnEvent("Click", (*) => SendMessage(0x014F, 1, 0, this.waitSectionHexDump))
        this.displayAllCOFFInfo.OnEvent("Click",    (*) {
            this.hexDumpRE.Text   := ""
            this.COFFinfoRE.Text  := ""
            this.copyMcodeRE.Text := ""
            if !(FileExist(Const.GLOBAL_TEMP_OBJ)) {
                return RTF.ReplaceSel("The COFF file was not found. Generate the Mcode, and click on this button again, or drag the obj file into this window.", RTF.HexDump, this.hexDumpRE)
            }

            cf := COFF(Const.GLOBAL_TEMP_OBJ)
            if (cf is Error) {
                return RTF.ReplaceSel("Unexpected error. Most likely, the specified file is not (.o/.obj) or the file is corrupted.", RTF.HexDump, this.hexDumpRE)
            }
            this.hexDump := cf.ObjCopy(true, 20, &prop)
            this.waitSectionHexDump.Delete()
            this.waitSectionHexDump.Add(prop)

            text := ""
            for p in prop {
                if (p ~= "text") {
                    text := p
                    break
                }
            }

            if (text) {
                RTF.ReplaceSel(this.hexDump[text].dump, RTF.HexDump, this.hexDumpRE)
                this.copyMcodeRE.Text := this.hexDump[text].hex
                this.waitSectionHexDumpBtn.Text := text
            } else {
                this.waitSectionHexDumpBtn.Text := prop.Length " sections:"
            }

            RTF.ReplaceSel(cf.AllInfo(), RTF.CoffSyntax, this.COFFinfoRE,, false)
        })

        this.waitSectionHexDump.OnEvent("Change", (*) {
            this.waitSectionHexDumpBtn.Text := this.waitSectionHexDump.Text
            this.hexDumpRE.Text := ""
            if (this.HasOwnProp("hexDump")) {
                this.hexDumpRE.Text  := ""
                RTF.ReplaceSel(this.hexDump[this.waitSectionHexDumpBtn.Text].dump, RTF.HexDump, this.hexDumpRE)
                if (StrLen(this.hexDump[this.waitSectionHexDumpBtn.Text].hex) <= 500000) {
                    this.copyMcodeRE.Text := this.hexDump[this.waitSectionHexDumpBtn.Text].hex
                } else {
                    this.copyMcodeRE.Text := "The Hex Mcode will not be displayed visually, but you can still copy it."
                }
            } else {
                RTF.ReplaceSel("Sections [Hex Dump] will be displayed after you generate Mcode.", RTF.HexDump, this.hexDumpRE)
            }
        })

        this.copyMcodeHex.OnEvent("Click", (*) => (this.HasOwnProp("hexDump") && A_Clipboard := this.hexDump[this.waitSectionHexDumpBtn.Text].hex))

        ;####################################################### SLP ######################################################

        this.slpG.OnEvent("Close", (*) {
            IniWrite(this.loadSL.Text, Const.GLOBAL_INI_FILE, "SETTINGS", "LOAD_SLP_STATIC_LIB")
        })

        this.slpG.OnEvent("Size", GuiReSizer)
        this.btnLoadSL.OnEvent("Click", (*) {
            try {
                this.SLP := StaticLibraryParser(Trim(this.loadSL.Text))
                this.lvAR.Delete()
                for symName, info in this.SLP.ResolvedSymbols {
                    this.lvAR.Add(, symName, info.ObjFile, info.DataOffset, info.Size, info.IsThin)
                }
                this.statusSL.Text := "Uploaded: " this.SLP.Members.Length " objects, " this.SLP.ResolvedSymbols.Count " symbols, " this.SLP.ThinMembers.Length " thin"
            } catch as er {
                this.statusSL.Text := "ERROR: " er.Message
            }
        })

        this.lvAR.OnEvent("DoubleClick", (*) {
            if (row := this.lvAR.GetNext(0, "F")) {
                this.saveSL.Text := Const.GLOBAL_WORKING_DIR "\" this.lvAR.GetText(row, 2)
            }
        })

        this.btnSaveSL.OnEvent("Click", (*) {
            try {
                if (this.HasProp("SLP")) {
                    objName := this.lvAR.GetText(this.lvAR.GetNext(0, "F"), 2)
                    outPath := this.SLP.ExtractMemberToFile(objName, Trim(this.saveSL.Text))
                    this.statusSL.Text := "Saved: " outPath
                } else {
                    this.statusSL.Text := "First, download the library"
                }
            } catch as er {
                this.statusSL.Text := "ERROR: " er.Message
            }
        })

        ;########################################################## Full Log ########################################################

        this.logG.OnEvent("Size", (GuiObj, MinMax, Width, Height) {
            this.logLinkerRE.Move(10, 41, Width - 20, Height - 51)
        })

        ;########################################################## Search Symbols ########################################################

        this.searchSymbolsG.OnEvent("Close", (*) {
            IniWrite(Join(StrSplit(RegExReplace(this.edit_symbols_RE.Text,  "\R+", "`n"), "`n"), "|"), Const.GLOBAL_INI_FILE, "SETTINGS", "SEARCH_SYMBOLS")
            IniWrite(Join(StrSplit(RegExReplace(this.edit_dir_file_RE.Text, "\R+", "`n"), "`n"), "|"), Const.GLOBAL_INI_FILE, "SETTINGS", "SEARCH_SYMBOLS_DIR")

            IniWrite(this.btnBox_find_all.Text         != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_FIND_ALL")
            IniWrite(this.btnBox_recursive_search.Text != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_RECURSIVE_SEARCH")
            IniWrite(this.btnBox_search_static.Text    != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_SEARCH_STATIC")
            IniWrite(this.btnBox_search_dynamic.Text   != "" ? "✔" : "", Const.GLOBAL_INI_FILE, "SETTINGS", "SYMBOLS_SEARCH_DYNAMIC")
        })

        SelectPath(type) {
            if (type == "File") {
                selected := FileSelect("M3",,, "Archives (*.a; *.lib)")
                if (selected) {
                    for file in selected
                        this.edit_dir_file_RE.Value .= (this.edit_dir_file_RE.Text ? "`n" : "") file
                }
            } else {
                selected := DirSelect(, 3, "Select a directory to search")
                if (selected)
                    this.edit_dir_file_RE.Value .= (this.edit_dir_file_RE.Text ? "`n" : "") selected
            }
        }

        OpenFileLocation() {
            rowNumber := this.lv_viewing_symbols.GetNext(0, "F")
            if (!rowNumber)
                return
            path := this.lv_viewing_symbols.GetText(rowNumber, 2)
            if FileExist(path)
                Run("explorer.exe /select,`"" path "`"")
        }

        this.btn_select_file.OnEvent("Click", (*) => SelectPath("File"))
        this.btn_select_dir.OnEvent("Click",  (*) => SelectPath("Folder"))
        this.btn_clear_paths.OnEvent("Click", (*) => this.edit_dir_file_RE.Text := "")

        this.btnBox_find_all.OnEvent("Click",         (*) => this.btnBox_find_all.Text         := this.btnBox_find_all.Text         ? "" : "✔")
        this.btnBox_recursive_search.OnEvent("Click", (*) => this.btnBox_recursive_search.Text := this.btnBox_recursive_search.Text ? "" : "✔")
        ; this.btnBox_search_static.OnEvent("Click",    (*) => this.btnBox_search_static.Text    := this.btnBox_search_static.Text    ? "" : "✔")
        ; this.btnBox_search_dynamic.OnEvent("Click",   (*) => this.btnBox_search_dynamic.Text   := this.btnBox_search_dynamic.Text   ? "" : "✔")
        this.btnBox_search_dynamic.OnEvent("Click", (*) => MsgBox("Not implemented..."))

        this.btn_search_symbols.OnEvent("Click", (*) {
            try {
                this.edit_output_paths_RE.Text := "Please wait. The symbol search process may take a few seconds or even minutes..."
                this.lv_viewing_symbols.Delete()
                symbols_path  := ""
                symbolsToFind := GUIDataToArray(this.edit_symbols_RE.Text)
                pathsToSearch := GUIDataToArray(this.edit_dir_file_RE.Text)
                findAll       := this.btnBox_find_all.Text         != "" ? true : false
                recurse       := this.btnBox_recursive_search.Text != "" ? true : false
                symbols       := FindSymbolsInArchives(symbolsToFind, pathsToSearch, findAll, recurse)

                for item in symbols {
                    this.lv_viewing_symbols.Add("", item.Symbol, item.ArchivePath, item.ObjFile, item.DataOffset, item.Size, item.IsThin)
                    symbols_path .= item.ArchivePath " // " item.Symbol "`n"
                }

                this.edit_output_paths_RE.Text := ""
                if (symbols_path) {
                    RTF.ReplaceSel("Search complete! " symbols.Length " characters found...`n" symbols_path, RTF.Comments, this.edit_output_paths_RE)
                } else {
                    RTF.ReplaceSel("Search completed! Unfortunately, no characters were found...", RTF.ErrorLog, this.edit_output_paths_RE)
                }

            } catch as er {
                RTF.ReplaceSel("Symbol search error:`n" er.Message "`n" er.Line "`n" er.File, RTF.Comments, this.edit_output_paths_RE)
            }
        })

        this.lv_viewing_symbols.OnEvent("ContextMenu", (GuiCtrlObj, Item, IsRightClick, X, Y) {
            if (!Item)
                return
            this.menu_search_symbols.Show()
        })

        this.menu_search_symbols.Add("Copy the archive path", (*) => A_Clipboard := this.lv_viewing_symbols.GetText(this.lv_viewing_symbols.GetNext(0, "F"), 2))
        this.menu_search_symbols.Add("Copy the symbol name",  (*) => A_Clipboard := this.lv_viewing_symbols.GetText(this.lv_viewing_symbols.GetNext(0, "F"), 1))
        this.menu_search_symbols.Add("Copy object file name", (*) => A_Clipboard := this.lv_viewing_symbols.GetText(this.lv_viewing_symbols.GetNext(0, "F"), 3))
        this.menu_search_symbols.Add()
        this.menu_search_symbols.Add("Open the file folder",  (*) => OpenFileLocation())
    }


    GenerateMcode(src) {
        try {
            this.objdump         := unset
            prop                 := []
            this.SetTextColorRE(0x11b1a9, this.hexRE)
            this.SetTextColorRE(0x11b1a9, this.base64RE)
            this.SetTextColorRE(0x11b1a9, this.compressRE)
            this.infoRE.Text     := ""
            this.warningRE.Text  := ""
            this.objdumpRE.Text  := ""
            this.hexRE.Text      := ""
            this.base64RE.Text   := ""
            this.compressRE.Text := ""
            this.waitSectionObjdump.Delete()
            this.waitSectionObjdump.Add(["No sections"])
            this.waitSectionObjdumpBtn.Text := "No sections"
            RTF.ReplaceSel("Please wait, Mcode assembly may take several tens of seconds...`n", RTF.Log, this.warningRE,,, true)
            totalTime             := QPC()
            srcIsCOFF             := (src ~= "\.(o|obj)$" && FileExist(src)) ? 1 : 0
            set                   := Compiler.Settings()
            set.src               := src
            set.srcFileMode       := this.cFileMode.Text != "" ? "c" : "cpp"
            set.flagsObjdump      := this.objdumpFlags.Text
            set.flagsObj          := this.flags.Text
            set.optimizeSizeMcode := this.optimizeSizeMcode.Text != "" ? true : false
            set.removeDbgSection  := this.removeDbgSection.Text  != "" ? true : false
            set.defineNoDebug     := this.defineNoDebug.Text     != "" ? true : false
            set.GCCPath           := this.GCCPath.Text
            set.MSVCPath          := this.setModeDDL.Text == "MSVC x64" ? this.MSVCPathX64.Text : this.setModeDDL.Text == "MSVC x86" ? this.MSVCPathX86.Text : "unknown path (MSVC)"
            set.Use               := this.setModeDDL.Text == "GCC" ? "GCC" : "MSVC"
            set.disassemblerPath  := this.objdumpPath.Text
            compil                := Compiler(set)

            importDll             := GUIDataToArray(this.importDllsRE.Text)
            dynamicLinking        := this.dynamicLinkingAuto.Text != "" ? true : (_ := GUIDataToArray(this.dynamicLinkingRE.Text), _.Length ? _ : false)
            staticLinking         := GUIDataToArray(this.staticLibrariesRE.Text)
            ignoreSec             := StrSplit(RTrim(this.ignoreSections.Text, "`n`r"), "|")
            fullOffsetTable       := this.displayFullOffsetTable.Text != "" ? true : false
            try ePoint            := Integer(this.entryPoint.Text)
            staticSubstitution    := ParseEditToMap(this.staticSubstitution.Text)
            dynamicSubstitution   := ParseEditToMap(this.dynamicSubstitution.Text)
            demangleLvl           := (this.demangleSymbols.Text ? 1 : 0) + (this.demangleSignatures ? 2 : 0)
        } catch as er {
            MsgBox("This error should not happen... If you see it, please report it.`n" er.Message "`n" er.Line " -> " er.File "`n" er.Stack "`n" er.What, "ERROR")
            return
        }

        ; Если src это COFF (.o|.obj), то линковщик соберет Mcode без зависимостей от компилятора. COFF копируеться - задел на будущее...
        if (srcIsCOFF) {
            try FileCopy(src, Const.GLOBAL_WORKING_DIR "\temp.o", true)
            Objdump(src)
            Linker(src)
        } else { ; Если src это код, то сперва идет компиляция, а потом линковка...
            if (this.setModeDDL.Text == "GCC") {
                if (set.GCCPath != "" && !FileExist(set.GCCPath)) ; Проверка валидности GCC патча* (компилятора)
                    return this.Error_log("Invalid GCC path: " set.GCCPath "`n`nSpecify the absolute path to GCC [\bin\x86_64-w64-mingw32-gcc-10.3.0.exe], or do not specify a path at all (leave the input field empty); in which case the path from the environment variables will be used (PATH).")

                assemblingTime := QPC()
                er := compil.ObjGCC()
                if (er is Error)
                    return this.Error_log(er.Message)

                RTF.ReplaceSel("Compilation is completed in " QPC() - assemblingTime " milliseconds...`n", RTF.Log, this.warningRE,,, true)
                Objdump(Const.GLOBAL_TEMP_OBJ)
                Linker(Const.GLOBAL_TEMP_OBJ)
            } else {
                if (set.MSVCPath != "" && !FileExist(set.MSVCPath)) ; Проверка валидности MSVC патча* (компилятора)
                    return this.Error_log("Invalid MSVC path: " set.MSVCPath "`n`nSpecify the absolute path to MSVC [\VC\Auxiliary\Build\vcvars64.bat].")

                assemblingTime := QPC()
                er := compil.ObjGCC()
                if (er is Error)
                    return this.Error_log(er.Message)

                RTF.ReplaceSel("Compilation is completed in " QPC() - assemblingTime " milliseconds...`n", RTF.Log, this.warningRE,,, true)
                Objdump(Const.GLOBAL_TEMP_OBJ)
                Linker(Const.GLOBAL_TEMP_OBJ)
            }
        }


        ; Objdump не обязателен для работы кода. Это просто дополнение (дизассемблер) для удобства понимания того, как именно компилятор собирает код.
        ; В дальнейшем нужно доделать DumpBin (MSVC), а возможно лучше будет написать свой собственный дизассемблер на AHK, но это мутороное занятие...
        Objdump(path) {
            if (this.generateObjdump.Text) {
                objdumpTime := QPC()
                dump := compil.ObjdumpGCC(path)
            }

            if (this.generateObjdump.Text && this.displayObjdump.Text) {
                if (dump is Error) {
                    RTF.ReplaceSel("Invalid Objdump path: " this.objdumpPath.Text "`n`nSpecify the absolute path to Objdump [\bin\objdump.exe], or do not specify a path at all (leave the input field empty); in which case the path from the environment variables will be used (PATH).`n`n" er.Message, RTF.ErrorLog, this.objdumpRE)
                        this.waitSectionObjdump.Delete()
                        this.waitSectionObjdump.Add(["See the error below..."])
                } else {
                    this.objdump := Binary.ParseObjdumpToMap(FileRead(Const.GLOBAL_TEMP_ASM), &prop)
                    this.waitSectionObjdump.Delete()
                    this.waitSectionObjdump.Add(prop)
                }
                RTF.ReplaceSel("Disassembler is completed in " QPC() - objdumpTime " milliseconds...`n", RTF.Log, this.warningRE,,, true)

                text := "" ; Все компиляторы генерируют секцию [.text | .text$mn | (разные имена)] - в ней лежит основной (исполняемый) код. Поэтому она отображается в приоритете.
                for p in prop {
                    if (p ~= "text") {
                        text := p
                        break
                    }
                }
                if (text) {
                    this.objdumpRE.Text := ""
                    RTF.ReplaceSel(this.objdump[text], RTF.ObjdumpHighlight, this.objdumpRE, this.objdumpHighlighting.Text != "" ? true : false)
                    this.waitSectionObjdumpBtn.Text := text
                } else {
                    this.waitSectionObjdumpBtn.Text := prop.Length " sections:"
                }
            }
        }

        Linker(path) {
            try {
                linkerTime := QPC()
                if (staticLinking.Length) {
                    newStaticLinking := []
                    for sl in staticLinking {
                        newStaticLinking.Push(StaticLibraryParser(sl))
                    }
                } else newStaticLinking := staticLinking

                this.cf := COFF(path, importDll, ignoreSec, fullOffsetTable, ePoint ?? 0, dynamicLinking, newStaticLinking, dynamicSubstitution, staticSubstitution, demangleLvl)
                this.mcode := this.cf.Linker()

                ; Визуальная подсветка самой короткой строки MCode.
                minLen := Min(StrLen(this.mcode.hex), StrLen(this.mcode.base64), StrLen(this.mcode.compress))
                for key, re in Map("hex", this.hexRE, "base64", this.base64RE, "compress", this.compressRE) {
                    if (StrLen(this.mcode.%key%) = minLen) {
                        this.SetTextColorRE("0x12abd1", re)
                    }
                }

                if (this.displayHexMcode.Text && StrLen(this.mcode.hex) <= 500000) {
                    this.hexRE.Text := this.mcode.hex
                } else if !(this.displayHexMcode.Text) {
                    this.hexRE.Text := "The Hex Mcode will not be displayed visually (you can change this in the settings), but you can still copy it."
                } else this.hexRE.Text := "The Hex Mcode won't be displayed visually because it exceeds 500,000 characters. However, you can still copy it."

                if (this.displayBase64Mcode.Text && StrLen(this.mcode.base64) <= 500000) {
                    this.base64RE.Text := this.mcode.base64
                } else if !(this.displayBase64Mcode.Text) {
                    this.base64RE.Text := "The Base64 Mcode will not be displayed visually (you can change this in the settings), but you can still copy it."
                } else this.base64RE.Text := "The Base64 Mcode won't be displayed visually because it exceeds 500,000 characters. However, you can still copy it."
                
                if (this.displayCompressMcode.Text && StrLen(this.mcode.compress) <= 500000) {
                    this.compressRE.Text := this.mcode.compress
                } else if !(this.displayCompressMcode.Text) {
                    this.compressRE.Text := "The Compress Mcode will not be displayed visually (you can change this in the settings), but you can still copy it."
                } else this.compressRE.Text := "The Compress Mcode won't be displayed visually because it exceeds 500,000 characters. However, you can still copy it."

                RTF.ReplaceSel(this.mcode.table, RTF.VsCodeAhk, this.infoRE)
                RTF.ReplaceSel("Linker is completed in " QPC() - linkerTime " milliseconds...`n", RTF.Log, this.warningRE,,, true)
                RTF.ReplaceSel("Mcode was successfully built in " QPC() - totalTime " milliseconds!`n`n", RTF.Log, this.warningRE,,, true)
                if (this.mcode.dbg.short) { ; Отладочная информация
                    RTF.ReplaceSel(this.mcode.dbg.short, RTF.ErrorLog, this.warningRE,,, true)
                } else {
                    RTF.ReplaceSel("No errors occurred during linking!", RTF.VsCodeAhk, this.warningRE,,, true)
                }
                if (this.mcode.dbg.ALL) {
                    this.logLinkerRE.Text := ""
                    try FileDelete(Const.GLOBAL_MCF_LINKER_LOG)
                    FileAppend(this.mcode.dbg.ALL, Const.GLOBAL_MCF_LINKER_LOG, "")
                    ; RTF.ReplaceSel(this.mcode.dbg.ALL, RTF.VsCodeAhk, this.logLinkerRE)
                }
            } catch as er {
                this.Error_log("ERORR Linker:`n" er.Message "`n" er.Line " " er.File "`nFor more information about the error, see the log.")
                try FileDelete(Const.GLOBAL_MCF_LINKER_LOG)
                FileAppend(this.cf.dbgLogInfo, Const.GLOBAL_MCF_LINKER_LOG, "")
            }
        }
    }


    SetTextColorRE(color := 0x11b1a9, RE) {
        cf := Buffer(116, 0), NumPut("UInt", 116, cf, 0) ; CHARFORMAT2
        NumPut("UInt", RGBtoBGR(color), cf, 20)  ; crTextColor
        NumPut("UInt", 0x40000000, cf, 4) ; CFM_COLOR | dwMask
        SendMessage(0x0444, 0x0004, cf.Ptr,, RE.Hwnd) ; EM_SETCHARFORMAT | SCF_ALL
        RGBtoBGR(rgbClr) => ((rgbClr & 0xFF) << 16) | (((rgbClr >> 8) & 0xFF) << 8) | ((rgbClr >> 16) & 0xFF)
    }


    Error_log(message) {
        this.warningRE.Text  := ""
        this.objdumpRE.Text  := ""
        this.infoRE.Text     := ""
        this.hexRE.Text      := ""
        this.base64RE.Text   := ""
        this.compressRE.Text := ""
        RTF.ReplaceSel(message, RTF.ErrorLog, this.warningRE)
    }
}
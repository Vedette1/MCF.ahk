#Requires AutoHotkey v2.0
#Include MCODE.ahk

class MyCtrl extends Gui {
    static __New() {
        super.Prototype.AddRichEdit := this.CreateRichEdit.Bind(this)
        this.CustomEdit()
    }

    static CreateRichEdit(Gui, FontName := "Consolas", FontSize := 11, TextColor := "0x5f2e2e", BgColor := "0x161616", Opt := "", Text := "") {
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
        MCODE.CustomBorder(RE)
        return RE
    }


    static CustomEdit() {
        static origAddEdit := Gui.Prototype.AddEdit
        Gui.Prototype.DefineProp("AddEdit", {Call: (this, Options := "", Text := "") {
            e := origAddEdit(this, Options, Text)
            MCODE.CustomBorder(e)
            return e
        }})
    }
}
#Requires AutoHotkey v2.0
#Include ../MCF.ahk

class MCODE {
    static __New() {
        x64 := "
        (
        $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
        ERvzJYtQCBTpOaAAkAQA|User32:GetWindowDC:535:4|User32:GetWindowRect:552:4|Gdi32:CreateSolidBrush:578:4|User32:FrameRect:646:4|Gdi32:DeleteObject:661:4|User32:ReleaseDC:673:4|Ker
        nel32:LoadLibraryA:769:4|Kernel32:GetProcAddress:781:4|User32:MessageBoxA:872:4|User32:GetWindowLongPtrA:906:4|User32:SetWindowLongPtrA:915:4|User32:SetWindowPos:1133:4|Gdi32:S
        etBkMode:1267:4|Gdi32:SetDCBrushColor:1287:4|Gdi32:GetStockObject:1294:4|Gdi32:SelectObject:1309:4|User32:FillRect:1351:4|Gdi32:CreatePen:1476:4|Gdi32:Rectangle:1551:4|Gdi32:De
        leteObject:1573:4|User32:GetWindowLongW:1607:4|User32:GetWindowTextW:1658:4|User32:DrawTextW:1700:4|Gdi32:SetTextColor:1796:4|User32:GetKeyState:1883:4|Gdi32:SetTextColor:2012:
        4|User32:DrawTextW:2058:4|Gdi32:CreateFontW:2212:4|Gdi32:DeleteObject:2306:4|Gdi32:SetDCBrushColor:2425:4|Gdi32:GetStockObject:2436:4|Gdi32:SelectObject:2451:4|User32:FillRect:
        2466:4|User32:SendMessageW:2516:4|Gdi32:SetBkMode:2530:4|Gdi32:SetTextColor:2546:4|User32:DrawTextW:2580:4|Comctl32:RemoveWindowSubclass:497:4|Comctl32:DefSubclassProc:521:4|ms
        vcrt:free:718:4|msvcrt:malloc:970:4|Comctl32:GetWindowSubclass:1054:4|Comctl32:SetWindowSubclass:1092:4|msvcrt:free:1153:4|Comctl32:DefSubclassProc:427:4
        )"

        x86 := "
        (
        $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|User32:GetWindowDC:650:4|User32:GetWindowRect:676:4|Gdi32:CreateSolidBrush:719:4|User32:FrameRe
        ct:800:4|Gdi32:DeleteObject:821:4|User32:ReleaseDC:841:4|Kernel32:LoadLibraryA:911:4|Kernel32:GetProcAddress:924:4|User32:MessageBoxA:1025:4|User32:GetWindowLongA:1049:4|User32
        :SetWindowLongA:1076:4|User32:SetWindowPos:1345:4|Gdi32:SetBkMode:1488:4|Gdi32:SetDCBrushColor:1504:4|Gdi32:GetStockObject:1510:4|Gdi32:SelectObject:1528:4|User32:FillRect:1590
        :4|Gdi32:CreatePen:1737:4|Gdi32:Rectangle:1825:4|Gdi32:DeleteObject:1857:4|User32:GetWindowLongW:1897:4|User32:GetWindowTextW:1963:4|User32:DrawTextW:2072:4|Gdi32:SetTextColor:
        2126:4|User32:GetKeyState:2233:4|Gdi32:SetTextColor:2374:4|User32:DrawTextW:2424:4|Gdi32:CreateFontW:2607:4|Gdi32:DeleteObject:2732:4|Gdi32:SetDCBrushColor:2867:4|Gdi32:GetStoc
        kObject:2883:4|Gdi32:SelectObject:2901:4|User32:FillRect:2930:4|User32:SendMessageW:2989:4|Gdi32:SetBkMode:3009:4|Gdi32:SetTextColor:3035:4|User32:DrawTextW:3080:4|Comctl32:Def
        SubclassProc:483:4|Comctl32:RemoveWindowSubclass:596:4|Comctl32:DefSubclassProc:632:4|msvcrt:free:872:4|msvcrt:malloc:1155:4|Comctl32:GetWindowSubclass:1242:4|Comctl32:SetWindo
        wSubclass:1285:4|msvcrt:free:1364:4|VA:4:149|VA:4:176|VA:4:208|VA:4:228|VA:4:276|VA:4:299|VA:4:340|VA:4:363|VA:4:580|VA:4:905|VA:4:1004|VA:4:1012|VA:4:1234|VA:4:1277|VA:4:1689|
        VA:4:1707|VA:4:2194|VA:4:2278|VA:4:2330|VA:4:2498|VA:4:2699
        )"

        ptr := GetMcodePtr(x64, x86)
        offset := Map()
        offset["_Z16CustomBorderProcP6HWND__jyxyy"]            := ptr + (A_PtrSize == 8 ? 0x150 : 0x1A0) ; 4
        offset["_Z8DarkModev"]                                 := ptr + (A_PtrSize == 8 ? 0x2F0 : 0x380) ; 5
        offset["_Z12CustomBorderP6HWND__ii"]                   := ptr + (A_PtrSize == 8 ? 0x370 : 0x410) ; 6
        offset["_Z16CustomButtonProcP6HWND__xP12ButtonConfig"] := ptr + (A_PtrSize == 8 ? 0x490 : 0x560) ; 7
        offset["_Z14CustomDDLProcAP6HWND__jyxP9DDLConfig"]     := ptr + (A_PtrSize == 8 ? 0x910 : 0xAC0) ; 9
        this.o := offset
    }


    static DarkMode() {
        DllCall(this.o["_Z8DarkModev"], "cdecl") ; DarkMode(void)
    }


    static CustomBorder(ctrl, hexColor := 0x303030, width := 2) {
        DllCall(this.o["_Z12CustomBorderP6HWND__ii"], "Ptr", ctrl is Integer ? ctrl : ctrl.hwnd, "Int", width, "Int", hexColor, "cdecl") ; CustomBorder(HWND__*, int, int)
    }


    static CustomButton(btn, backgroundColor := 0x303030, textColor?, borderColor?, borderWidth?, hover := {}, ddlMode := false) {
        static NM_CUSTOMDRAW := -12
        static m := Map()

        if m.Has(btn.hwnd) {
            cfg := m[btn.hwnd]
            btn.Redraw()
        } else {
            cfg := Buffer(32, 0)
            m[btn.hwnd] := cfg

            SetWindowTheme(btn.hwnd, "DarkMode_Explorer")
            btn.OnNotify(NM_CUSTOMDRAW, (gCtrl, lParam) => DllCall(this.o["_Z16CustomButtonProcP6HWND__xP12ButtonConfig"], "Ptr", gCtrl.hwnd, "Ptr", lParam, "Ptr", cfg.Ptr, "cdecl"))
        }

        NumPut(
        "Int", this.RGB(backgroundColor),
        "Int", this.RGB(textColor      ?? -1),
        "Int", this.RGB(borderColor    ?? -1),
        "Int", borderWidth             ?? -1,
        "Int", this.RGB(hover.DISABLED ?? -1),
        "Int", this.RGB(hover.SELECTED ?? -1),
        "Int", this.RGB(hover.HOT      ?? -1),
        "Int", ddlMode, cfg)
    }


    static CustomDDL(DDL, backgroundСolor := 0x005000, textColor := 0xFFFFFF, highlightColor := 0x0078D7) {
        static WM_DRAWITEM := 0x002B
        static m := Map()

        if (!m.Has(DDL.hwnd)) {
            cfg := Buffer(12, 0)
            NumPut(
            "Int", this.RGB(backgroundСolor),
            "Int", this.RGB(textColor),
            "Int", this.RGB(highlightColor), cfg)

            SetWindowTheme(DDL.hwnd, "DarkMode_CFD")
            OnMessage(WM_DRAWITEM, (wParam, lParam, msg, hwnd) => DllCall(this.o["_Z14CustomDDLProcAP6HWND__jyxP9DDLConfig"], "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr", cfg.Ptr, "cdecl"))
        }
        if (IsSet(cfg))
            m[DDL.hwnd] := cfg
    }


    static RGB(clr) {
        if (clr <= -1)
            return -1
        return ((clr & 0xFF) << 16) | (((clr >> 8) & 0xFF) << 8) | ((clr >> 16) & 0xFF)
    }
}
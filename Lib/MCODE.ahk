#Requires AutoHotkey v2.0
#Include ../MCF.ahk

class MCODE {
    static __New() {
        x64 := "
        (
        $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|User32:GetWindowDC:2135
        :4|User32:GetWindowRect:2152:4|Gdi32:CreateSolidBrush:2178:4|User32:FrameRect:2246:4|Gdi32:DeleteObject:2261:4|User32:ReleaseDC:2273:4|User32:IsWindow:2392:4|User32:SendMessage
        W:2514:4|User32:InvalidateRect:2767:4|User32:UpdateWindow:2785:4|User32:KillTimer:2812:4|User32:KillTimer:2841:4|User32:InvalidateRect:3069:4|User32:BeginPaint:3110:4|User32:Ge
        tClientRect:3125:4|User32:EndPaint:3183:4|User32:InvalidateRect:3226:4|User32:InvalidateRect:3281:4|User32:TrackMouseEvent:3410:4|User32:InvalidateRect:3424:4|Gdi32:CreateCompa
        tibleDC:3450:4|Gdi32:CreateCompatibleBitmap:3469:4|Gdi32:SelectObject:3487:4|User32:IsWindowEnabled:3522:4|User32:SendMessageW:3588:4|Gdi32:SetDCBrushColor:3683:4|Gdi32:GetStoc
        kObject:3708:4|User32:FillRect:3728:4|Gdi32:CreatePen:3884:4|Gdi32:Rectangle:3949:4|Gdi32:DeleteObject:3972:4|User32:GetWindowTextW:4016:4|Gdi32:SetBkMode:4155:4|Gdi32:SetTextC
        olor:4293:4|User32:DrawTextW:4318:4|Gdi32:BitBlt:4510:4|Gdi32:DeleteObject:4531:4|Gdi32:DeleteDC:4540:4|User32:SendMessageW:4629:4|User32:SendMessageW:4705:4|User32:SendMessage
        W:4725:4|User32:IsWindowEnabled:4776:4|User32:SendMessageW:4819:4|Kernel32:LoadLibraryA:4913:4|Kernel32:GetProcAddress:4925:4|User32:MessageBoxA:5016:4|User32:GetWindowLongPtrA
        :5050:4|User32:SetWindowLongPtrA:5059:4|User32:SetWindowPos:5277:4|Gdi32:SetBkMode:5411:4|Gdi32:SetDCBrushColor:5431:4|Gdi32:GetStockObject:5438:4|Gdi32:SelectObject:5453:4|Use
        r32:FillRect:5495:4|Gdi32:CreatePen:5620:4|Gdi32:Rectangle:5695:4|Gdi32:DeleteObject:5717:4|User32:GetWindowLongW:5751:4|User32:GetWindowTextW:5802:4|User32:DrawTextW:5844:4|Gd
        i32:SetTextColor:5940:4|User32:GetKeyState:6027:4|Gdi32:SetTextColor:6156:4|User32:DrawTextW:6202:4|Gdi32:CreateFontW:6356:4|Gdi32:DeleteObject:6450:4|User32:SendMessageW:6503:
        4|Kernel32:GetTickCount:6542:4|User32:SetTimer:6586:4|Gdi32:SetDCBrushColor:6713:4|Gdi32:GetStockObject:6724:4|Gdi32:SelectObject:6739:4|User32:FillRect:6754:4|User32:SendMessa
        geW:6804:4|Gdi32:SetBkMode:6818:4|Gdi32:SetTextColor:6834:4|User32:DrawTextW:6868:4|Comctl32:RemoveWindowSubclass:2097:4|Comctl32:DefSubclassProc:2121:4|msvcrt:free:2318:4|Comc
        tl32:RemoveWindowSubclass:2967:4|msvcrt:malloc:5114:4|Comctl32:GetWindowSubclass:5198:4|Comctl32:SetWindowSubclass:5236:4|msvcrt:free:5297:4|Comctl32:DefSubclassProc:2027:4|Com
        ctl32:DefSubclassProc:3019:4
        )"

        x86 := "
        (
        $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
        BP8txQKJ8EJCh+ESxBLwN0AI6eMAJQKQBAA=|User32:GetWindowDC:1946:4|User32:GetWindowRect:1972:4|Gdi32:CreateSolidBrush:2015:4|User32:FrameRect:2096:4|Gdi32:DeleteObject:2117:4|User3
        2:ReleaseDC:2137:4|User32:IsWindow:2237:4|User32:SendMessageW:2339:4|User32:InvalidateRect:2541:4|User32:UpdateWindow:2553:4|User32:KillTimer:2601:4|User32:KillTimer:2629:4|Use
        r32:BeginPaint:2837:4|User32:GetClientRect:2859:4|User32:EndPaint:2922:4|User32:InvalidateRect:2994:4|User32:TrackMouseEvent:3142:4|Gdi32:CreateCompatibleDC:3169:4|Gdi32:Create
        CompatibleBitmap:3203:4|Gdi32:SelectObject:3219:4|User32:IsWindowEnabled:3259:4|User32:SendMessageW:3327:4|Gdi32:SetDCBrushColor:3410:4|Gdi32:GetStockObject:3432:4|User32:FillR
        ect:3461:4|Gdi32:CreatePen:3667:4|Gdi32:Rectangle:3763:4|Gdi32:DeleteObject:3791:4|User32:GetWindowTextW:3838:4|Gdi32:SetBkMode:3986:4|Gdi32:SetTextColor:4152:4|User32:DrawText
        W:4185:4|Gdi32:BitBlt:4435:4|Gdi32:DeleteObject:4467:4|Gdi32:DeleteDC:4479:4|User32:SendMessageW:4589:4|User32:SendMessageW:4672:4|User32:SendMessageW:4721:4|User32:IsWindowEna
        bled:4781:4|User32:SendMessageW:4829:4|User32:SendMessageW:4843:4|Kernel32:LoadLibraryA:4879:4|Kernel32:GetProcAddress:4892:4|User32:MessageBoxA:4993:4|User32:GetWindowLongA:50
        17:4|User32:SetWindowLongA:5044:4|User32:SetWindowPos:5313:4|Gdi32:SetBkMode:5456:4|Gdi32:SetDCBrushColor:5472:4|Gdi32:GetStockObject:5478:4|Gdi32:SelectObject:5496:4|User32:Fi
        llRect:5558:4|Gdi32:CreatePen:5705:4|Gdi32:Rectangle:5793:4|Gdi32:DeleteObject:5825:4|User32:GetWindowLongW:5865:4|User32:GetWindowTextW:5931:4|User32:DrawTextW:6040:4|Gdi32:Se
        tTextColor:6094:4|User32:GetKeyState:6201:4|Gdi32:SetTextColor:6342:4|User32:DrawTextW:6392:4|Gdi32:CreateFontW:6575:4|Gdi32:DeleteObject:6700:4|User32:SendMessageW:6771:4|Kern
        el32:GetTickCount:6804:4|User32:SetTimer:6847:4|Gdi32:SetDCBrushColor:6979:4|Gdi32:GetStockObject:6995:4|Gdi32:SelectObject:7013:4|User32:FillRect:7042:4|User32:SendMessageW:71
        01:4|Gdi32:SetBkMode:7121:4|Gdi32:SetTextColor:7147:4|User32:DrawTextW:7192:4|Comctl32:DefSubclassProc:1779:4|Comctl32:RemoveWindowSubclass:1892:4|Comctl32:DefSubclassProc:1928
        :4|msvcrt:free:2168:4|Comctl32:RemoveWindowSubclass:2748:4|Comctl32:DefSubclassProc:2790:4|msvcrt:malloc:5123:4|Comctl32:GetWindowSubclass:5210:4|Comctl32:SetWindowSubclass:525
        3:4|msvcrt:free:5332:4|VA:4:1253|VA:4:1280|VA:4:1312|VA:4:1332|VA:4:1380|VA:4:1403|VA:4:1444|VA:4:1467|VA:4:1606|VA:4:1876|VA:4:2202|VA:4:2215|VA:4:2247|VA:4:2275|VA:4:2397|VA:
        4:2403|VA:4:2473|VA:4:2499|VA:4:2736|VA:4:3290|VA:4:3341|VA:4:3384|VA:4:3533|VA:4:3539|VA:4:4022|VA:4:4088|VA:4:4560|VA:4:4608|VA:4:4691|VA:4:4873|VA:4:4972|VA:4:4980|VA:4:5202
        |VA:4:5245|VA:4:5657|VA:4:5675|VA:4:6162|VA:4:6246|VA:4:6298|VA:4:6466|VA:4:6667|VA:4:6785|VA:4:6792|VA:4:6822
        )"

        ptr := GetMcodePtr(x64, x86)
        offset := Map()
        offset["_Z16CustomBorderProcP6HWND__jyxyy"]            := ptr + (A_PtrSize == 8 ? 0x790  : 0x6B0)  ; CustomBorderProc(HWND__*, unsigned int, unsigned long long, long long, unsigned long long, unsigned long long)
        offset["_Z18ToggleSubclassProcP6HWND__jyxyy"]          := ptr + (A_PtrSize == 8 ? 0xB20  : 0xA60)  ; ToggleSubclassProc(HWND__*, unsigned int, unsigned long long, long long, unsigned long long, unsigned long long)
        offset["_Z8DarkModev"]                                 := ptr + (A_PtrSize == 8 ? 0x1320 : 0x1300) ; DarkMode()
        offset["_Z12CustomBorderP6HWND__ii"]                   := ptr + (A_PtrSize == 8 ? 0x13A0 : 0x1390) ; CustomBorder(HWND__*, int, int)
        offset["_Z16CustomButtonProcP6HWND__xP12ButtonConfig"] := ptr + (A_PtrSize == 8 ? 0x14C0 : 0x14E0) ; CustomButtonProc(HWND__*, long long, ButtonConfig*)
        offset["_Z12Toggle_ClickP6HWND__"]                     := ptr + (A_PtrSize == 8 ? 0x1940 : 0x1A40) ; Toggle_Click(HWND__*)
        offset["_Z14CustomDDLProcAP6HWND__jyxP9DDLConfig"]     := ptr + (A_PtrSize == 8 ? 0x19D0 : 0x1AD0) ; CustomDDLProcA(HWND__*, unsigned int, unsigned long long, long long, DDLConfig*)
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


    static CustomCheckBox(btn, backgroundColor := 0x101010, borderColor := 0x303030, squareColor := 0x500000, activeTextColor := 0xFFFFFF, inactiveTextColor := 0x979797, hover := {}) {
        static NM_CUSTOMDRAW := -12
        static m := Map()

        if m.Has(btn.hwnd) {
            cfg := m[btn.hwnd]
            btn.Redraw()
        } else {
            cfg := Buffer(32, 0)
            m[btn.hwnd] := cfg

            btn.Opt("0x1000")
            SetWindowTheme(btn.hwnd, "", "") ; Супер важно что бы винда не вставляла встроенные анимации UxTheme
            ; SetWindowSubclass(btn.hwnd, this.o["_Z18ToggleSubclassProcP6HWND__jyxyy"], btn.hwnd, 0)
            SetWindowSubclass(btn.hwnd, this.o["_Z18ToggleSubclassProcP6HWND__jyxyy"], btn.hwnd, cfg.Ptr)
            ; btn.OnNotify(NM_CUSTOMDRAW, (gCtrl, lParam) => DllCall(this.o["_Z12CheckBoxProcP6HWND__xP14CheckBoxConfig"], "Ptr", gCtrl.hwnd, "Ptr", lParam, "Ptr", cfg.Ptr, "cdecl"))
        }

        NumPut(
        "Int", this.RGB(backgroundColor),
        "Int", this.RGB(borderColor),
        "Int", this.RGB(squareColor),
        "Int", this.RGB(activeTextColor),
        "Int", this.RGB(inactiveTextColor),
        "Int", this.RGB(hover.DISABLED ?? -1),
        "Int", this.RGB(hover.SELECTED ?? -1),
        "Int", this.RGB(hover.HOT      ?? -1), cfg)
    }


    static CustomCheckBoxToggle(btn) {
        DllCall(MCODE.o["_Z12Toggle_ClickP6HWND__"], "Ptr", btn is Integer ? btn : btn.Hwnd)
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
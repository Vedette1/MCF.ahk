#Requires AutoHotkey v2.0
#SingleInstance Force

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include const.ahk
#Include IDE.ahk
#Include сompilerWrapper.ahk
#Include MCF.ahk



Join(arr, sep) => (arr.Length) ? ((s := '', i := 0, [(_ => (s .= arr[++i] . sep, i < arr.Length))*], Trim(s, sep))) : ""
QPC() {
    static c := 0, f := (DllCall("QueryPerformanceFrequency", "int64*", &c), c /= 1000)
    return (DllCall("QueryPerformanceCounter", "int64*", &c), c / f)
}


class Custom_Ctrl {
    static WM_CTLCOLORBTN := 0x0135
    static NM_CUSTOMDRAW  := -12
    static CDIS_DISABLED  := 0x0004
    static CDIS_HOT       := 0x0040
    static CDIS_SELECTED  := 0x0001
    static CDIS_DEFAULT   := 0x0020
    static first          := false

    static clrHwnd     := Map()
    static WM_DRAWITEM := 0x002B
    static INIT        := false

    __New(gui?) {
        OnMessage(Custom_Ctrl.WM_CTLCOLORBTN, (wParam, lParam, *) => 0)
        if (IsSet(gui))
            DllCall("user32\SendMessage", "Ptr", gui.Hwnd, "UInt", 0x0127, "Ptr", 0x0001 | ((0x0001 | 0x0002) << 16), "Ptr", 0)
    }

    ; 0x0210
    ClrDDL(DDL, bgColor := 0x005000, textColor := 0xFFFFFF, highlightColor := 0x0078D7) {
        if (!Custom_Ctrl.clrHwnd.Has(DDL.hwnd)) {
            this.SetWindowTheme(DDL.hwnd, "DarkMode_CFD")
        }
        if (!Custom_Ctrl.INIT) {
            OnMessage(Custom_Ctrl.WM_DRAWITEM, this.__DrawDDL.Bind(this))
            Custom_Ctrl.INIT := true
        }
        Custom_Ctrl.clrHwnd[DDL.hwnd] := {bgColor: bgColor, textColor: textColor, highlightColor: highlightColor}
    }


    ClrBtn(BTN, bgColor?, textColor?, borderColor?, borderWidth := 4, hoverEffect := {DISABLED: "", SELECTED: "", HOT: ""}, ddlMode := false) {
        if (!Custom_Ctrl.clrHwnd.Has(BTN.hwnd)) {
            this.SetWindowTheme(BTN.hwnd, "DarkMode_Explorer")
            BTN.OnNotify(Custom_Ctrl.NM_CUSTOMDRAW, (gCtrl, lParam) => this.__DrawBTN(gCtrl, lParam))
        }
        Custom_Ctrl.clrHwnd[BTN.hwnd] := {bg:  bgColor     ?? "0x544d4d",
                                          tx:  textColor   ?? "",
                                          bc:  borderColor ?? "",
                                          bw:  borderWidth,
                                          he:  hoverEffect,
                                          ddl: ddlMode}
    }


    __DrawBTN(gCtrl, lParam) {
        Critical(-1)
        static CDRF_SKIPDEFAULT := 0x4
        static DT_CALCRECT      := 0x400
        static DT_WORDBREAK     := 0x10

        static o    := this.NMCUSTOMDRAW()
        hwndFrom    := NumGet(lParam, o.hwndFrom,    "Ptr")
        idFrom      := NumGet(lParam, o.idFrom,      "UInt")
        code        := NumGet(lParam, o.code,        "UInt")
        dwDrawStage := NumGet(lParam, o.dwDrawStage, "UInt")
        hdc         := NumGet(lParam, o.hdc,         "Ptr")
        left        := NumGet(lParam, o.left,        "UInt")
        top         := NumGet(lParam, o.top,         "UInt")
        right       := NumGet(lParam, o.right,       "UInt")
        bottom      := NumGet(lParam, o.bottom,      "UInt")
        dwItemSpec  := NumGet(lParam, o.dwItemSpec,  "Ptr")
        uItemState  := NumGet(lParam, o.uItemState,  "UInt")
        lItemlParam := NumGet(lParam, o.lItemlParam, "Ptr")
        RECT        := lParam + o.left
        width       := right  - left
        height      := bottom - top
        info        := Custom_Ctrl.clrHwnd.Get(hwndFrom, 0)

        brushColor  := info.bg
        textColor   := info.tx
        borderColor := info.bc
        borderWidth := info.bw
        ddlMode  := info.ddl
        DISABLED := info.he.DISABLED ?? ""
        SELECTED := info.he.SELECTED ?? ""
        HOT      := info.he.HOT      ?? ""

        if (uItemState & Custom_Ctrl.CDIS_DISABLED)
            brushColor := DISABLED != "" ? DISABLED : this.BrightenColor(brushColor, -20) ; -20
        else if (uItemState & Custom_Ctrl.CDIS_SELECTED || GetKeyState("LButton", "P") && Custom_Ctrl.first)
            brushColor := SELECTED != "" ? SELECTED : this.BrightenColor(brushColor, -10), Custom_Ctrl.first := false ; -10
        else if (uItemState & Custom_Ctrl.CDIS_HOT)
            brushColor := HOT != "" ? HOT : this.BrightenColor(brushColor, 20) ; 20

        ; Draw Background.
        this.SetBkMode(hdc, 0)
        this.SetDCBrushColor(hdc, this.RgbToBgr(brushColor))
        this.SelectObject(hdc, bru := this.GetStockObject(18))
        this.SelectObject(hdc, this.GetStockObject(19))
        this.FillRect(hdc, RECT, bru)

        if (borderColor != "") {
            hpen := this.CreatePen(0, borderWidth, this.RgbToBgr(borderColor))
            oldPen := this.SelectObject(hdc, hpen)
            this.SelectObject(hdc, this.GetStockObject(5)) ; NULL_BRUSH
            this.Rectangle(hdc, left, top, right, bottom)
            this.SelectObject(hdc, oldPen)
            this.DeleteObject(hpen)
        }

        if (textColor != "") {
            style     := this.GetWindowLong(gCtrl.Hwnd, -16) & 0x300
            textAlign := (style = 0x100) ? 0x0 : (style = 0x200) ? 0x2 : 0x1 ; Left, Right, Center
            dtFlags   := DT_WORDBREAK | textAlign

            if (textColor != "" && ddlMode == true) {
                this.RtlMoveMemory(defText := Buffer(16), RECT)
                this.SetTextColor(hdc, this.RgbToBgr(textColor))
                NumPut("Int", 4, defText, 0), NumPut("Int", width - 20, defText, 8)
                this.DrawText(hdc, gCtrl.Text, -1, defText, 0x24) ; DT_VCENTER | DT_SINGLELINE

                hFont := this.CreateFont(18, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0, "Arial")
                oldFont := this.SelectObject(hdc, hFont)

                this.SetTextColor(hdc, this.RgbToBgr("0xb9b9b9"))
                NumPut("Int", width - 14, RECT, 0), NumPut("Int", -2, RECT, 4)
                this.DrawText(hdc, "⌵", -1, RECT, 0x24) ; DT_VCENTER | DT_SINGLELINE

                this.SelectObject(hdc, oldFont)
                this.DeleteObject(hFont)

            } else {
                this.RtlMoveMemory(rcText := Buffer(16), RECT) ; Исходный прямоугольник
                this.RtlMoveMemory(rcCalc := Buffer(16), rcText) ; Высота текста
                textHeight := this.DrawText(hdc, gCtrl.Text, -1, rcCalc, dtFlags | DT_CALCRECT)

                ; Вертикальное смещение для центрирования
                btnHeight := NumGet(rcText, 12, "Int") - NumGet(rcText, 4, "Int")
                if (textHeight < btnHeight) {
                    offset := (btnHeight - textHeight) // 2
                    NumPut("Int", NumGet(rcText, 4, "Int") + offset, rcText, 4)   ; top
                    NumPut("Int", NumGet(rcText, 12, "Int") - offset, rcText, 12) ; bottom
                }

                this.SetTextColor(hdc, this.RgbToBgr(textColor))
                this.DrawText(hdc, gCtrl.Text, -1, rcText, dtFlags)
            }
        }
        return textColor != "" ? CDRF_SKIPDEFAULT : 1 ; Если цвет текста не задан, его рисует винда
    }


    __DrawDDL(wParam, lParam, msg, hwnd) {
        Critical(-1)
        static ODS_SELECTED := 0x0001
        static DT_FLAGS     := 0x824

        static o  := this.DRAWITEMSTRUCT()
        CtlType   := NumGet(lParam, o.CtlType,   "UInt")
        CtlID     := NumGet(lParam, o.CtlID,     "UInt")
        itemID    := NumGet(lParam, o.itemID,    "UInt")
        itemState := NumGet(lParam, o.itemState, "UInt")
        hwndItem  := NumGet(lParam, o.hwndItem,  "Ptr")
        hDC       := NumGet(lParam, o.hDC,       "Ptr")
        left      := NumGet(lParam, o.left,      "UInt")
        top       := NumGet(lParam, o.top,       "UInt")
        right     := NumGet(lParam, o.right,     "UInt")
        bottom    := NumGet(lParam, o.bottom,    "UInt")
        itemData  := NumGet(lParam, o.itemData,  "Ptr")
        RECT      := lParam + o.left

        info           := Custom_Ctrl.clrHwnd.Get(hwndItem, 0)
        currentBgColor := (itemState & ODS_SELECTED) ? info.highlightColor : info.bgColor

        this.SetDCBrushColor(hDC, this.RgbToBgr(currentBgColor))
        this.SelectObject(hDC, bru := this.GetStockObject(18))
        this.FillRect(hDC, RECT, bru)

        if (itemID != -1) {
            txtBuf := Buffer(2048, 0)
            SendMessage(CtlType = 2 ? 0x0189 : 0x0148, itemID, txtBuf.Ptr, hwndItem)
            this.SetBkMode(hDC, 1)
            this.SetTextColor(hDC, this.RgbToBgr(info.textColor))
            NumPut("UInt", left + 4, lParam, o.left)
            this.DrawText(hDC, StrGet(txtBuf), -1, RECT, DT_FLAGS)
        }
        return true
    }

    DRAWITEMSTRUCT() {
        static p := A_PtrSize
        return {
            CtlType: 0, CtlID: 4, itemID: 8, itemAction: 12, itemState: 16, hwndItem: p=8 ? 24 : 20, hDC: p=8 ? 32 : 24,
            left: p=8 ? 40 : 28, top: p=8 ? 44 : 32, right: p=8 ? 48 : 36, bottom: p=8 ? 52 : 40, ; RECT rcItem
            itemData: p=8 ? 56 : 44
        }
    }


    NMCUSTOMDRAW() {
        static p := A_PtrSize
        return {
            hwndFrom: 0, idFrom: p=8 ? 8 : 4, code: p=8 ? 16 : 8, ; NMHDR
            dwDrawStage: p=8 ? 24 : 12, hdc: p=8 ? 32 : 16,
            left: p=8 ? 40 : 20, top: p=8 ? 44 : 24, right: p=8 ? 48 : 28, bottom: p=8 ? 52 : 32, ; RECT rc
            dwItemSpec: p=8 ? 56 : 36, uItemState: p=8 ? 64 : 40, lItemlParam: p=8 ? 72 : 44
        }
    }


    RGB(R, G, B) => ((R << 16) | (G << 8) | B)
    BrightenColor(clr, perc := 5) => ((p := perc / 100 + 1), this.RGB(Round(Min(255, (clr >> 16 & 0xFF) * p)), Round(Min(255, (clr >> 8 & 0xFF) * p)), Round(Min(255, (clr & 0xFF) * p))))
    RgbToBgr(rgbColor) => ((rgbColor & 0xFF) << 16) | (((rgbColor >> 8) & 0xFF) << 8) | ((rgbColor >> 16) & 0xFF)

    RtlMoveMemory(Destination, Source, Length := 16) => DllCall("Kernel32\RtlMoveMemory", "Ptr", Destination, "Ptr", Source, "UPtr", Length, "Int")

    GetWindowLong(hWnd, nIndex) => DllCall("User32\GetWindowLong", "Ptr", hWnd, "Int", nIndex, "Int")

    SetWindowTheme(hwnd, pszSubAppName, pszSubIdList := 0) => DllCall("UxTheme\SetWindowTheme", "Ptr", hwnd, "Ptr", StrPtr(pszSubAppName), "Ptr", pszSubIdList, "Int")

    FillRect(hDC, lprc, hbr) => DllCall("User32\FillRect", "Ptr", hDC, "Ptr", lprc, "Ptr", hbr, "Int")

    SetBkMode(hdc, iBkMode) => DllCall("Gdi32\SetBkMode", "Ptr", hdc, "Int", iBkMode, "Int")

    SetDCBrushColor(hdc, crColor) => DllCall("Gdi32\SetDCBrushColor", "Ptr", hdc, "UInt", crColor, "UInt")

    SelectObject(hdc, hgdiobj) => DllCall("Gdi32\SelectObject", "Ptr", hdc, "Ptr", hgdiobj, "Ptr")

    GetStockObject(fnObject) => DllCall("Gdi32\GetStockObject", "Int", fnObject, "Ptr")

    DeleteObject(hObject) => DllCall("Gdi32\DeleteObject", "Ptr", hObject, "Int")

    CreatePen(fnPenStyle, nWidth, crColor) => DllCall("Gdi32\CreatePen", "Int", fnPenStyle, "Int", nWidth, "UInt", crColor, "Ptr")

    Rectangle(hdc, nLeftRect, nTopRect, nRightRect, nBottomRect) => DllCall("Gdi32\Rectangle", "Ptr", hdc, "Int", nLeftRect, "Int", nTopRect, "Int", nRightRect, "Int", nBottomRect, "Int")

    SetTextColor(hdc, crColor) => DllCall("Gdi32\SetTextColor", "Ptr", hdc, "UInt", crColor, "UInt")

    DrawText(hDC, lpchText, nCount, lpRect, uFormat) => DllCall("User32\DrawText", "Ptr", hDC, "Ptr", StrPtr(lpchText), "Int", nCount, "Ptr", lpRect, "UInt", uFormat, "Int")

    CreateFont(cHeight, cWidth, cEscapement, cOrientation, cWeight, bItalic, bUnderline, bStrikeOut, iCharSet, iOutPrecision, iClipPrecision, iQuality, iPitchAndFamily, pszFaceName) =>
        DllCall("Gdi32\CreateFont", "Int", cHeight, "Int", cWidth, "Int", cEscapement, "Int", cOrientation, "Int", cWeight,
        "UInt", bItalic, "UInt", bUnderline, "UInt", bStrikeOut, "UInt", iCharSet, "UInt", iOutPrecision, "UInt", iClipPrecision, 
        "UInt", iQuality, "UInt", iPitchAndFamily, "Str", pszFaceName, "Ptr")
}


class EditBorder {
    static WS_BORDER        := 0x00800000
    static WS_EX_CLIENTEDGE := 0x00000200

    static SWP_NOMOVE       := 0x0002
    static SWP_NOSIZE       := 0x0001
    static SWP_NOZORDER     := 0x0004
    static SWP_FRAMECHANGED := 0x0020
    static U_FLAGS          := EditBorder.SWP_NOMOVE | EditBorder.SWP_NOSIZE | EditBorder.SWP_NOZORDER | EditBorder.SWP_FRAMECHANGED

    static WM_NCCALCSIZE := 0x0083
    static WM_NCPAINT    := 0x0085


    __New(edit, borderColor := 0x303030, borderWidth := 2) {
        this.borderColor := borderColor
        this.borderWidth := borderWidth
        this.windowProcNew := CallbackCreate(ObjBindMethod(this, "WindowProc"), "", 4)
        this.windowProcOld := DllCall(A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong", "Ptr", edit.Hwnd, "Int", -4, "Ptr", this.windowProcNew, "Ptr")
        
        ; Нужно убрать стандартные стили границ чтобы винда не пыталась рисовать сови рамки.
        DllCall("SetWindowLong", "Ptr", edit.Hwnd, "Int", -16, "Int", DllCall("GetWindowLong", "Ptr", edit.Hwnd, "Int", -16) & ~EditBorder.WS_BORDER)
        DllCall("SetWindowLong", "Ptr", edit.Hwnd, "Int", -20, "Int", DllCall("GetWindowLong", "Ptr", edit.Hwnd, "Int", -20) & ~EditBorder.WS_EX_CLIENTEDGE)

        ; Важно заставить окно пересчитать свои размеры - это вызовет WM_NCCALCSIZE, где мы зададим новую толщину рамки.
        DllCall("SetWindowPos", "Ptr", edit.Hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", EditBorder.U_FLAGS)
    }


    WindowProc(hwnd, uMsg, wParam, lParam) {
        if (uMsg = EditBorder.WM_NCCALCSIZE) { ; Пересчет размера рамки
            if (wParam) { ; Если wParam = true, lParam содержит структуру NCCALCSIZE_PARAMS
                NumPut(
                    "Int", NumGet(lParam, 0,  "Int") + this.borderWidth, ; left
                    "Int", NumGet(lParam, 4,  "Int") + this.borderWidth, ; top
                    "Int", NumGet(lParam, 8,  "Int") - this.borderWidth, ; right
                    "Int", NumGet(lParam, 12, "Int") - this.borderWidth, ; bottom
                    lParam
                )
                return DllCall("CallWindowProc", "Ptr", this.windowProcOld, "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam)
            }
        }

        if (uMsg = EditBorder.WM_NCPAINT) { ; Отрисовка рамки
            hdc := DllCall("GetWindowDC", "Ptr", hwnd, "Ptr")
            
            DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect := Buffer(16))
            width  := NumGet(rect, 8,  "Int") - NumGet(rect, 0, "Int")
            height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
            
            hBrush := DllCall("CreateSolidBrush", "UInt", this.RgbToBgr(this.borderColor), "Ptr")
            frame := Buffer(16)
            
            Loop this.borderWidth {
                i := A_Index - 1
                NumPut("Int", i, "Int", i, "Int", width - i, "Int", height - i, frame, 0)
                DllCall("FrameRect", "Ptr", hdc, "Ptr", frame, "Ptr", hBrush)
            }
            
            DllCall("DeleteObject", "Ptr", hBrush)
            DllCall("ReleaseDC", "Ptr", hwnd, "Ptr", hdc)
        }
        return DllCall("CallWindowProc", "Ptr", this.windowProcOld, "Ptr", hwnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam)
    }

    RgbToBgr(rgbColor) => ((rgbColor & 0xFF) << 16) | (((rgbColor >> 8) & 0xFF) << 8) | ((rgbColor >> 16) & 0xFF)
}


Class GuiReSizer {
    Static Call(GuiObj, WindowMinMax, GuiW, GuiH) {
        ; Initial display of Gui use redraw to cleanup first positioning
        Try
            (GuiObj.Init)
        Catch
            GuiObj.Init := 3 ; Redraw twice and initialize abbreviations on Initial Call (called on initial Show)
        ; Window minimize and maximize
        If WindowMinMax = -1 ; Do nothing if window minimized
            Return
        If WindowMinMax = 1 ; Repeat if maximized
            Repeat := true
        ; Loop through all Controls of Gui
        Loop 2 { ; Loop twice by default to calculate Anchor controls
            For Hwnd, CtrlObj in GuiObj {
                ;{ Initializations on First Call
                If GuiObj.Init = 3 {
                    Try CtrlObj.OriginX := CtrlObj.OX
                    Try CtrlObj.OriginXP := CtrlObj.OXP
                    Try CtrlObj.OriginY := CtrlObj.OY
                    Try CtrlObj.OriginYP := CtrlObj.OYP
                    Try CtrlObj.Width := CtrlObj.W
                    Try CtrlObj.WidthP := CtrlObj.WP
                    Try CtrlObj.Height := CtrlObj.H
                    Try CtrlObj.HeightP := CtrlObj.HP
                    Try CtrlObj.MinWidth := CtrlObj.MinW
                    Try CtrlObj.MaxWidth := CtrlObj.MaxW
                    Try CtrlObj.MinHeight := CtrlObj.MinH
                    Try CtrlObj.MaxHeight := CtrlObj.MaxH
                    Try CtrlObj.Function := CtrlObj.F
                    Try CtrlObj.Cleanup := CtrlObj.C
                    Try CtrlObj.Anchor := CtrlObj.A
                    Try CtrlObj.AnchorIn := CtrlObj.AI
                    If !CtrlObj.HasProp("AnchorIn")
                        CtrlObj.AnchorIn := true
                }
                ; Initialize Current Positions and Sizes
                CtrlObj.GetPos(&CtrlX, &CtrlY, &CtrlW, &CtrlH)
                LimitX := AnchorW := GuiW, LimitY := AnchorH := GuiH, OffsetX := OffsetY := 0
                ; Check for Anchor
                If CtrlObj.HasProp("Anchor") {
                    Repeat := true
                    CtrlObj.Anchor.GetPos(&AnchorX, &AnchorY, &AnchorW, &AnchorH)
                    If CtrlObj.HasProp("X") or CtrlObj.HasProp("XP")
                        OffsetX := AnchorX
                    If CtrlObj.HasProp("Y") or CtrlObj.HasProp("YP")
                        OffsetY := AnchorY
                    If CtrlObj.AnchorIn
                        LimitX := AnchorW, LimitY := AnchorH
                }
                ; OriginX
                If CtrlObj.HasProp("OriginX") and CtrlObj.HasProp("OriginXP")
                    OriginX := CtrlObj.OriginX + (CtrlW * CtrlObj.OriginXP)
                Else If CtrlObj.HasProp("OriginX") and !CtrlObj.HasProp("OriginXP")
                    OriginX := CtrlObj.OriginX
                Else If !CtrlObj.HasProp("OriginX") and CtrlObj.HasProp("OriginXP")
                    OriginX := CtrlW * CtrlObj.OriginXP
                Else
                    OriginX := 0
                ; OriginY
                If CtrlObj.HasProp("OriginY") and CtrlObj.HasProp("OriginYP")
                    OriginY := CtrlObj.OriginY + (CtrlH * CtrlObj.OriginYP)
                Else If CtrlObj.HasProp("OriginY") and !CtrlObj.HasProp("OriginYP")
                    OriginY := CtrlObj.OriginY
                Else If !CtrlObj.HasProp("OriginY") and CtrlObj.HasProp("OriginYP")
                    OriginY := CtrlH * CtrlObj.OriginYP
                Else
                    OriginY := 0
                ; X
                If CtrlObj.HasProp("X") and CtrlObj.HasProp("XP")
                    CtrlX := Mod(LimitX + CtrlObj.X + (AnchorW * CtrlObj.XP) - OriginX, LimitX)
                Else If CtrlObj.HasProp("X") and !CtrlObj.HasProp("XP")
                    CtrlX := Mod(LimitX + CtrlObj.X - OriginX, LimitX)
                Else If !CtrlObj.HasProp("X") and CtrlObj.HasProp("XP")
                    CtrlX := Mod(LimitX + (AnchorW * CtrlObj.XP) - OriginX, LimitX)
                ; Y
                If CtrlObj.HasProp("Y") and CtrlObj.HasProp("YP")
                    CtrlY := Mod(LimitY + CtrlObj.Y + (AnchorH * CtrlObj.YP) - OriginY, LimitY)
                Else If CtrlObj.HasProp("Y") and !CtrlObj.HasProp("YP")
                    CtrlY := Mod(LimitY + CtrlObj.Y - OriginY, LimitY)
                Else If !CtrlObj.HasProp("Y") and CtrlObj.HasProp("YP")
                    CtrlY := Mod(LimitY + AnchorH * CtrlObj.YP - OriginY, LimitY)
                ; Width
                If CtrlObj.HasProp("Width") and CtrlObj.HasProp("WidthP")
                    (CtrlObj.Width > 0 and CtrlObj.WidthP > 0 ? CtrlW := CtrlObj.Width + AnchorW * CtrlObj.WidthP : CtrlW := CtrlObj.Width + AnchorW + AnchorW * CtrlObj.WidthP - CtrlX)
                Else If CtrlObj.HasProp("Width") and !CtrlObj.HasProp("WidthP")
                    (CtrlObj.Width > 0 ? CtrlW := CtrlObj.Width : CtrlW := AnchorW + CtrlObj.Width - CtrlX)
                Else If !CtrlObj.HasProp("Width") and CtrlObj.HasProp("WidthP")
                    (CtrlObj.WidthP > 0 ? CtrlW := AnchorW * CtrlObj.WidthP : CtrlW := AnchorW + AnchorW * CtrlObj.WidthP - CtrlX)
                ; Height
                If CtrlObj.HasProp("Height") and CtrlObj.HasProp("HeightP")
                    (CtrlObj.Height > 0 and CtrlObj.HeightP > 0 ? CtrlH := CtrlObj.Height + AnchorH * CtrlObj.HeightP : CtrlH := CtrlObj.Height + AnchorH + AnchorH * CtrlObj.HeightP - CtrlY)
                Else If CtrlObj.HasProp("Height") and !CtrlObj.HasProp("HeightP")
                    (CtrlObj.Height > 0 ? CtrlH := CtrlObj.Height : CtrlH := AnchorH + CtrlObj.Height - CtrlY)
                Else If !CtrlObj.HasProp("Height") and CtrlObj.HasProp("HeightP")
                    (CtrlObj.HeightP > 0 ? CtrlH := AnchorH * CtrlObj.HeightP : CtrlH := AnchorH + AnchorH * CtrlObj.HeightP - CtrlY)
                ; Min Max
                (CtrlObj.HasProp("MinX") ? MinX := CtrlObj.MinX : MinX := -999999)
                (CtrlObj.HasProp("MaxX") ? MaxX := CtrlObj.MaxX : MaxX := 999999)
                (CtrlObj.HasProp("MinY") ? MinY := CtrlObj.MinY : MinY := -999999)
                (CtrlObj.HasProp("MaxY") ? MaxY := CtrlObj.MaxY : MaxY := 999999)
                (CtrlObj.HasProp("MinWidth") ? MinW := CtrlObj.MinWidth : MinW := 0)
                (CtrlObj.HasProp("MaxWidth") ? MaxW := CtrlObj.MaxWidth : MaxW := 999999)
                (CtrlObj.HasProp("MinHeight") ? MinH := CtrlObj.MinHeight : MinH := 0)
                (CtrlObj.HasProp("MaxHeight") ? MaxH := CtrlObj.MaxHeight : MaxH := 999999)
                CtrlX := MinMax(CtrlX, MinX, MaxX)
                CtrlY := MinMax(CtrlY, MinY, MaxY)
                CtrlW := MinMax(CtrlW, MinW, MaxW)
                CtrlH := MinMax(CtrlH, MinH, MaxH)

                CtrlObj.Move(CtrlX + OffsetX, CtrlY + OffsetY, CtrlW, CtrlH)
                If GuiObj.Init or (CtrlObj.HasProp("Cleanup") and CtrlObj.Cleanup = true)
                    CtrlObj.Redraw()
                If CtrlObj.HasProp("Function")
                    CtrlObj.Function(GuiObj) ; CtrlObj is hidden 'this' first parameter
            }
            If !IsSet(Repeat) ; Break loop if no Repeat is needed because of Anchor or Maximize
                Break
        }

        If (GuiObj.Init := GuiObj.Init - 1 > 0) {
            GuiObj.GetClientPos(, , &AnchorW, &AnchorH)
            GuiReSizer(GuiObj, WindowMinMax, AnchorW, AnchorH)
        }
        If WindowMinMax = 1 ; maximized
            GuiObj.Init := 2 ; redraw twice on next call after a maximize
        MinMax(Num, MinNum, MaxNum) => Min(Max(Num, MinNum), MaxNum)
    }

    Static Opt(CtrlObj, Options) => GuiReSizer.Options(CtrlObj, Options)
    Static Options(CtrlObj, Options) {
        For Option in StrSplit(Options, " ") {
            For Abbr, Cmd in Map(
                "xp", "XP", "yp", "YP", "x", "X", "y", "Y",
                "wp", "WidthP", "hp", "HeightP", "w", "Width", "h", "Height",
                "minx", "MinX", "maxx", "MaxX", "miny", "MinY", "maxy", "MaxY",
                "minw", "MinWidth", "maxw", "MaxWidth", "minh", "MinHeight", "maxh", "MaxHeight",
                "oxp", "OriginXP", "oyp", "OriginYP", "ox", "OriginX", "oy", "OriginY")
                If RegExMatch(Option, "i)^" Abbr "([\d.-]*$)", &Match) {
                    CtrlObj.%Cmd% := Match.1
                    Break
                }

            If SubStr(Option, 1, 1) = "o" {
                Flags := SubStr(Option, 2)
                If Flags ~= "i)l"           ; left
                    CtrlObj.OriginXP := 0
                If Flags ~= "i)c"           ; center (left to right)
                    CtrlObj.OriginXP := 0.5
                If Flags ~= "i)r"           ; right
                    CtrlObj.OriginXP := 1
                If Flags ~= "i)t"           ; top
                    CtrlObj.OriginYP := 0
                If Flags ~= "i)m"           ; middle (top to bottom)
                    CtrlObj.OriginYP := 0.5
                If Flags ~= "i)b"           ; bottom
                    CtrlObj.OriginYP := 1
            }
        }
    }

    Static Now(GuiObj, Redraw := true, Init := 2) {
        If Redraw
            GuiObj.Init := Init
        GuiObj.GetClientPos(, , &Width, &Height)
        GuiReSizer(GuiObj, WindowMinMax := 1, Width, Height)
    }
}


class CustomTitleBarWindow {
    /**
     * @param {GuiObj} gui
     * @param {Color} colorTheme - Цвет заголовка в формате RGB.
     * @param {Integer} titleBarHeight - Высота заголовка в пикселях.
     * @param {Integer} showSystemMenu - Будет ли отображенно системно меню, при клике ПКМ по заголовку [true || false].
     * @param {Integer} winLimitMaximized - У всех окон в WinApi заголовок окна уходят на 7-8 пикселей при максимальном изменение размера окна. Это можно исправить:
     * Имейте ввиду что верхяя граница окна являеться клиентской областью окна, то есть там можно размещать контролы. Учитывайте это при выборе флага `winLimitMaximized`.
     * ```ahk
     * winLimitMaximized := 0 ; Если установить значение "0" окно будет вести себя как обычно.
     * winLimitMaximized := 1 ; Если установить значение "1" то при максимальном изменение размера окна, заголовок не будет уходить за экран (включая границу).
     * winLimitMaximized := 2 ; Если установить значение "2" окно будет вести себя аналогично [winLimitMaximized := 1], за исключением того что верхяя граница окна будет уходить за экран.
     * ```
     * @param {Integer} fixTopBorder - Если `fixTopBorderColor := false`, то цвет верхней границы будет равен [цвет заголовка `colorTheme` + интерполяция цвета + прозрачность]. Если `fixTopBorderColor := true`, то граница будет иметь системный цвет [Примерно "0x80000000"].
     */
    __New(gui, colorTheme := "000000", titleBarHeight := 31, showSystemMenu := true, winLimitMaximized := 1, fixTopBorderColor := false) {
        this.hwnd              := gui.hwnd
        this.gui               := gui
        this.titleBarHeight    := titleBarHeight
        this.colorTheme        := colorTheme
        this.showSystemMenu    := showSystemMenu
        this.winLimitMaximized := winLimitMaximized
        this.fixTopBorderColor := fixTopBorderColor
        this.Create()
    }


    Create() {
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.hwnd, "UInt", 20, "Ptr*", 1, "UInt", 4)
        this.ExtendFrameIntoClientArea()
        this.SetupMessageHandlers()
        this.DrawTitle()
        this.RefreshFrame()
    }


    DrawTitle() {
        static SM_CXVIRTUALSCREEN := DllCall("GetSystemMetrics", "Int", 78) + 50 ; Ширина виртуального экрана в пикселях + запас.
        this.title := this.gui.AddText("x0 y0 w" SM_CXVIRTUALSCREEN " h" this.titleBarHeight " Background" this.colorTheme)
        if (this.fixTopBorderColor) {
            borderTitle := this.gui.AddText("x0 y0 w" SM_CXVIRTUALSCREEN " h1 Background000000")
            borderTitle.Redraw()
        }
        if (this.winLimitMaximized) {
            this.gui.OnEvent("Size", (*) {
                if (DllCall("IsZoomed", "Ptr", this.hwnd, "Int")) {
                    this.WinMaximizedOffsetWorkArea()
                }
            })
        }
    }


    GetCoord(lParam, &x, &y, mode := "Screen") {
        x := (x := lParam & 0xFFFF) > 0x7FFF ? x - 0x10000 : x
        y := (y := (lParam >> 16) & 0xFFFF) > 0x7FFF ? y - 0x10000 : y

        if (mode = "Client") {
            pt := Buffer(8), NumPut("Int", x, "Int", y, pt)
            DllCall("ScreenToClient", "Ptr", this.hwnd, "Ptr", pt)
            x := NumGet(pt, 0, "Int"), y := NumGet(pt, 4, "Int")
        }
    }


    GetClientRect(&width, &height) {
        DllCall("GetClientRect", "Ptr", this.hwnd, "Ptr", rect := Buffer(16))
        width := NumGet(rect, 8, "Int"), height := NumGet(rect, 12, "Int")
    }


    ; Когда окно развёрнуто, часть уходит за экран
    GetMaximizedOffset(dpi) {
        frameY  := DllCall("User32\GetSystemMetricsForDpi", "Int", 33, "UInt", dpi, "Int")  ; SM_CYFRAME
        padding := DllCall("User32\GetSystemMetricsForDpi", "Int", 92, "UInt", dpi, "Int")  ; SM_CXPADDEDBORDER
        return frameY + padding  ; ~7-8 пикселей
    }


    WinMaximizedOffsetWorkArea() {
        dpi := DllCall("User32\GetDpiForWindow", "Ptr", this.hwnd, "UInt")
        minMaxOffset := this.GetMaximizedOffset(dpi)

        monitor := DllCall("MonitorFromWindow", "Ptr", this.hwnd, "UInt", 2) ; MONITOR_DEFAULTTONEAREST
        mi := Buffer(40), NumPut("UInt", 40, mi) ; cbSize
        DllCall("GetMonitorInfo", "Ptr", monitor, "Ptr", mi)

        workLeft   := NumGet(mi, 20, "Int") ; rcWork.left
        workTop    := NumGet(mi, 24, "Int") ; rcWork.top
        workRight  := NumGet(mi, 28, "Int") ; rcWork.right
        workBottom := NumGet(mi, 32, "Int") ; rcWork.bottom
        
        workWidth  := workRight - workLeft
        workHeight := workBottom - workTop
        threshold  := minMaxOffset
        
        this.GetClientRect(&width, &height)
        if (width >= workWidth - threshold && height >= workHeight - threshold) {
            this.gui.Move(workLeft - minMaxOffset, workTop -= (this.winLimitMaximized = 2) ? 1 : 0)
            ;return 1
        }
        ;return 0
    }


    RefreshFrame() {
        DllCall("SetWindowPos", "Ptr", this.hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x0027) ; SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER
    }

    ExtendFrameIntoClientArea() {
        ; высота заголовка в физические пиксели для DWM
        dpi := DllCall("User32\GetDpiForWindow", "Ptr", this.hwnd, "UInt")
        physicalHeight := Round(this.titleBarHeight * (dpi / 96.0))
        margins := Buffer(16), NumPut("Int", 0, "Int", 0, "Int", physicalHeight, "Int", 0, margins)
        DllCall("dwmapi\DwmExtendFrameIntoClientArea", "Ptr", this.hwnd, "Ptr", margins)
    }


    SetupMessageHandlers() {
        OnMessage(0x0083, ObjBindMethod(this, "WM_NCCALCSIZE"))
        OnMessage(0x0084, ObjBindMethod(this, "WM_NCHITTEST"))
        if (this.showSystemMenu)
            OnMessage(0x00A5, ObjBindMethod(this, "WM_NCRBUTTONUP"))
        OnMessage(0x02A2, ObjBindMethod(this, "WM_NCMOUSELEAVE"))
        ;OnMessage(0x0005, ObjBindMethod(this, "WM_SIZE"))
        OnMessage(0x02E0, ObjBindMethod(this, "WM_DPICHANGED")) ; обработка смены монитора/DPI, чтобы рамка перерисовывалась
    }


    WM_NCCALCSIZE(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return

        if (wParam) { ; системные метрики с учетом масштаба текущего экрана
            dpi     := DllCall("User32\GetDpiForWindow", "Ptr", hwnd, "UInt")
            frameX  := DllCall("User32\GetSystemMetricsForDpi", "Int", 32, "UInt", dpi, "Int") ; SM_CXFRAME
            frameY  := DllCall("User32\GetSystemMetricsForDpi", "Int", 33, "UInt", dpi, "Int") ; SM_CYFRAME
            padding := DllCall("User32\GetSystemMetricsForDpi", "Int", 92, "UInt", dpi, "Int") ; SM_CXPADDEDBORDER
            
            NumPut("Int", NumGet(lParam, 0,  "Int") + frameX + padding, lParam, 0)  ; left
            NumPut("Int", NumGet(lParam, 4,  "Int"),  lParam, 4)                    ; top (без изменений)
            NumPut("Int", NumGet(lParam, 8,  "Int") - frameX - padding, lParam, 8)  ; right
            NumPut("Int", NumGet(lParam, 12, "Int") - frameY - padding, lParam, 12) ; bottom
            return 0
        }
    }


    WM_NCHITTEST(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return

        if DllCall("dwmapi\DwmDefWindowProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr", lResult := Buffer(8)) ; DWM сначала для hover эффектов кнопок
            return NumGet(lResult, 0, "Ptr")

        this.GetCoord(lParam, &clientX, &clientY, "Client") ; Клиентские координаты
        this.GetClientRect(&width, &height) ; Размер окна (W / H)

        ; Смещение GUI относительно рабочей области "A" монитора. Если окно развернуто, то весь заголовок HTCAPTION.
        ; FIX: Зоны HitTest рассчитываются в физических координатах
        dpi := DllCall("User32\GetDpiForWindow", "Ptr", hwnd, "UInt")
        scale := dpi / 96.0
        physicalTitleBarHeight := Round(this.titleBarHeight * scale)
        borderSize := Round(5 * scale) ; Размер области resize

        if (this.winLimitMaximized && DllCall("IsZoomed", "Ptr", this.hwnd, "Int")) {
            return clientY < physicalTitleBarHeight ? 2 : 1
        }

        switch {
            case clientY < borderSize && clientX < borderSize                  : return 13 ; HTTOPLEFT
            case clientY < borderSize && clientX > width - borderSize          : return 14 ; HTTOPRIGHT
            case clientY < borderSize                                          : return 12 ; HTTOP
            case clientY > height - borderSize && clientX < borderSize         : return 16 ; HTBOTTOMLEFT
            case clientY > height - borderSize && clientX > width - borderSize : return 17 ; HTBOTTOMRIGHT
            case clientY > height - borderSize                                 : return 15 ; HTBOTTOM
            case clientX < borderSize                                          : return 10 ; HTLEFT
            case clientX > width - borderSize                                  : return 11 ; HTRIGHT
            case clientY < this.titleBarHeight                                 : return 2  ; HTCAPTION
        }
        return 1 ; HTCLIENT
    }


    WM_NCRBUTTONUP(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return

        static TPM_RETURNCMD   := 0x0100
        static TPM_RIGHTBUTTON := 0x0002
        static WM_SYSCOMMAND   := 0x0112
        static MF_ENABLED      := 0x0000
        static MF_GRAYED       := 0x0001
        static SC_RESTORE      := 0xF120
        static SC_MOVE         := 0xF010
        static SC_SIZE         := 0xF000
        static SC_MINIMIZE     := 0xF020
        static SC_MAXIMIZE     := 0xF030
        static SC_CLOSE        := 0xF060
        static HTCAPTION       := 2
        
        if (wParam = HTCAPTION) {
            this.GetCoord(lParam, &x, &y, "Screen")
            hMenu := DllCall("GetSystemMenu", "Ptr", this.hwnd, "Int", 0, "Ptr")
            isMaximized := DllCall("IsZoomed", "Ptr", this.hwnd, "Int")
            isMinimized := DllCall("IsIconic", "Ptr", this.hwnd, "Int")
            DllCall("EnableMenuItem", "Ptr", hMenu, "UInt", SC_RESTORE, "UInt", (isMaximized || isMinimized) ? MF_ENABLED : MF_GRAYED)
            DllCall("EnableMenuItem", "Ptr", hMenu, "UInt", SC_MOVE, "UInt", isMaximized ? MF_GRAYED : MF_ENABLED)
            DllCall("EnableMenuItem", "Ptr", hMenu, "UInt", SC_SIZE, "UInt", isMaximized ? MF_GRAYED : MF_ENABLED)
            DllCall("EnableMenuItem", "Ptr", hMenu, "UInt", SC_MAXIMIZE, "UInt", isMaximized ? MF_GRAYED : MF_ENABLED)
            ;DllCall("EnableMenuItem", "Ptr", hMenu, "UInt", SC_CLOSE, "UInt", MF_ENABLED)
            cmd := DllCall("TrackPopupMenu", "Ptr", hMenu, "UInt", TPM_RETURNCMD | TPM_RIGHTBUTTON, "Int", x, "Int", y, "Int", 0, "Ptr", this.hwnd, "Ptr", 0, "UInt")

            if (cmd)
                PostMessage(WM_SYSCOMMAND, cmd, 0,, this.hwnd)
            return 0
        }
    }


    ; Если dwmDefWindowProc не вызывается для сообщения WM_NCMOUSELEAVE, DWM не удаляет выделение с кнопок заголовка.
    WM_NCMOUSELEAVE(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        if DllCall("dwmapi\DwmDefWindowProc", "Ptr", hwnd, "UInt", msg, "Ptr", wParam, "Ptr", lParam, "Ptr", lResult := Buffer(8))
            return NumGet(lResult, 0, "Ptr")
        return 0
    }


    WM_SIZE(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return

        if (this.winLimitMaximized && wParam = 2) { ; SIZE_MAXIMIZED
            this.WinMaximizedOffsetWorkArea()
        }
    }


    ; Обработчик перемещения окна на монитор с другим масштабом
    WM_DPICHANGED(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        this.ExtendFrameIntoClientArea()
    }
}


class DarkMode {
    __New() {
        uxtheme := DllCall("kernel32\GetModuleHandle", "Str", "uxtheme", "Ptr")
        DllCall(DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr"), "Int", 2) ; SetPreferredAppMode
        DllCall(DllCall("kernel32\GetProcAddress", "Ptr", uxtheme, "Ptr", 136, "Ptr"))           ; FlushMenuThemes

        ; OnMessage(0x0134, this.WM_CTLCOLORLISTBOX.Bind(this))
    }

    ; WM_CTLCOLORLISTBOX(wParam, lParam, msg, hwnd) {
    ;     DllCall("gdi32\SetTextColor", "ptr", wParam, "uint", "0xd1bea3")
    ;     DllCall("gdi32\SetDCBrushColor", "ptr", wParam, "uint", "0x141414")
    ;     return DllCall("gdi32\GetStockObject", "int", 18, "ptr")
    ; }
}


class GuiMcode {
    static borderСolor := "303030"
    static mainColor   := "005343"
    static decor       := "005343"

    static ARR_FLAGS  := ["GCC (x64)", "GCC (x64) Mcode", "GCC (x86)", "GCC (x86) Mcode", "MSVC (x64_x86)"]
    static IMPORT_DLL := "User32|Kernel32|ntdll|Gdi32|Advapi32|msvcrt|Shell32|Ole32|OleAut32|Comctl32|Shlwapi|Ws2_32|Iphlpapi|Version|Secur32|Winmm|Imm32|Uxtheme|Setupapi|Crypt32"

    __New() {
        DarkMode()
        this.ctrl := Custom_Ctrl()
        this.CreateMainGUI()
        this.CreateSettingsGUI()
        this.CreateSetPathGUI()
        this.CreateCOFFinfoGUI()

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
        this.flags        := this.mainG.AddEdit("Background101010", IniRead(GLOBAL_INI_FILE, "SETTINGS", "FLAGS", "-m64 -O2"))
        this.sourceFile   := this.mainG.AddEdit("Background101010", IniRead(GLOBAL_INI_FILE, "SETTINGS", "SOURCE_FILE", "Mcode[.c / .cpp] || Mcode[.o / .obj] (CHANGE)"))
        this.objdumpFlags := this.mainG.AddEdit("Background101010", IniRead(GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_FLAGS", "-D -C -M intel"))
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
        this.copyMcodeFunc := this.mainG.AddButton("x403 y5 h22", "Copy Mcode Func")

        this.objdumpRE  := this.CreateRichEdit(this.mainG, "Consolas", 11, "0xffffff", "0x101010")
        this.cppRE      := this.CreateRichEdit(this.mainG, "Consolas", 11, "0xffffff", "0x101010")
        this.warningRE  := this.CreateRichEdit(this.mainG, "Consolas", 9,  "0x98e6e6", "0x101010")
        this.infoRE     := this.CreateRichEdit(this.mainG, "Consolas", 9,  "0x551b19", "0x101010")
        this.hexRE      := this.CreateRichEdit(this.mainG, "Consolas", 9,  "0x11b1a9", "0x101010")
        this.base64RE   := this.CreateRichEdit(this.mainG, "Consolas", 9,  "0x11b1a9", "0x101010")
        this.compressRE := this.CreateRichEdit(this.mainG, "Consolas", 9,  "0x11b1a9", "0x101010") ; 0x12abd1


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
        this.setFlagsDDL.Function        := (CtrlObj, GuiObj) => PostMessage(0x0153, -1, 18, CtrlObj)
        this.waitSectionObjdump.Function := (CtrlObj, GuiObj) => PostMessage(0x0153, -1, 16, CtrlObj)

        this.ctrl.ClrBtn(this.setModeDDLBtn,           "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766}, true)
        this.ctrl.ClrBtn(this.COFFinfo,                "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        this.ctrl.ClrBtn(this.settings,                "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        this.ctrl.ClrBtn(this.copyMcodeFunc,           "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        this.ctrl.ClrBtn(this.browseSourceFile,        "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.setFlagsDDLBtn,          "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}, true)
        this.ctrl.ClrBtn(this.addFlagsDDl,             "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.copyTable,               "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.waitSectionObjdumpBtn,   "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}, true)
        this.ctrl.ClrBtn(this.generateMcodeFromSrc,    "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.copyCode,                "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.generateMcodeFromEditor, "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.parseBytes,              "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.copyHex,                 "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.copyBase64,              "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.copyCompress,            "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}) ; 0x32606b
        this.ctrl.ClrDDL(this.setFlagsDDL,             "0x141414", "0xa3bed1", "0x1f3a3a")
        this.ctrl.ClrDDL(this.waitSectionObjdump,      "0x141414", "0xa3bed1", "0x1f3a3a")
        this.ctrl.ClrDDL(this.setModeDDL,              "0x141414", "0xa3bed1", "0x1f3a3a")

        EditBorder(this.flags)
        EditBorder(this.sourceFile)
        EditBorder(this.objdumpFlags)
        EditBorder(this.objdumpRE)
        EditBorder(this.cppRE)
        EditBorder(this.warningRE)
        EditBorder(this.infoRE)
        EditBorder(this.hexRE)
        EditBorder(this.base64RE)
        EditBorder(this.compressRE)

        IDE(this.cppRE, RTF.CSyntax)
        IDE(this.objdumpRE, RTF.ObjdumpHighlight)
        RTF.ReplaceSel(GLOBAL_C_CODE, RTF.CSyntax, this.cppRE)
    }


    CreateSettingsGUI() {
        this.settingsG := Gui()
        this.settingsG.SetFont("s11", "Consolas")
        this.settingsG.BackColor := 0x060606
        CustomTitleBarWindow(this.settingsG, "005343",,,,true)

        this.settingsG.AddText("x10 y43  c0x9AA7B0", "MSVC x64 path:")
        this.settingsG.AddText("x10 y77  c0x9AA7B0", "MSVC x86 path:")
        this.settingsG.AddText("x10 y111 c0x9AA7B0", "GCC path:")
        this.settingsG.AddText("x10 y145 c0x9AA7B0", "Objdump path:")
        this.settingsG.AddText("x900 y51 c12abd1", ASCII_MCODE).SetFont("s10")

        this.MSVCPathX64   := this.settingsG.AddEdit("x130 y41  w596 h24 Background101010 c11b1a9", IniRead(GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X64", "\VC\Auxiliary\Build\vcvars64.bat"))
        this.MSVCPathX86   := this.settingsG.AddEdit("x130 y75  w596 h24 Background101010 c11b1a9", IniRead(GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X86", "\VC\Auxiliary\Build\vcvars32.bat"))
        this.GCCPath       := this.settingsG.AddEdit("x130 y109 w596 h24 Background101010 c11b1a9", IniRead(GLOBAL_INI_FILE, "SETTINGS", "GCC_PATH",      "\bin\x86_64-w64-mingw32-gcc-10.3.0.exe [change]"))
        this.objdumpPath   := this.settingsG.AddEdit("x130 y143 w596 h24 Background101010 c11b1a9", IniRead(GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_PATH",  "\bin\objdump.exe [change]"))
        this.settingsG.SetFont("s9", "Consolas")
        this.browseMSVCX64 := this.settingsG.AddButton("x736 y41  w120 h24", "Browse MSVC x64")
        this.browseMSVCX86 := this.settingsG.AddButton("x736 y75  w120 h24", "Browse MSVC x86")
        this.browseGCC     := this.settingsG.AddButton("x736 y109 w120 h24", "Browse GCC")
        this.browseObjdump := this.settingsG.AddButton("x736 y143 w120 h24", "Browse Objdump")
        this.settingsG.SetFont("s11", "Consolas")

        this.settingsG.AddText("x100 y191 c0x9AA7B0", "General settings")
        this.settingsG.AddText("x450 y191 c0x9AA7B0", "Compiler settings")
        this.settingsG.AddText("x870 y191 c0x9AA7B0", "Linker settings")
        this.settingsG.AddText("x820 y319 c0x9AA7B0", "===== Import Dll =====")

        this.displayObjdump          := this.settingsG.AddButton("x20 y223 w18 h18", IniRead(GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_OBJDUMP",            "✔")), this.settingsG.AddText("x48 y223 c0x12abd1", "Display disassembler")
        this.objdumpHighlighting     := this.settingsG.AddButton("x20 y255 w18 h18", IniRead(GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_HIGHLIGHTING",       "✔")), this.settingsG.AddText("x48 y255 c0x12abd1", "Disassembler highlighting")
        this.displayHexMcode         := this.settingsG.AddButton("x20 y287 w18 h18", IniRead(GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_HEX_MCODE",          "✔")), this.settingsG.AddText("x48 y287 c0x12abd1", "Display Hex Mcode")
        this.displayBase64Mcode      := this.settingsG.AddButton("x20 y319 w18 h18", IniRead(GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_BASE64_MCODE",       "")),  this.settingsG.AddText("x48 y319 c0x12abd1", "Display Base64 Mcode")
        this.displayCompressMcode    := this.settingsG.AddButton("x20 y351 w18 h18", IniRead(GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_COMPRESS_MCODE",     "")),  this.settingsG.AddText("x48 y351 c0x12abd1", "Display Compress Mcode")
        this.displayFullOffsetTable  := this.settingsG.AddButton("x20 y383 w18 h18", IniRead(GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_FULL_OFFSET_TABLE",  "✔")), this.settingsG.AddText("x48 y383 c0x12abd1", "Display full offset table")
        this.showCommentsOffsetTable := this.settingsG.AddButton("x20 y415 w18 h18", IniRead(GLOBAL_INI_FILE, "SETTINGS", "SHOW_COMMENTS_OFFSET_TABLE", "✔")), this.settingsG.AddText("x48 y415 c0x12abd1", "Show comments for the offset table")
        this.multilineOutputLength   := this.settingsG.AddEdit("x220 y446 w62 h22 Background101010 c11b1a9 Center Number", IniRead(GLOBAL_INI_FILE, "SETTINGS", "MULTILINE_OUTPUT_LENGTH",    "176")), this.settingsG.AddText("x20 y447 c0x9AA7B0", "Multiline output length:")

        this.cFileMode         := this.settingsG.AddButton("x350 y223 w18 h18",  IniRead(GLOBAL_INI_FILE, "SETTINGS", "C_FILE_MODE",         "")) , this.settingsG.AddText("x378 y223 c0x12abd1", "C file mode")
        this.cppFileMode       := this.settingsG.AddButton("x350 y255 w18 h18",  IniRead(GLOBAL_INI_FILE, "SETTINGS", "CPP_FILE_MODE",       "✔")), this.settingsG.AddText("x378 y255 c0x12abd1", "Cpp file mode")
        this.removeDbgSection  := this.settingsG.AddButton("x350 y287 w18 h18",  IniRead(GLOBAL_INI_FILE, "SETTINGS", "REMOVE_DBG_SECTION",  "")),  this.settingsG.AddText("x378 y287 c0x12abd1", "Remove dbg section")
        this.optimizeSizeMcode := this.settingsG.AddButton("x350 y319 w18 h18",  IniRead(GLOBAL_INI_FILE, "SETTINGS", "OPTIMIZE_SIZE_MCODE", "")),  this.settingsG.AddText("x378 y319 c0x12abd1", "Optimize Mcode size as much as possible")

        this.removeLastAlignment := this.settingsG.AddButton("x710 y221 w18 h18",  IniRead(GLOBAL_INI_FILE, "SETTINGS", "REMOVE_LAST_ALIGNMENT", "")), this.settingsG.AddText("x738 y221 c0x12abd1", "Remove last alignment")
        this.entryPoint          := this.settingsG.AddEdit("x845 y253 w66 h22   Background101010 c11b1a9 Center Number", IniRead(GLOBAL_INI_FILE, "SETTINGS", "ENTRY_POINT", 0x0)), this.settingsG.AddText("x710 y255 c0x12abd1", "Entry Point:")
        this.ignoreSections      := this.settingsG.AddEdit("x845 y285 w304 h24  Background101010 c11b1a9", IniRead(GLOBAL_INI_FILE, "SETTINGS", "IGNORE_SECTION", ".xdata|.pdata|.rdata$zzz")), this.settingsG.AddText("x710 y287 c0x12abd1", "Ignore Sections:")
        this.importDlls          := this.CreateRichEdit(this.settingsG, "Consolas", 11, "0x11b1a9", "0x101010", "x710 y351 w439 h224", Join(StrSplit(IniRead(GLOBAL_INI_FILE, "SETTINGS", "IMPORT_DLLS", GuiMcode.IMPORT_DLL), "|"), "`n"))

        this.settingsG.SetFont("s9", "Consolas")
        this.showTempDir    := this.settingsG.AddButton("x10 y5 h22", "Show temp dir")
        this.showSetPathGUI := this.settingsG.AddButton("x128 y5 h22", "Change paths")

        this.settingsG.AddText("x0   y175 w1159 h2   Background005343")
        this.settingsG.AddText("x330 y175 w2    h600 Background005343")
        this.settingsG.AddText("x700 y175 w2    h600 Background005343")
        this.settingsG.AddText("x866 y31  w2    h144 Background005343")

        this.ctrl.ClrBtn(this.showSetPathGUI,          "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: "0x2a2766"})
        this.ctrl.ClrBtn(this.showTempDir,             "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: "0x2a2766"})
        this.ctrl.ClrBtn(this.browseMSVCX64,           "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.browseMSVCX86,           "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.browseGCC,               "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.browseObjdump,           "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.displayObjdump,          "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.objdumpHighlighting,     "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.displayHexMcode,         "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.displayBase64Mcode,      "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.displayCompressMcode,    "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.displayFullOffsetTable,  "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.showCommentsOffsetTable, "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.cFileMode,               "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.cppFileMode,             "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.removeDbgSection,        "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.optimizeSizeMcode,       "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        this.ctrl.ClrBtn(this.removeLastAlignment,     "0x101010", "0x12abd1", "0x303030", 3, {HOT: "0x1f3a3a"})
        EditBorder(this.MSVCPathX64)
        EditBorder(this.MSVCPathX86)
        EditBorder(this.GCCPath)
        EditBorder(this.objdumpPath)
        EditBorder(this.entryPoint)
        EditBorder(this.ignoreSections)
        EditBorder(this.importDlls)
        EditBorder(this.multilineOutputLength)
    }


    CreateSetPathGUI() {
        this.pathG := Gui()
        this.pathG.BackColor := 0x060606
        CustomTitleBarWindow(this.pathG, "005343",,,,true)
        this.pathG.SetFont("s11", "Consolas")

        this.pathG.AddText("x10 y43  c0x12abd1", "Temp Dir:")
        this.pathG.AddText("x10 y77  c0x12abd1", "Settings ini:")
        this.pathG.AddText("x10 y111 c0x12abd1", "Output Dir:")
        this.setPathTempDir     := this.pathG.AddEdit("x121 y41  w720 h24 Background101010 c11b1a9", GLOBAL_WORKING_DIR)
        this.setPathSettingsIni := this.pathG.AddEdit("x121 y75  w720 h24 Background101010 c11b1a9", GLOBAL_INI_FILE)
        this.setPathOutputDir   := this.pathG.AddEdit("x121 y109 w720 h24 Background101010 c11b1a9", "This is not currently implemented...") ; GLOBAL_WORKING_OUTPUT_DIR
        this.pathG.AddText("x10 y145 c0xc44444", "IMPORTANT: If you change the paths, you need to close this window and restart the application for it to work correctly.").SetFont("s9")
        EditBorder(this.setPathTempDir)
        EditBorder(this.setPathSettingsIni)
        EditBorder(this.setPathOutputDir)
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

        this.ctrl.ClrBtn(this.displayAllCOFFInfo,        "0x0e2227", "0x00ccff", "0x000d13", 1, {HOT: 0x2a2766})
        this.ctrl.ClrBtn(this.copyMcodeHex,              "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a})
        this.ctrl.ClrBtn(this.waitSectionHexDumpBtn,     "0x141414", "0xa3bed1", "0x2c4e57", 3, {HOT: 0x1f3a3a}, true)
        this.ctrl.ClrDDL(this.waitSectionHexDump,        "0x141414", "0xa3bed1", "0x1f3a3a")
        EditBorder(this.copyMcodeRE)
        EditBorder(this.hexDumpRE)
        EditBorder(this.COFFinfoRE)

        IDE(this.hexDumpRE, RTF.HexDump)
        IDE(this.COFFinfoRE, RTF.CoffSyntax)
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
            IniWrite(this.objdumpFlags.Text,   GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_FLAGS")
            IniWrite(this.sourceFile.Text,     GLOBAL_INI_FILE, "SETTINGS", "SOURCE_FILE")
            IniWrite(this.flags.Text,          GLOBAL_INI_FILE, "SETTINGS", "FLAGS")
            ExitApp()
        })

        this.settings.OnEvent("Click",      (*) => this.settingsG.Show("w1159 h554"))
        this.copyMcodeFunc.OnEvent("Click", (*) => A_Clipboard := GLOBAL_MCODE_FUNC_FINAL)
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

        CopyFormatMcode(str) {
            if (this.HasOwnProp("cf")) {
                arch := this.cf.is64 ? 'x64 := "`n(`n' : 'x86 := "`n(`n'
                arch .= RegExReplace(str, "(.{" Integer(this.multilineOutputLength.Text) "})", "$1`n")
                return arch '`n)"'
            }
        }

        ;########################################################## settings ####################################################

        this.settingsG.OnEvent("Close", (*) {
            IniWrite(this.MSVCPathX64.Text, GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X64")
            IniWrite(this.MSVCPathX86.Text, GLOBAL_INI_FILE, "SETTINGS", "MSVC_PATH_X86")
            IniWrite(this.GCCPath.Text,     GLOBAL_INI_FILE, "SETTINGS", "GCC_PATH")
            IniWrite(this.objdumpPath.Text, GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_PATH")

            IniWrite(this.displayObjdump.Text          != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_OBJDUMP")
            IniWrite(this.objdumpHighlighting.Text     != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "OBJDUMP_HIGHLIGHTING")
            IniWrite(this.displayHexMcode.Text         != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_HEX_MCODE")
            IniWrite(this.displayBase64Mcode.Text      != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_BASE64_MCODE")
            IniWrite(this.displayCompressMcode.Text    != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_COMPRESS_MCODE")
            IniWrite(this.displayFullOffsetTable.Text  != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "DISPLAY_FULL_OFFSET_TABLE")
            IniWrite(this.showCommentsOffsetTable.Text != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "SHOW_COMMENTS_OFFSET_TABLE")
            IniWrite(this.multilineOutputLength.Text, GLOBAL_INI_FILE, "SETTINGS", "MULTILINE_OUTPUT_LENGTH")

            IniWrite(this.cFileMode.Text         != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "C_FILE_MODE")
            IniWrite(this.cppFileMode.Text       != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "CPP_FILE_MODE")
            IniWrite(this.removeDbgSection.Text  != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "REMOVE_DBG_SECTION")
            IniWrite(this.optimizeSizeMcode.Text != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "OPTIMIZE_SIZE_MCODE")

            IniWrite(this.removeLastAlignment.Text != "" ? "✔" : "", GLOBAL_INI_FILE, "SETTINGS", "REMOVE_LAST_ALIGNMENT")
            IniWrite(this.entryPoint.Text    , GLOBAL_INI_FILE, "SETTINGS", "ENTRY_POINT")
            IniWrite(this.ignoreSections.Text, GLOBAL_INI_FILE, "SETTINGS", "IGNORE_SECTION")
            IniWrite(Join(StrSplit(RegExReplace(this.importDlls.Text, "\R+", "`n"), "`n"), "|"), GLOBAL_INI_FILE, "SETTINGS", "IMPORT_DLLS")
        })

        this.showTempDir.OnEvent("Click",    (*) => Run(GLOBAL_WORKING_DIR))
        this.showSetPathGUI.OnEvent("Click", (*) => this.pathG.Show("w851 h146"))

        this.browseMSVCX64.OnEvent("Click", (*) => this.MSVCPathX64.Text    := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.MSVCPathX64.Text)
        this.browseMSVCX86.OnEvent("Click", (*) => this.MSVCPathX86.Text    := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.MSVCPathX86.Text)
        this.browseGCC.OnEvent("Click",     (*) => this.GCCPath.Text        := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.GCCPath.Text)
        this.browseObjdump.OnEvent("Click", (*) => this.objdumpPath.Text    := (sel := FileSelect(,,, "Exe File (*.exe)")) ? sel : this.objdumpPath.Text)

        this.displayObjdump.OnEvent("Click",          (*) => this.displayObjdump.Text          := this.displayObjdump.Text          ? "" : "✔")
        this.objdumpHighlighting.OnEvent("Click",     (*) => this.objdumpHighlighting.Text     := this.objdumpHighlighting.Text     ? "" : "✔")
        this.displayHexMcode.OnEvent("Click",         (*) => this.displayHexMcode.Text         := this.displayHexMcode.Text         ? "" : "✔")
        this.displayBase64Mcode.OnEvent("Click",      (*) => this.displayBase64Mcode.Text      := this.displayBase64Mcode.Text      ? "" : "✔")
        this.displayCompressMcode.OnEvent("Click",    (*) => this.displayCompressMcode.Text    := this.displayCompressMcode.Text    ? "" : "✔")
        this.displayFullOffsetTable.OnEvent("Click",  (*) => this.displayFullOffsetTable.Text  := this.displayFullOffsetTable.Text  ? "" : "✔")
        this.showCommentsOffsetTable.OnEvent("Click", (*) => this.showCommentsOffsetTable.Text := this.showCommentsOffsetTable.Text ? "" : "✔")
        this.cFileMode.OnEvent("Click",               (*) => (this.cFileMode.Text   := "✔", this.cppFileMode.Text := ""))
        this.cppFileMode.OnEvent("Click",             (*) => (this.cppFileMode.Text := "✔", this.cFileMode.Text := ""))
        this.removeDbgSection.OnEvent("Click",        (*) => this.removeDbgSection.Text    := this.removeDbgSection.Text    ? "" : "✔")
        this.optimizeSizeMcode.OnEvent("Click",       (*) => this.optimizeSizeMcode.Text   := this.optimizeSizeMcode.Text   ? "" : "✔")
        this.removeLastAlignment.OnEvent("Click",     (*) => this.removeLastAlignment.Text := this.removeLastAlignment.Text ? "" : "✔")

        ;####################################################### Path ###########################################################

        this.pathG.OnEvent("Close", (*) {
            RegWrite(this.setPathTempDir.Text,     "REG_SZ", "HKCU\Software\MCF", "TEMP_DIR")
            RegWrite(this.setPathSettingsIni.Text, "REG_SZ", "HKCU\Software\MCF", "TEMP_SETTINGS_INI")
            RegWrite(this.setPathOutputDir.Text,   "REG_SZ", "HKCU\Software\MCF", "TEMP_OUTPUT")
        })

        ;####################################################### COFF info ######################################################

        this.COFFG.OnEvent("Size", GuiReSizer)
        this.waitSectionHexDumpBtn.OnEvent("Click", (*) => SendMessage(0x014F, 1, 0, this.waitSectionHexDump))
        this.displayAllCOFFInfo.OnEvent("Click",    (*) {
            this.hexDumpRE.Text   := ""
            this.COFFinfoRE.Text  := ""
            this.copyMcodeRE.Text := ""
            if !(FileExist(Compiler.tempO)) {
                return RTF.ReplaceSel("The COFF file was not found. Generate the Mcode, and click on this button again, or drag the obj file into this window.", RTF.HexDump, this.hexDumpRE)
            }

            cf   := COFF(Compiler.tempO)
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
    }


    GenerateMcode(src) {
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
        set.GCCPath           := this.GCCPath.Text
        set.MSVCPath          := this.setModeDDL.Text == "MSVC x64" ? this.MSVCPathX64.Text : this.setModeDDL.Text == "MSVC x86" ? this.MSVCPathX86.Text : "unknown path (MSVC)"
        set.Use               := this.setModeDDL.Text == "GCC" ? "GCC" : "MSVC"
        set.disassemblerPath  := this.objdumpPath.Text
        compil                := Compiler(set)
        importDll             := StrSplit(RegExReplace(this.importDlls.Text, "\R+", "`n"), "`n")
        ignoreSec             := StrSplit(this.ignoreSections.Text, "|")
        fullOffsetTable       := this.displayFullOffsetTable.Text != "" ? true : false
        try ePoint            := Integer(this.entryPoint.Text)

        ; Если src это COFF (.o|.obj), то линковщик соберет Mcode без зависимостей от компилятора. COFF копируеться - задел на будущее...
        if (srcIsCOFF) {
            try FileCopy(src, GLOBAL_WORKING_DIR "\*.o", true)
            Objdump()
            Linker()
        } else { ; Если src это код, то сперва идет компиляция, а потом линковка...
            if (this.setModeDDL.Text == "GCC") {
                if (set.GCCPath != "" && !FileExist(set.GCCPath)) ; Проверка валидности GCC патча* (компилятора)
                    return this.Error_log("Invalid GCC path: " set.GCCPath "`n`nSpecify the absolute path to GCC [\bin\x86_64-w64-mingw32-gcc-10.3.0.exe], or do not specify a path at all (leave the input field empty); in which case the path from the environment variables will be used (PATH).")

                assemblingTime := QPC()
                er := compil.ObjGCC()
                if (er is Error)
                    return this.Error_log(er.Message)

                RTF.ReplaceSel("Compilation is completed in " QPC() - assemblingTime " milliseconds...`n", RTF.Log, this.warningRE,,, true)
                Objdump()
                Linker()
            } else {
                if (set.MSVCPath != "" && !FileExist(set.MSVCPath)) ; Проверка валидности MSVC патча* (компилятора)
                    return this.Error_log("Invalid MSVC path: " set.MSVCPath "`n`nSpecify the absolute path to MSVC [\VC\Auxiliary\Build\vcvars64.bat].")

                assemblingTime := QPC()
                er := compil.ObjGCC()
                if (er is Error)
                    return this.Error_log(er.Message)

                RTF.ReplaceSel("Compilation is completed in " QPC() - assemblingTime " milliseconds...`n", RTF.Log, this.warningRE,,, true)
                Objdump()
                Linker()
            }
        }


        ; Objdump не обязателен для работы кода. Это просто дополнение (дизассемблер) для удобства понимания того, как именно компилятор собирает код.
        ; В дальнейшем нужно доделать DumpBin (MSVC), а возможно лучше будет написать свой собственный дизассемблер на AHK, но это мутороное занятие...
        Objdump() {
            if (this.displayObjdump.Text) {
                objdumpTime := QPC()
                er := compil.ObjdumpGCC()
                if (er is Error) {
                    RTF.ReplaceSel("Invalid Objdump path: " this.objdumpPath.Text "`n`nSpecify the absolute path to Objdump [\bin\objdump.exe], or do not specify a path at all (leave the input field empty); in which case the path from the environment variables will be used (PATH).`n`n" er.Message, RTF.ErrorLog, this.objdumpRE)
                        this.waitSectionObjdump.Delete()
                        this.waitSectionObjdump.Add(["See the error below..."])
                } else {
                    this.objdump := Binary.ParseObjdumpToMap(FileRead(Compiler.tempAsm), &prop)
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

        Linker() {
            linkerTime := QPC()
            this.cf := COFF(Compiler.tempO, importDll, ignoreSec, fullOffsetTable, ePoint ?? 0)
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
            if (this.mcode.dbg) ; Отладочная информация
                RTF.ReplaceSel(this.mcode.dbg, RTF.ErrorLog, this.warningRE,,, true)
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
#Requires AutoHotkey v2.0

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
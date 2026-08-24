#Requires AutoHotkey v2.0

class __CustomListView extends Gui.ListView {
    class ListViewSubclass {
        HoverHeaderItem := -1 ; индекс колонки под мышью
        HoverLVItem     := -1 
        HoverLViSubItem := -1 
        IsMouseTracking := false 

        __New(LV, headerBkColor, gridColor, borderColor) {
            this.LV                  := LV

            this.realItemHeight := SendMessage(0x1033, 1, 0, this.LV.hwnd) >> 16 ; высота элементов LVM_GETITEMSPACING := 0x1033
            this.headerHeight   := 0
            if (!this.headerHeight) {
                headerRect := Buffer(16, 0)
                GetWindowRect(SendMessage(0x101F, 0, 0, this.LV.hwnd), headerRect) ; LVM_GETHEADER
                this.headerHeight := NumGet(headerRect, 12, "Int") - NumGet(headerRect, 4, "Int")
            }

            this.hHeader             := SendMessage(0x101F, 0, 0, this.LV.Hwnd) ; LVM_GETHEADER
            this.headerBkColor       := headerBkColor
            this.gridColor           := gridColor
            this.borderColor         := borderColor
            this.windowProcNewHeader := CallbackCreate(this.HeaderSubclassProc.Bind(this), "", 4)
            this.windowProcOldHeader := __CustomListView.SetWindowLong(this.hHeader, -4, this.windowProcNewHeader)
            this.windowProcNewLV     := CallbackCreate(this.ListViewSubclassProc.Bind(this), "", 4)
            this.windowProcOldLV     := __CustomListView.SetWindowLong(this.LV.hwnd, -4, this.windowProcNewLV)
        }


        GetColumnBoundaries(hHeader) {
            static HDM_GETITEMCOUNT := 0x1200, HDM_ORDERTOINDEX := 0x120F, HDM_GETITEMRECT := 0x1207
            boundaries := []
            loop (SendMessage(HDM_GETITEMCOUNT, 0, 0, hHeader)) { ; count
                index := SendMessage(HDM_ORDERTOINDEX, A_Index - 1, 0, hHeader)
                rect := Buffer(16, 0)
                SendMessage(HDM_GETITEMRECT, index, rect.Ptr, hHeader)
                boundaries.Push(NumGet(rect, 8, "Int") - 1) ; правая граница этой колонки (-1 что бы линии заголовка совпадали с нижними линиями)
            }
            return boundaries ; массив X-координат вертикальных линий, уже в порядке слева направо
        }


        GetRowBoundaries(hwnd) {
            static LVM_GETITEMRECT := 0x100E, LVM_GETTOPINDEX := 0x1027, LVM_GETCOUNTPERPAGE := 0x1028, LVM_GETITEMCOUNT := 0x1004, LVIR_BOUNDS := 0
            topIndex    := SendMessage(LVM_GETTOPINDEX, 0, 0, hwnd)
            perPage     := SendMessage(LVM_GETCOUNTPERPAGE, 0, 0, hwnd)
            total       := SendMessage(LVM_GETITEMCOUNT, 0, 0, hwnd)
            lastVisible := Min(topIndex + perPage, total - 1)
            boundaries  := []
            loop (lastVisible - topIndex + 1) {
                i := topIndex + A_Index - 1
                rect := Buffer(16, 0)
                NumPut("Int", LVIR_BOUNDS, rect, 0) ; обязательно перед вызовом
                SendMessage(LVM_GETITEMRECT, i, rect.Ptr, hwnd)
                boundaries.Push(NumGet(rect, 12, "Int")) ; bottom этой строки
            }

            if (boundaries.Length < perPage) { ; Если количесво элементов меньше чем в себя может вместить LV, то горизонтальные линии сетки все равно будет нарисована
                boundaries := []
                loop (perPage + 1) { ; +1 - это запас
                    boundaries.Push(A_Index * this.realItemHeight + (this.headerHeight - this.realItemHeight))
                }
            }
            return boundaries
        }


        GetHeaderOffsetX(hHeader, hLV) {
            pt := Buffer(8, 0) ; POINT {x, y}
            DllCall("MapWindowPoints", "Ptr", hHeader, "Ptr", hLV, "Ptr", pt, "UInt", 1, "Int")
            return NumGet(pt, 0, "Int")
        }


        ListViewSubclassProc(hwnd, uMsg, wParam, lParam) {
            if (uMsg == 0x000F) { ; WM_PAINT
                res := __CustomListView.CallWindowProc(this.windowProcOldLV, hwnd, uMsg, wParam, lParam)

                hdc    := __CustomListView.GetDC(hwnd)
                hPen   := __CustomListView.CreatePen(0, 1, this.gridColor) ; PS_SOLID
                oldPen := __CustomListView.SelectObject(hdc, hPen)

                clientRect := Buffer(16, 0)
                __CustomListView.GetClientRect(hwnd, clientRect)
                right  := NumGet(clientRect, 8,  "Int")
                bottom := NumGet(clientRect, 12, "Int")

                headerRect := Buffer(16, 0)
                __CustomListView.GetWindowRect(this.hHeader, headerRect)
                headerHeight := NumGet(headerRect, 12, "Int") - NumGet(headerRect, 4, "Int")

                for y in this.GetRowBoundaries(hwnd) {
                    if (y > headerHeight) { ; рисование ниже заголовка
                        __CustomListView.MoveToEx(hdc, 0, y, 0)
                        __CustomListView.LineTo(hdc, right, y)
                    }
                }

                ; вертикальные линии начинай от headerHeight, а не от 0:
                offsetX := this.GetHeaderOffsetX(this.hHeader, hwnd)
                for x in this.GetColumnBoundaries(this.hHeader) {
                    realX := x + offsetX
                    __CustomListView.MoveToEx(hdc, realX, headerHeight, 0) ; то же ниже заголовка
                    __CustomListView.LineTo(hdc, realX, bottom)
                }

                __CustomListView.SelectObject(hdc, oldPen)
                __CustomListView.DeleteObject(hPen)
                __CustomListView.ReleaseDC(hwnd, hdc)

                return res
            }

            ; if (uMsg == 0x0083) {
            ;     style := __CustomListView.GetWindowLong(hwnd, -16) ; GWL_STYLE = -16
            ;     if (style & 0x00100000) { ; WS_HSCROLL = 0x00100000
            ;     __CustomListView.SetWindowLong(hwnd, -16, style & ~0x00100000)
            ;     }
            ; }

            ; else if (uMsg == 0x007C) {
            ;     if (wParam == -16) { ; GWL_STYLE
            ;         styleNew := NumGet(lParam, 4, "UInt") ; STYLESTRUCT
            ;         if (styleNew & 0x00100000) {
            ;             NumPut("UInt", styleNew & ~0x00100000, lParam, 4) ; del WS_HSCROLL
            ;         }
            ;     }
            ; }

            if (uMsg == 0x0085) { ; WM_NCPAINT
                res := __CustomListView.CallWindowProc(this.windowProcOldLV, hwnd, uMsg, wParam, lParam)
                hdc  := __CustomListView.GetWindowDC(hwnd)
                rect := Buffer(16)
                __CustomListView.GetWindowRect(hwnd, rect)
                width  := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
                height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")

                hBrush   := __CustomListView.GetStockObject(5)
                hPen     := __CustomListView.CreatePen(0, 3, this.borderColor)
                oldBrush := __CustomListView.SelectObject(hdc, hBrush)
                oldPen   := __CustomListView.SelectObject(hdc, hPen)

                __CustomListView.Rectangle(hdc, 0, 0, width, height)
                __CustomListView.SelectObject(hdc, oldBrush)
                __CustomListView.SelectObject(hdc, oldPen)
                __CustomListView.DeleteObject(hPen)
                __CustomListView.ReleaseDC(hwnd, hdc)
                return res
            }

            if (uMsg == 0x0200) { ; WM_MOUSEMOVE
                x := lParam << 48 >> 48
                y := lParam << 32 >> 48
                NumPut("Int", x, "Int", y, HitTest := Buffer(20, 0)) ; LVHITTESTINFO

                SendMessage(0x1039, 0, HitTest.Ptr, hwnd) ; LVM_SUBITEMHITTEST = 0x1039
                flags    := NumGet(HitTest, 8, "UInt")
                iItem    := NumGet(HitTest, 12, "Int")
                iSubItem := NumGet(HitTest, 16, "Int")
                
                if (this.HoverLVItem != iItem || this.HoverLViSubItem != iSubItem) {
                    this.HoverLVItem     := iItem
                    this.HoverLViSubItem := iSubItem
                    __CustomListView.InvalidateRect(hwnd, 0, 0) ; Форсируем CustomDraw
                    
                    static TME := Buffer(8 + A_PtrSize + 4, 0)
                    NumPut("UInt", TME.Size, "UInt", 2, "Ptr", hwnd, TME)
                    DllCall("TrackMouseEvent", "Ptr", TME)
                }
            }
            else if (uMsg == 0x02A3) { ; WM_MOUSELEAVE
                if (this.HoverLVItem != -1) {
                    this.HoverLVItem := -1
                    __CustomListView.InvalidateRect(hwnd, 0, 0)
                }
            }

            if (uMsg == 0x020A || uMsg == 0x0115 || (uMsg == 0x0100 && wParam >= 0x21 && wParam <= 0x28)) { ; 0x0115 = WM_VSCROLL, 0x020A = WM_MOUSEWHEEL, VK_PRIOR..VK_DOWN
                ; res := __CustomListView.CallWindowProc(this.windowProcOldLV, hwnd, uMsg, wParam, lParam)
                ; Critical(-1)
                __CustomListView.InvalidateRect(hwnd, 0, 0) ; крч это фиксит баг с лишней линией в заголовке LV, я хз как это по нормальному реализовать, но вроде это работает
                ; return res
            }

            if (uMsg == 0x0114 || (uMsg == 0x0100 && wParam >= 0x21 && wParam <= 0x28)) { ; 0x0114 = WM_HSCROLL, VK_PRIOR..VK_DOWN
                res := __CustomListView.CallWindowProc(this.windowProcOldLV, hwnd, uMsg, wParam, lParam)
                __CustomListView.InvalidateRect(hwnd, 0, 0)
                return res
            }

            return __CustomListView.CallWindowProc(this.windowProcOldLV, hwnd, uMsg, wParam, lParam)
        }


        HeaderSubclassProc(hwnd, uMsg, wParam, lParam) {
            if (uMsg == 0x000F) { ; WM_PAINT
                res := __CustomListView.CallWindowProc(this.windowProcOldHeader, hwnd, uMsg, wParam, lParam)
                
                ; рисуем пустую область поверх
                hdc := __CustomListView.GetDC(hwnd)
                rect := Buffer(16, 0)
                __CustomListView.GetClientRect(hwnd, rect)
                
                ; где заканчивается последняя колонка
                count := SendMessage(0x1200, 0, 0, hwnd) ; HDM_GETITEMCOUNT
                if (count > 0) {
                    lastIndex := SendMessage(0x120F, count - 1, 0, hwnd) ; HDM_ORDERTOINDEX(order = count-1) реальный index
                    itemRect := Buffer(16, 0)
                    SendMessage(0x1207, lastIndex, itemRect, hwnd) ; HDM_GETITEMRECT
                    lastRight := NumGet(itemRect, 8, "Int")
                    NumPut("Int", lastRight, rect, 0) ; Смещаем левую границу заливки к концу последней колонки
                }
                
                ; Если пустое место реально есть (левая граница меньше правой)
                if (NumGet(rect, 0, "Int") < NumGet(rect, 8, "Int")) {
                    hBrush := __CustomListView.CreateSolidBrush(this.headerBkColor)
                    __CustomListView.FillRect(hdc, rect, hBrush)
                    __CustomListView.DeleteObject(hBrush)
                }
                __CustomListView.ReleaseDC(hwnd, hdc)

                return res
            }

            if (uMsg == 0x0200) { ; WM_MOUSEMOVE
                x := lParam << 48 >> 48
                y := lParam << 32 >> 48
                NumPut("Int", x, "Int", y, HitTest := Buffer(16, 0))
                
                SendMessage(0x1206, 0, HitTest, hwnd) ; HDM_HITTEST
                flags   := NumGet(HitTest, 8, "UInt")
                item    := NumGet(HitTest, 12, "Int")
                newItem := (flags & 0x0002) ? item : -1 ; (HHT_ONHEADER) - мышь на самом тексте/фоне заголовка. Если мышь на разделителе (ресайз), флаг будет другим.
                
                if (this.HoverHeaderItem != newItem) {
                    this.HoverHeaderItem := newItem
                    __CustomListView.InvalidateRect(hwnd, 0, 0)
                    static TME := Buffer(8 + A_PtrSize + 4, 0)
                    NumPut("UInt", TME.Size, "UInt", 2, "Ptr", hwnd, TME) ; (TME_LEAVE = 2)
                    __CustomListView.TrackMouseEvent(TME)
                }
            }
            else if (uMsg == 0x02A3) { ; WM_MOUSELEAVE
                if (this.HoverHeaderItem != -1) {
                    this.HoverHeaderItem := -1
                    __CustomListView.InvalidateRect(hwnd, 0, 0)
                }
            }

            return __CustomListView.CallWindowProc(this.windowProcOldHeader, hwnd, uMsg, wParam, lParam)
        }
    }

    static CDDS_POSTERASE     := 0x00000004
    static CDDS_POSTPAINT     := 0x00000002
    static CDDS_PREERASE      := 0x00000003
    static CDDS_PREPAINT      := 0x00000001
    static CDDS_ITEM          := 0x00010000
    static CDDS_ITEMPOSTERASE := this.CDDS_ITEM | this.CDDS_POSTERASE
    static CDDS_ITEMPOSTPAINT := this.CDDS_ITEM | this.CDDS_POSTPAINT
    static CDDS_ITEMPREERASE  := this.CDDS_ITEM | this.CDDS_PREERASE
    static CDDS_ITEMPREPAINT  := this.CDDS_ITEM | this.CDDS_PREPAINT
    static CDDS_SUBITEM       := 0x00020000

    static CDRF_DODEFAULT         := 0x00000000
    static CDRF_NEWFONT           := 0x00000002
    static CDRF_SKIPDEFAULT       := 0x00000004
    static CDRF_DOERASE           := 0x00000008
    static CDRF_NOTIFYPOSTPAINT   := 0x00000010
    static CDRF_NOTIFYITEMDRAW    := 0x00000020
    static CDRF_NOTIFYSUBITEMDRAW := 0x00000020
    static CDRF_NOTIFYPOSTERASE   := 0x00000040
    static CDRF_SKIPPOSTPAINT     := 0x00000100

    static LVM_GETHEADER := 0x101F
    static NM_CUSTOMDRAW := -12
    static WM_NOTIFY     := 0x4E

    static CDIS_SELECTED := 0x0001
    static CDIS_HOT      := 0x0040

    static uniqueHwnd := Map()

    static __New() => super.Prototype.SetTheme := this.SetTheme.Bind(this)


    static SetTheme(LV, headerBkColor := "0x238f35", headerTextColor := "0xffffff", hoverHeader := {SELECTED: "", HOT: ""}, lvBkColor := "0x101010", lvTextColor := "0x00ccff", gridColor := "0xFF0000", hoverLV := {SELECTED: "", HOT: ""}, borderColor := "0x303030") {
        hHeader := SendMessage(this.LVM_GETHEADER, 0, 0, LV.hwnd)
        if (!this.uniqueHwnd.Has(hHeader)) {
            LV.Opt("Background" headerBkColor " +LV" 0x10000) ; LVS_EX_DOUBLEBUFFER
            this.SetWindowTheme(hHeader, "DarkMode_ItemsView")
            this.SetWindowTheme(lv.Hwnd, "DarkMode_Explorer")
            this.uniqueHwnd[hHeader] := {subclass: __CustomListView.ListViewSubclass(LV, headerBkColor, gridColor, borderColor)}
            LV.OnNotify(this.NM_CUSTOMDRAW, (gCtrl, lParam)           => this.ListViewCustomDraw(gCtrl, lParam))
            LV.OnMessage(this.WM_NOTIFY, (gCtrl, wParam, lParam, Msg) => this.HeaderCustomDraw(hHeader, wParam, lParam, Msg))
        }

        this.uniqueHwnd[hHeader].headerBkColor     := headerBkColor
        this.uniqueHwnd[hHeader].headerTextColor   := headerTextColor
        this.uniqueHwnd[hHeader].hoverHeaderSelect := hoverHeader.SELECTED
        this.uniqueHwnd[hHeader].hoverHeaderHot    := hoverHeader.HOT
        this.uniqueHwnd[hHeader].lvBkColor         := lvBkColor
        this.uniqueHwnd[hHeader].lvTextColor       := lvTextColor
        this.uniqueHwnd[hHeader].gridColor         := gridColor
        this.uniqueHwnd[hHeader].hoverLVSelect     := hoverLV.SELECTED
        this.uniqueHwnd[hHeader].hoverLVHot        := hoverLV.HOT
    }


    static ListViewCustomDraw(gCtrl, lParam) {
        static o     := this.NMLVCUSTOMDRAW()
        dwDrawStage  := NumGet(lParam, o.nmcd.dwDrawStage,  "UInt")
        switch (dwDrawStage) {
            case this.CDDS_PREPAINT:
                return this.CDRF_NOTIFYITEMDRAW | this.CDRF_NOTIFYSUBITEMDRAW

            case this.CDDS_ITEMPREPAINT:
                return this.CDRF_NOTIFYSUBITEMDRAW

            case this.CDDS_SUBITEM | this.CDDS_ITEMPREPAINT:
                dwItemSpec := NumGet(lParam, o.nmcd.dwItemSpec,   "Ptr")
                uItemState := NumGet(lParam, o.nmcd.uItemState,   "UInt")
                iSubItem   := NumGet(lParam, o.iSubItem,          "Int")
                hHeader    := SendMessage(this.LVM_GETHEADER, 0, 0, gCtrl.hwnd)
                info       := this.uniqueHwnd.Get(hHeader, 0)
                if (!info)
                    return this.CDRF_DODEFAULT

                realState := SendMessage(0x102C, dwItemSpec, 0x0002, gCtrl.hwnd) ; LVM_GETITEMSTATE = 0x102C, LVIS_SELECTED = 0x0002
                ; isSelected := (realState & 2 && dwItemSpec == this.subclass.HoverLVItem && iSubItem == this.subclass.HoverLViSubItem)
                isSelected := (realState & 2)
                isHovered  := (dwItemSpec == info.subclass.HoverLVItem && iSubItem == info.subclass.HoverLViSubItem)
            
                bkColor := info.lvBkColor
                if (isSelected)
                    bkColor := info.hoverLVSelect != "" ? info.hoverLVSelect : this.BrightenColor(bkColor, -40)
                else if (isHovered)
                    bkColor := info.hoverLVHot != "" ? info.hoverLVHot : this.BrightenColor(bkColor, 40)

                NumPut("UInt", uItemState & ~0x0001 & ~0x0010, lParam, o.nmcd.uItemState) ; убиает синею рамку выделения CDIS_SELECTED (0x0001) и CDIS_FOCUS (0x0010)
                NumPut("UInt", this.RGBtoBGR(info.lvTextColor ?? 0), lParam, o.clrText)
                NumPut("UInt", this.RGBtoBGR(bkColor          ?? 0), lParam, o.clrTextBk)
                return this.CDRF_NEWFONT | this.CDRF_NOTIFYPOSTPAINT
        }
        return this.CDRF_DODEFAULT
    }


    static HeaderCustomDraw(hHeader, wParam, lParam, Msg) {
        static o := this.NMLVCUSTOMDRAW()
        code         := NumGet(lParam, o.nmcd.hdr.code,    "Int")
        hwndFrom     := NumGet(lParam, o.nmcd.hdr.hwndFrom,"Ptr")
        dwDrawStage  := NumGet(lParam, o.nmcd.dwDrawStage, "UInt")
        info         := this.uniqueHwnd.Get(hwndFrom, 0)

        if (code != this.NM_CUSTOMDRAW || hwndFrom != hHeader)
            return
        if (dwDrawStage == this.CDDS_PREPAINT)
            return this.CDRF_NOTIFYITEMDRAW
        if (!info)
            return this.CDRF_DODEFAULT

        code         := NumGet(lParam, o.nmcd.hdr.code,   "Int")
        hdc          := NumGet(lParam, o.nmcd.hdc,        "Ptr")
        dwItemSpec   := NumGet(lParam, o.nmcd.dwItemSpec, "Ptr")
        uItemState   := NumGet(lParam, o.nmcd.uItemState, "UInt")
        rcLeft       := NumGet(lParam, o.nmcd.rc.left,    "Int")
        rcTop        := NumGet(lParam, o.nmcd.rc.top,     "Int")
        rcRight      := NumGet(lParam, o.nmcd.rc.right,   "Int")
        rcBottom     := NumGet(lParam, o.nmcd.rc.bottom,  "Int")

        bkColor := info.headerBkColor
        if (uItemState & this.CDIS_SELECTED)
            bkColor := info.hoverHeaderSelect != "" ? info.hoverHeaderSelect : this.BrightenColor(bkColor, -20)
        ; else if (uItemState & this.CDIS_HOT) ; Это так не работает
        ;     bkColor := info.hoverHeaderHot != "" ? info.hoverHeaderHot : this.BrightenColor(bkColor, 20)
        else if (dwItemSpec == info.subclass.HoverHeaderItem)
            bkColor := info.hoverHeaderHot != "" ? info.hoverHeaderHot : this.BrightenColor(bkColor, 20)

        ; Draw BK
        this.SetBkMode(hdc, 1)
        this.SetDCBrushColor(hdc, bkColor)
        this.SelectObject(hdc, bru := this.GetStockObject(18))
        this.SelectObject(hdc, this.GetStockObject(19))
        this.FillRect(hdc, lParam + o.nmcd.rc.left, bru)

        ; Draw separator
        this.SetDCBrushColor(hdc, info.gridColor)
        lineRect := Buffer(16, 0)
        NumPut("Int", rcRight -1, "Int", rcTop, "Int", rcRight, "Int", rcBottom, lineRect)
        this.FillRect(hdc, lineRect, bru)

        ; Draw Text
        colInfo := this.GetHeaderInfo(hHeader, dwItemSpec)
        this.SetTextColor(hdc, info.headerTextColor)
        if (colInfo.align == 0) { ; HDF_LEFT
            aligRect := Buffer(16, 0)
            NumPut("Int", rcLeft + 6 , "Int", rcTop, "Int", rcRight, "Int", rcBottom, aligRect) ; выравнивание что бы было красиво
            this.DrawText(hdc, colInfo.text, -1, aligRect, 0x8024 | colInfo.align) ; DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS
        } else this.DrawText(hdc, colInfo.text, -1, lParam + o.nmcd.rc.left, 0x8024 | colInfo.align)

        return this.CDRF_SKIPDEFAULT
    }


    static GetHeaderInfo(hHeader, index) {
        static HDI_TEXT := 2, HDI_FORMAT := 4
        hditem  := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
        textBuf := Buffer(512, 0)
        
        NumPut("UInt", HDI_TEXT | HDI_FORMAT, hditem, 0)
        NumPut("Ptr", textBuf.Ptr, hditem, 8)
        NumPut("Int", 256, hditem, 8 + A_PtrSize * 2) ; cchTextMax
        
        SendMessage(0x120B, index, hditem.Ptr, hHeader) ; HDM_GETITEMW

        fmt := NumGet(hditem, 8 + A_PtrSize * 2 + 4, "Int")
        alignFlag := fmt & 0x03 ; (HDF_LEFT=0, HDF_RIGHT=1, HDF_CENTER=2)
        dtAlign := (alignFlag == 0) ? 0x0 : (alignFlag == 2) ? 0x1 : 0x2 ; Для DrawText
        return {text: StrGet(textBuf, "UTF-16"), align: dtAlign}
    }


    static NMLVCUSTOMDRAW() {
        static p := A_PtrSize
        return {
            nmcd: {hdr: {hwndFrom: 0, idFrom: p=8 ? 8 : 4, code: p=8 ? 16 : 8}, ; NMHDR
                   dwDrawStage: p=8 ? 24 : 12, hdc: p=8 ? 32 : 16,
                   rc: {left: p=8 ? 40 : 20, top: p=8 ? 44 : 24, right: p=8 ? 48 : 28, bottom: p=8 ? 52 : 32}, ; RECT
                   dwItemSpec: p=8 ? 56 : 36, uItemState: p=8 ? 64 : 40, lItemlParam: p=8 ? 72 : 44,
                    },
            clrText: p=8 ? 80 : 48, clrTextBk: p=8 ? 84 : 52, iSubItem: p=8 ? 88 : 56, dwItemType: p=8 ? 92 : 60,
            clrFace: p=8 ? 96 : 64, iIconEffect: p=8 ? 100 : 68, iIconPhase: p=8 ? 104 : 72, iPartId: p=8 ? 108 : 76, iStateId: p=8 ? 112 : 80,
            rcText: {left: p=8 ? 116 : 84, top: p=8 ? 120 : 88, right: p=8 ? 124 : 92, bottom: p=8 ? 128 : 96}, ; RECT
            uAlign: p=8 ? 132 : 100
        }
    }

    static RGB(R, G, B) => ((R << 16) | (G << 8) | B)

    static BrightenColor(clr, perc := 5) => ((p := perc / 100 + 1), this.RGB(Round(Min(255, (clr >> 16 & 0xFF) * p)), Round(Min(255, (clr >> 8 & 0xFF) * p)), Round(Min(255, (clr & 0xFF) * p))))

    static RgbToBgr(rgbColor) => ((rgbColor & 0xFF) << 16) | (((rgbColor >> 8) & 0xFF) << 8) | ((rgbColor >> 16) & 0xFF)

    static GetClientRect(hHeader, rect) => DllCall("GetClientRect", "Ptr", hHeader, "Ptr", rect, "Int")

    static SetWindowTheme(hwnd, pszSubAppName, pszSubIdList := 0) => DllCall("UxTheme\SetWindowTheme", "Ptr", hwnd, "Ptr", StrPtr(pszSubAppName), "Ptr", pszSubIdList, "Int")

    static FillRect(hDC, lprc, hbr) => DllCall("User32\FillRect", "Ptr", hDC, "Ptr", lprc, "Ptr", hbr, "Int")

    static CreateSolidBrush(color) => DllCall("CreateSolidBrush", "UInt", this.RgbToBgr(color), "Ptr")

    static SetBkMode(hdc, iBkMode) => DllCall("Gdi32\SetBkMode", "Ptr", hdc, "Int", iBkMode, "Int")

    static SetDCBrushColor(hdc, crColor) => DllCall("Gdi32\SetDCBrushColor", "Ptr", hdc, "UInt", this.RgbToBgr(crColor), "UInt")

    static SelectObject(hdc, hgdiobj) => DllCall("Gdi32\SelectObject", "Ptr", hdc, "Ptr", hgdiobj, "Ptr")

    static GetStockObject(fnObject) => DllCall("Gdi32\GetStockObject", "Int", fnObject, "Ptr")

    static DeleteObject(hObject) => DllCall("Gdi32\DeleteObject", "Ptr", hObject, "Int")

    static CreatePen(fnPenStyle, nWidth, crColor) => DllCall("Gdi32\CreatePen", "Int", fnPenStyle, "Int", nWidth, "UInt", this.RgbToBgr(crColor), "Ptr")

    static Rectangle(hdc, nLeftRect, nTopRect, nRightRect, nBottomRect) => DllCall("Gdi32\Rectangle", "Ptr", hdc, "Int", nLeftRect, "Int", nTopRect, "Int", nRightRect, "Int", nBottomRect, "Int")

    static SetTextColor(hdc, crColor) => DllCall("Gdi32\SetTextColor", "Ptr", hdc, "UInt", this.RgbToBgr(crColor), "UInt")

    static DrawText(hDC, lpchText, nCount, lpRect, uFormat) => DllCall("User32\DrawText", "Ptr", hDC, "Ptr", StrPtr(lpchText), "Int", nCount, "Ptr", lpRect, "UInt", uFormat, "Int")

    static GetDC(hWnd) => DllCall("GetDC", "Ptr", hWnd, "Ptr")

    static GetWindowDC(hWnd) => DllCall("GetWindowDC", "Ptr", hWnd, "Ptr")

    static ReleaseDC(hWnd, hDC) => DllCall("ReleaseDC", "Ptr", hWnd, "Ptr", hDC)

    static GetWindowLong(hWnd, nIndex) => DllCall(A_PtrSize == 8 ? "GetWindowLongPtr" : "GetWindowLong", "Ptr", hwnd, "Int", nIndex, "Ptr")

    static SetWindowLong(hWnd, nIndex, dwNewLong) => DllCall(A_PtrSize = 8 ? "SetWindowLongPtr" : "SetWindowLong", "Ptr", hWnd, "Int", nIndex, "Ptr", dwNewLong, "Ptr")

    static CallWindowProc(lpPrevWndFunc, hWnd, Msg, wParam, lParam) => DllCall("CallWindowProc", "Ptr", lpPrevWndFunc, "Ptr", hWnd, "UInt", Msg, "Ptr", wParam, "Ptr", lParam)

    static InvalidateRect(hWnd, lpRect, bErase) => DllCall("InvalidateRect", "Ptr", hwnd, "Ptr", lpRect, "Int", bErase)

    static TrackMouseEvent(lpEventTrack) => DllCall("TrackMouseEvent", "Ptr", lpEventTrack)

    static MoveToEx(hdc, x, y, lppt) => DllCall("MoveToEx", "Ptr", hdc, "Int", x, "Int", y, "Ptr", lppt)

    static LineTo(hdc, x, y) => DllCall("LineTo", "Ptr", hdc, "Int", x, "Int", y)

    static GetWindowRect(hWnd, lpRect) => DllCall("GetWindowRect", "Ptr", hWnd, "Ptr", lpRect)
}
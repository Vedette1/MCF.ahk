#include "ctrl.h"
#include <Windows.h>
#include <commctrl.h>


static unsigned int BrightenColor(unsigned int clr, double perc) {
    double p = perc / 100.0 + 1.0;

    double r = (clr >> 16 & 0xFF) * p;
    double g = (clr >>  8 & 0xFF) * p;
    double b = (clr       & 0xFF) * p;

    r = r > 255.0 ? 255.0 : r;
    g = g > 255.0 ? 255.0 : g;
    b = b > 255.0 ? 255.0 : b;

    unsigned int ri = (unsigned int)(r + 0.5);
    unsigned int gi = (unsigned int)(g + 0.5);
    unsigned int bi = (unsigned int)(b + 0.5);

    return (ri << 16) | (gi << 8) | bi;
}


LRESULT CALLBACK CustomButtonProc(HWND hwnd, LPARAM lParam, ButtonConfig* config) {
    if (LPNMHDR(lParam)->code != NM_CUSTOMDRAW) {
        return 0;
    }

    NMCUSTOMDRAW* cDraw = (NMCUSTOMDRAW*)lParam;
    HDC hdc = cDraw->hdc;
    RECT rc = cDraw->rc;
    int brushColor = config->backgroundСolor;
    static bool first = false;

    if (cDraw->uItemState & CDIS_DISABLED) {
        brushColor = config->hover.DISABLED != -1 ? config->hover.DISABLED : BrightenColor(brushColor, -20);
    } else if (cDraw->uItemState & CDIS_SELECTED || GetKeyState(VK_LBUTTON) & 0x8000 && first) {
        brushColor = config->hover.SELECTED != -1 ? config->hover.SELECTED : BrightenColor(brushColor, -10); first = false;
    } else if (cDraw->uItemState & CDIS_HOT) {
        brushColor = config->hover.HOT != -1 ? config->hover.HOT : BrightenColor(brushColor, 20);
    }


    SetBkMode(hdc, TRANSPARENT); // Draw Background.
    SetDCBrushColor(hdc, brushColor);
    HGDIOBJ hbr = GetStockObject(DC_BRUSH);
    SelectObject(hdc, hbr);
    SelectObject(hdc, GetStockObject(DC_PEN));
    FillRect(hdc, &rc, (HBRUSH)hbr);


    if (config->borderColor != -1 && config->borderWidth != -1) { // Draw Border
        HPEN hPen = CreatePen(PS_SOLID, config->borderWidth, config->borderColor);
        HGDIOBJ oldPen = SelectObject(hdc, hPen);
        SelectObject(hdc, GetStockObject(NULL_BRUSH));
        Rectangle(hdc, rc.left, rc.top, rc.right, rc.bottom);
        SelectObject(hdc, oldPen);
        DeleteObject(hPen);
    }


    if (config->textColor != -1) { // Draw Text
        LONG style  = GetWindowLongW(hwnd, GWL_STYLE) & 0x300;
        int dtFlags = DT_WORDBREAK | ((style == 0x100) ? DT_LEFT : (style == 0x200) ? DT_RIGHT : DT_CENTER);
        wchar_t buffer[256];
        GetWindowTextW(hwnd, buffer, 256);

        if (config->ddlMode == true) {
            RECT defText = rc;
            int width    = rc.right - rc.left;

            SetTextColor(hdc, config->textColor);
            defText.left  = 4;
            defText.right = width - 20;
            DrawTextW(hdc, buffer, -1, &defText, DT_VCENTER | DT_SINGLELINE);

            HFONT hFont     = CreateFontW(18, 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 0, 0, L"Arial");
            HGDIOBJ oldFont = SelectObject(hdc, hFont);
            SetTextColor(hdc, 0xb9b9b9);
            rc.left = width - 14;
            rc.top  = -2;

            DrawTextW(hdc, L"⌵", -1, &rc, DT_VCENTER | DT_SINGLELINE);
            SelectObject(hdc, oldFont);
            DeleteObject(hFont);
        } else {
            RECT rcText = rc, rcCalc = rc;
            int textHeight = DrawTextW(hdc, buffer, -1, &rcCalc, dtFlags | DT_CALCRECT);
            int btnHeight  = rcText.bottom - rcText.top;
            
            if (textHeight < btnHeight) {
                int offset    = (btnHeight - textHeight) / 2;
                rcText.top    += offset;
                rcText.bottom -= offset;
            }
            
            SetTextColor(hdc, config->textColor);
            DrawTextW(hdc, buffer, -1, &rcText, dtFlags);
        }
        return CDRF_SKIPDEFAULT;
    }

    return 1; // Если цвет текста не задан, его рисует винда
}
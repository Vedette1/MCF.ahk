#include "ctrl.h"
#include <Windows.h>
#include <commctrl.h>
#include <uxtheme.h>

int CALLBACK CustomDDLProcA(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, DDLConfig* config) {
    if (msg != WM_DRAWITEM) {
        return 0;
    }

    DRAWITEMSTRUCT* draw = (DRAWITEMSTRUCT*)lParam;
    if (draw->CtlType != ODT_COMBOBOX) {
        return 0;
    }

    int currentBgColor   = (draw->itemState & ODS_SELECTED) ? config->highlightColor : config->backgroundСolor;
    HDC hdc              = draw->hDC;
    RECT rc              = draw->rcItem;

    SetDCBrushColor(hdc, currentBgColor);
    HGDIOBJ hBru = GetStockObject(DC_BRUSH);
    SelectObject(hdc, hBru);
    FillRect(hdc, &rc, (HBRUSH)hBru);

    if (draw->itemID != -1) {
        wchar_t buffer[1024];
        SendMessageW(draw->hwndItem, draw->CtlType == 2 ? 0x0189 : 0x0148, draw->itemID, (LPARAM)buffer);
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, config->textColor);
        rc.left += 4;
        DrawTextW(hdc, buffer, -1, &rc, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    }

    return TRUE;
}


// Слишкмо сложно, и не рационально рисовать ComboBox с нуля, ибо нет анимаций.

// struct DDL_List_Config {
//     struct DDL_ComboBox_Config {
//         COLORREF backgroundСolor;
//         COLORREF borderColor;
//         int borderWidth;
//         COLORREF textColor;
//     };
//     COLORREF backgroundСolor;
//     COLORREF textColor;
//     COLORREF highlightColor;
//     DDL_ComboBox_Config ComboBox;
// };


// LRESULT CALLBACK CustomDDLProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam, UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
//     DDL_List_Config* config = (DDL_List_Config*)dwRefData;

//     switch (uMsg) {
//         case WM_PAINT: {
//             PAINTSTRUCT ps; RECT rc;

//             HDC hdc = BeginPaint(hwnd, &ps);
//             GetWindowRect(hwnd, &rc);
//             MapWindowPoints(NULL, hwnd, (LPPOINT)&rc, 2); // локальные координаты

//             SetDCBrushColor(hdc, config->ComboBox.backgroundСolor);
//             HGDIOBJ hBru = GetStockObject(DC_BRUSH);
//             SelectObject(hdc, hBru);
//             FillRect(hdc, &rc, (HBRUSH)hBru);


//             if (config->ComboBox.borderColor != -1 && config->ComboBox.borderWidth != -1) {
//                 HPEN hPen = CreatePen(PS_SOLID, config->ComboBox.borderWidth, config->ComboBox.borderColor);
//                 HGDIOBJ oldPen = SelectObject(hdc, hPen);
//                 Rectangle(hdc, rc.left, rc.top, rc.right, rc.bottom);
//                 SelectObject(hdc, oldPen);
//                 DeleteObject(hPen);
//             }

//             wchar_t buffer[1024];
//             GetWindowTextW(hwnd, buffer, 1024);
//             HFONT hFont = (HFONT)SendMessageW(hwnd, WM_GETFONT, 0, 0);
//             if (!hFont) hFont = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
//             HGDIOBJ hOldFont = SelectObject(hdc, hFont);

//             RECT rcText = rc, rcCalc = rc;
//             int textHeight = DrawTextW(hdc, buffer, -1, &rcCalc, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_CALCRECT);
//             int btnHeight  = rcText.bottom - rcText.top;
            
//             if (textHeight < btnHeight) {
//                 int offset    = (btnHeight - textHeight) / 2;
//                 rcText.top    += offset;
//                 rcText.bottom -= offset;
//             }
            
//             SetBkMode(hdc, TRANSPARENT);
//             SetTextColor(hdc, config->ComboBox.textColor);
//             rcText.left += 4;
//             DrawTextW(hdc, buffer, -1, &rcText, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
//             SelectObject(hdc, hOldFont);

//             EndPaint(hwnd, &ps);
//             return 0;
//         }

//         case WM_ERASEBKGND: {
//             return 1;
//         }

//         case WM_DRAWITEM: {
//             DRAWITEMSTRUCT* draw = (DRAWITEMSTRUCT*)lParam;
//             int currentBgColor   = (draw->itemState & ODS_SELECTED) ? config->highlightColor : config->backgroundСolor;
//             HDC hdc              = draw->hDC;
//             RECT rc              = draw->rcItem;

//             SetDCBrushColor(hdc, currentBgColor);
//             HGDIOBJ hBru = GetStockObject(DC_BRUSH);
//             SelectObject(hdc, hBru);
//             FillRect(hdc, &rc, (HBRUSH)hBru);

//             if (draw->itemID != -1) {
//                 wchar_t buffer[1024];
//                 SendMessageW(draw->hwndItem, draw->CtlType == 2 ? LB_GETTEXT : CB_GETLBTEXT , draw->itemID, (LPARAM)buffer);
//                 SetBkMode(hdc, TRANSPARENT);
//                 SetTextColor(hdc, config->textColor);
//                 rc.left += 4;
//                 DrawTextW(hdc, buffer, -1, &rc, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
//             }
//             return TRUE;
//         }

//         case WM_NCDESTROY: {
//             if (config) { free(config); }
//             RemoveWindowSubclass(hwnd, CustomDDLProc, uIdSubclass);
//             break;
//         }
//     }

//     return DefSubclassProc(hwnd, uMsg, wParam, lParam);
// }


// void CustomDDL(HWND hwnd, int backgroundСolor, int textColor, int highlightColor, int CBbackgroundСolor, int CBborderColor, int CBborderWidth, int CBtextColor) {
//     SetWindowTheme(hwnd, L"DarkMode_CFD", NULL);

//     DDL_List_Config* config = (DDL_List_Config*)malloc(sizeof(DDL_List_Config));
//     if (!config) return;
//     config->backgroundСolor          = HEX2COLORREF(backgroundСolor);
//     config->textColor                = HEX2COLORREF(textColor);
//     config->highlightColor           = HEX2COLORREF(highlightColor);
//     config->ComboBox.backgroundСolor = HEX2COLORREF(CBbackgroundСolor);
//     config->ComboBox.borderColor     = HEX2COLORREF(CBborderColor);
//     config->ComboBox.borderWidth     = CBborderWidth;
//     config->ComboBox.textColor       = HEX2COLORREF(CBtextColor);

//     DWORD_PTR oldRefData = 0;
//     if (GetWindowSubclass(hwnd, CustomDDLProc, uIdSubclassDDL, &oldRefData)) {
//         if (oldRefData) {
//             free((DDL_List_Config*)oldRefData);
//         }
//         SetWindowSubclass(hwnd, CustomDDLProc, uIdSubclassDDL, (DWORD_PTR)config);
//     } else {
//         SetWindowSubclass(hwnd, CustomDDLProc, uIdSubclassDDL, (DWORD_PTR)config);
//     }
// }
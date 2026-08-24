#include "ctrl.h"
#include <Windows.h>
#include <commctrl.h>


LRESULT CALLBACK CustomBorderProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam, UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
    BorderConfig* config = (BorderConfig*)dwRefData;

    switch (uMsg) {
        case WM_NCCALCSIZE: {
            if (wParam) {
                NCCALCSIZE_PARAMS* pNcParams = (NCCALCSIZE_PARAMS*)lParam;
                pNcParams->rgrc[0].left   += config->width;
                pNcParams->rgrc[0].top    += config->width;
                pNcParams->rgrc[0].right  -= config->width;
                pNcParams->rgrc[0].bottom -= config->width;
                return DefSubclassProc(hwnd, uMsg, wParam, lParam);
            }
            break;
        }

        case WM_NCPAINT: {
            LRESULT lRet = DefSubclassProc(hwnd, uMsg, wParam, lParam);

            HDC hdc = GetWindowDC(hwnd);
            RECT rc, frame;
            GetWindowRect(hwnd, &rc);
            int width  = rc.right - rc.left;
            int height = rc.bottom - rc.top;

            HBRUSH hBrush = CreateSolidBrush(config->color);
            for (int i = 0; i < config->width; i++) {
                frame.left   = i;
                frame.top    = i;
                frame.right  = width - i;
                frame.bottom = height - i;
                FrameRect(hdc, &frame, hBrush);
            }

            DeleteObject(hBrush);
            ReleaseDC(hwnd, hdc);
            return lRet;
        }

        case WM_NCDESTROY: {
            if (config) { free(config); }
            RemoveWindowSubclass(hwnd, CustomBorderProc, uIdSubclass);
            break;
        }
    }

    return DefSubclassProc(hwnd, uMsg, wParam, lParam);
}

void CustomBorder(HWND hwnd, int width = 2, int hexColor = 0x303030) {
    SetWindowLongPtr(hwnd, GWL_STYLE, GetWindowLongPtr(hwnd, GWL_STYLE) & ~WS_BORDER);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, GetWindowLongPtr(hwnd, GWL_EXSTYLE) & ~WS_EX_CLIENTEDGE);

    BorderConfig* config = (BorderConfig*)malloc(sizeof(BorderConfig));
    if (!config) return;
    config->width = width;
    config->color = HEX2COLORREF(hexColor);

    DWORD_PTR oldRefData = 0;
    if (GetWindowSubclass(hwnd, CustomBorderProc, uIdSubclassBoeder, &oldRefData)) { // есть ли уже подкласс или нет
        if (oldRefData) {
            free((BorderConfig*)oldRefData);
        }
        SetWindowSubclass(hwnd, CustomBorderProc, uIdSubclassBoeder, (DWORD_PTR)config);
    } else {
        SetWindowSubclass(hwnd, CustomBorderProc, uIdSubclassBoeder, (DWORD_PTR)config);
    }

    SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
}
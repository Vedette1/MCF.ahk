#include "ctrl.h"
#include <Windows.h>
#include <commctrl.h>
#include <uxtheme.h>


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
    int brushColor = config->backgroundColor;
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




//======================================================================================================================================


static const wchar_t* FindChar(const wchar_t* str, wchar_t ch) {
    while (*str) {
        if (*str == ch) return str;
        str++;
    }
    return NULL;
}


#define TOGGLE_ANIM_MS   400
#define TOGGLE_TIMER_ID  1

typedef struct {
    HWND  hwnd;
    float pos, from, target;
    DWORD t0;
    BOOL  animating;
    BOOL  hot;      // свой хот-трекинг (тему-то срезали)
    BOOL  pressed;  // своя фиксация нажатия
} ToggleAnim;

// POD-массив: нулевая инициализация, никакой работы при старте процесса
static ToggleAnim g_anims[32];
static int        g_animCount = 0;

static ToggleAnim* Toggle_Anim(HWND hwnd) {
    ToggleAnim* dead = NULL;
    for (int i = 0; i < g_animCount; i++) {
        if (g_anims[i].hwnd == hwnd) return &g_anims[i];
        if (!IsWindow(g_anims[i].hwnd)) dead = &g_anims[i]; // слот умершей кнопки
    }
    if (!dead) {
        if (g_animCount == 32) return NULL;
        dead = &g_anims[g_animCount++];
    }
    dead->hwnd      = hwnd;
    dead->animating = FALSE;
    dead->pos = dead->from = dead->target =
        (SendMessageW(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED) ? 1.0f : 0.0f;
    dead->t0 = 0;
    return dead;
}

static void CALLBACK Toggle_TimerProc(HWND hwnd, UINT, UINT_PTR id, DWORD now) {
    ToggleAnim* a = Toggle_Anim(hwnd);
    if (!a || !a->animating) { KillTimer(hwnd, id); return; }

    float t = (now - a->t0) / (float)TOGGLE_ANIM_MS; // DWORD-арифметика безопасна при wrap
    if (t >= 1.0f) {
        a->pos = a->target;
        a->animating = FALSE;
        KillTimer(hwnd, id);
    } else {
        float e = t * t * (3.0f - 2.0f * t); // smoothstep
        a->pos = a->from + (a->target - a->from) * e;
    }
    InvalidateRect(hwnd, NULL, FALSE); // FALSE = не стирать фон, меньше мерцания
    UpdateWindow(hwnd);
}

// Вызывать из WM_COMMAND на BN_CLICKED (BS_AUTOCHECKBOX чек уже переключил)
void Toggle_Click(HWND hwnd) {
    ToggleAnim* a = Toggle_Anim(hwnd);
    if (!a) return;
    a->target = (SendMessageW(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED) ? 1.0f : 0.0f;
    if (TOGGLE_ANIM_MS <= 0) {
        a->pos = a->target;
        InvalidateRect(hwnd, NULL, FALSE);
        return;
    }
    a->from      = a->pos;   // стартуем с текущего места — можно кликать посреди анимации
    a->t0        = GetTickCount();
    a->animating = TRUE;
    SetTimer(hwnd, TOGGLE_TIMER_ID, USER_TIMER_MINIMUM, Toggle_TimerProc);
}

// "альфа-канал для бедных": подмешивание вместо прозрачности
static COLORREF MixColor(COLORREF a, COLORREF b, float t) {
    if (t < 0.0f) t = 0.0f;
    if (t > 1.0f) t = 1.0f;
    return RGB((int)(GetRValue(a) + (GetRValue(b) - GetRValue(a)) * t + 0.5f),
               (int)(GetGValue(a) + (GetGValue(b) - GetGValue(a)) * t + 0.5f),
               (int)(GetBValue(a) + (GetBValue(b) - GetBValue(a)) * t + 0.5f));
}

// ========================= отрисовка =========================

// LRESULT CALLBACK CheckBoxProc(HWND hwnd, LPARAM lParam, CheckBoxConfig* config) {
//     NMCUSTOMDRAW* pcd = (NMCUSTOMDRAW*)lParam;
//     if (pcd->dwDrawStage != CDDS_PREPAINT)
//         return CDRF_DODEFAULT;

//     int width  = pcd->rc.right - pcd->rc.left;
//     int height = pcd->rc.bottom - pcd->rc.top;
//     if (width <= 0 || height <= 0)
//         return CDRF_SKIPDEFAULT;

//     // ---- буфер: весь кадр собирается здесь ----
//     HDC     hdc   = CreateCompatibleDC(pcd->hdc);
//     HBITMAP bm    = CreateCompatibleBitmap(pcd->hdc, width, height);
//     HGDIOBJ oldBM = SelectObject(hdc, bm);
//     RECT rc = { 0, 0, width, height };
//     int  pad = 3;

//     ToggleAnim* a = Toggle_Anim(hwnd);
//     float pos = a ? a->pos
//                   : (SendMessageW(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED ? 1.0f : 0.0f);

//     bool disabled = (pcd->uItemState & CDIS_DISABLED) != 0;
//     bool hot      = (pcd->uItemState & CDIS_HOT) != 0 || (a && a->hot); // ручной флаг надёжен
//     bool pressed  = a && a->pressed; // CDIS_SELECTED не юзаем

//     COLORREF track = config->backgroundColor;
//     if      (disabled) track = BrightenColor(track, -20);
//     else if (pressed)  track = BrightenColor(track, -20);
//     else if (hot)      track = BrightenColor(track, 5);

//     COLORREF accent = config->squareColor;
//     if      (disabled) accent = config->hover.DISABLED != -1 ? config->hover.DISABLED : BrightenColor(accent, -20);
//     else if (pressed)  accent = config->hover.SELECTED != -1 ? config->hover.SELECTED : BrightenColor(accent, -10);
//     else if (hot)      accent = config->hover.HOT      != -1 ? config->hover.HOT      : BrightenColor(accent, 12);

//     SetDCBrushColor(hdc, track);
//     FillRect(hdc, &rc, (HBRUSH)GetStockObject(DC_BRUSH));

//     int knobW = width / 2 - pad * 2;
//     int kx = (int)(pad + (float)(width - pad * 2 - knobW) * pos + 0.5f);
//     RECT rcKnob = { kx, pad, kx + knobW, height - pad };
//     SetDCBrushColor(hdc, accent);
//     FillRect(hdc, &rcKnob, (HBRUSH)GetStockObject(DC_BRUSH));

//     if (config->borderColor != -1) {
//         HPEN hPen = CreatePen(PS_SOLID, 3, config->borderColor);
//         HGDIOBJ oldPen = SelectObject(hdc, hPen);
//         SelectObject(hdc, GetStockObject(NULL_BRUSH));
//         Rectangle(hdc, 0, 0, width, height);
//         SelectObject(hdc, oldPen);
//         DeleteObject(hPen);
//     }

//     wchar_t buf[128] = { 0 };
//     GetWindowTextW(hwnd, buf, 128);
//     const wchar_t* leftText  = buf;
//     const wchar_t* rightText = NULL;
//     const wchar_t* sep = FindChar(buf, L'|');
//     if (sep) { buf[sep - buf] = L'\0'; rightText = sep + 1; }

//     HFONT hFont = (HFONT)SendMessageW(hwnd, WM_GETFONT, 0, 0);
//     HGDIOBJ oldFont = SelectObject(hdc, hFont ? hFont : GetStockObject(DEFAULT_GUI_FONT));
//     SetBkMode(hdc, TRANSPARENT);

//     COLORREF textOn  = config->activeTextColor;
//     COLORREF textOff = config->inactiveTextColor;
//     if (disabled) { textOn = MixColor(track, textOn, 0.45f); textOff = MixColor(track, textOff, 0.45f); }

//     RECT rcL = { 0, 0, width / 2, height };
//     SetTextColor(hdc, MixColor(textOff, textOn, 1.0f - pos));
//     DrawTextW(hdc, leftText, -1, &rcL, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

//     if (rightText) {
//         RECT rcR = { width / 2, 0, width, height };
//         SetTextColor(hdc, MixColor(textOff, textOn, pos));
//         DrawTextW(hdc, rightText, -1, &rcR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
//     }
//     SelectObject(hdc, oldFont);

//     // ---- атомарный вывод: единственная операция, которая трогает экран ----
//     BitBlt(pcd->hdc, pcd->rc.left, pcd->rc.top, width, height, hdc, 0, 0, SRCCOPY);

//     SelectObject(hdc, oldBM);
//     DeleteObject(bm);
//     DeleteDC(hdc);
//     return CDRF_SKIPDEFAULT;
// }


LRESULT CALLBACK ToggleSubclassProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
    ToggleAnim* a = Toggle_Anim(hwnd);
    CheckBoxConfig* config = (CheckBoxConfig*)dwRefData;

    switch (msg) {
        case WM_ERASEBKGND:
            return 1; // (TRUE), чтобы винда не пыталась очищать фон. Это убивает мерцание

        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdcPaint = BeginPaint(hwnd, &ps);

            RECT rcClient;
            GetClientRect(hwnd, &rcClient);
            int width = rcClient.right - rcClient.left;
            int height = rcClient.bottom - rcClient.top;

            if (width > 0 && height > 0) {
                // ---- Двойная буферизация ----
                HDC hdcMem = CreateCompatibleDC(hdcPaint);
                HBITMAP hbmMem = CreateCompatibleBitmap(hdcPaint, width, height);
                HGDIOBJ oldBM = SelectObject(hdcMem, hbmMem);
                
                int pad = 3;
                float pos = a ? a->pos : (SendMessageW(hwnd, BM_GETCHECK, 0, 0) == BST_CHECKED ? 1.0f : 0.0f);

                bool disabled = !IsWindowEnabled(hwnd);
                bool hot      = a && a->hot;
                bool pressed  = a && a->pressed;

                // Цвета
                COLORREF track = config->backgroundColor;
                if      (disabled) track = BrightenColor(track, -20);
                else if (pressed)  track = BrightenColor(track, -20);
                else if (hot)      track = BrightenColor(track, 50);

                COLORREF accent = config->squareColor;
                if      (disabled) accent = config->hover.DISABLED != -1 ? config->hover.DISABLED : BrightenColor(accent, -20);
                else if (pressed)  accent = config->hover.SELECTED != -1 ? config->hover.SELECTED : BrightenColor(accent, -10);
                else if (hot)      accent = config->hover.HOT      != -1 ? config->hover.HOT      : BrightenColor(accent, 12);

                // Отрисовка фона
                SetDCBrushColor(hdcMem, track);
                FillRect(hdcMem, &rcClient, (HBRUSH)GetStockObject(DC_BRUSH));

                // Отрисовка ползунка
                int knobW = width / 2 - pad * 2;
                int kx = (int)(pad + (float)(width - pad * 2 - knobW) * pos + 0.5f);
                RECT rcKnob = { kx, pad, kx + knobW, height - pad };
                SetDCBrushColor(hdcMem, accent);
                FillRect(hdcMem, &rcKnob, (HBRUSH)GetStockObject(DC_BRUSH));

                // Отрисовка рамки
                if (config->borderColor != -1) {
                    HPEN hPen = CreatePen(PS_SOLID, 3, config->borderColor);
                    HGDIOBJ oldPen = SelectObject(hdcMem, hPen);
                    SelectObject(hdcMem, GetStockObject(NULL_BRUSH));
                    Rectangle(hdcMem, 0, 0, width, height);
                    SelectObject(hdcMem, oldPen);
                    DeleteObject(hPen);
                }

                // Текст
                wchar_t buf[128] = { 0 };
                GetWindowTextW(hwnd, buf, 128);
                const wchar_t* leftText  = buf;
                const wchar_t* rightText = NULL;
                const wchar_t* sep = FindChar(buf, L'|');
                if (sep) { buf[sep - buf] = L'\0'; rightText = sep + 1; }

                HFONT hFont = (HFONT)SendMessageW(hwnd, WM_GETFONT, 0, 0);
                HGDIOBJ oldFont = SelectObject(hdcMem, hFont ? hFont : GetStockObject(DEFAULT_GUI_FONT));
                SetBkMode(hdcMem, TRANSPARENT);

                COLORREF textOn  = config->activeTextColor;
                COLORREF textOff = config->inactiveTextColor;
                if (disabled) { textOn = MixColor(track, textOn, 0.45f); textOff = MixColor(track, textOff, 0.45f); }

                RECT rcL = { 0, 0, width / 2, height };
                SetTextColor(hdcMem, MixColor(textOff, textOn, 1.0f - pos));
                DrawTextW(hdcMem, leftText, -1, &rcL, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

                if (rightText) {
                    RECT rcR = { width / 2, 0, width, height };
                    SetTextColor(hdcMem, MixColor(textOff, textOn, pos));
                    DrawTextW(hdcMem, rightText, -1, &rcR, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
                }
                SelectObject(hdcMem, oldFont);

                BitBlt(hdcPaint, 0, 0, width, height, hdcMem, 0, 0, SRCCOPY);

                SelectObject(hdcMem, oldBM);
                DeleteObject(hbmMem);
                DeleteDC(hdcMem);
            }
            EndPaint(hwnd, &ps);
            return 0; // дефолтный отрисовщик не вызывается
        }

        // Логика мыши
        case WM_MOUSEMOVE:
            if (!a->hot) {
                a->hot = TRUE;
                TRACKMOUSEEVENT tme = { sizeof(tme), TME_LEAVE, hwnd, 0 };
                TrackMouseEvent(&tme);
                InvalidateRect(hwnd, NULL, FALSE);
            }
            break;

        case WM_MOUSELEAVE:
            a->hot = FALSE;
            InvalidateRect(hwnd, NULL, FALSE);
            break;

        case WM_LBUTTONDOWN:
            a->pressed = TRUE;
            InvalidateRect(hwnd, NULL, FALSE);
            break;

        case WM_LBUTTONUP:
        case WM_CAPTURECHANGED:
            if (a->pressed) {
                a->pressed = FALSE;
                InvalidateRect(hwnd, NULL, FALSE);
            }
            break;
            
        case WM_NCDESTROY:
            RemoveWindowSubclass(hwnd, ToggleSubclassProc, uIdSubclass);
            break;
    }
    
    return DefSubclassProc(hwnd, msg, wParam, lParam);
}
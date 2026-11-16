// #include "ctrl.h"
// #include <Windows.h>
// #include <commctrl.h>
// #include <algorithm>


// static int* GetColumnBoundaries(HWND hHeader, int* outCount) {
//     int count = SendMessageW(hHeader, HDM_GETITEMCOUNT, NULL, NULL);
//     int* boundaries = (int*)malloc(count * sizeof(int));
//     *outCount = count;
//     if (boundaries == NULL) return NULL;

//     for (int i = 0; i < count; i++) {
//         int index = SendMessageW(hHeader, HDM_ORDERTOINDEX, i, 0);
//         RECT rc;
//         SendMessageW(hHeader, HDM_GETITEMRECT, index, (LPARAM)&rc);
//         boundaries[i] = rc.right - 1; // правая граница этой колонки (-1 что бы линии заголовка совпадали с нижними линиями)
//     }

//     return boundaries; // массив X-координат вертикальных линий, уже в порядке слева направо
// }


// static int* GetRowBoundaries(HWND hwnd, int realItemHeight, int* outCount) {
//     int topIndex    = SendMessageW(hwnd, LVM_GETTOPINDEX, NULL, NULL);
//     int perPage     = SendMessageW(hwnd, LVM_GETCOUNTPERPAGE, NULL, NULL);
//     int total       = SendMessageW(hwnd, LVM_GETITEMCOUNT, NULL, NULL);
//     int lastVisible = (std::min)(topIndex + perPage, total - 1);
//     int count       = lastVisible - topIndex + 1;
//     int* boundaries = (int*)malloc(count * sizeof(int));
//     *outCount = count;
//     if (boundaries == NULL) return NULL;

//     for (int i = 0; i < count; i++) {
//         int idx = topIndex + i;
//         RECT rc;
//         rc.left = LVIR_BOUNDS;
//         SendMessageW(hwnd, LVM_GETITEMRECT, idx, (LPARAM)&rc);
//         boundaries[i] = rc.bottom;
//     }

//     if (count < perPage) { // Если количесво элементов меньше чем в себя может вместить LV, то горизонтальные линии сетки все равно будет нарисована
//         boundaries = (int*)malloc((perPage + 1) * sizeof(int)); // +1 - это запас
//         *outCount = perPage;
//         for (int i = 1; i < (perPage + 1); i++) {
//             boundaries[i] = i * realItemHeight;
//         }
//     }

//     return boundaries;
// }


// static int GetHeaderOffsetX(HWND hHeader, HWND hLV) {
//     POINT pt;
//     MapWindowPoints(hHeader, hLV, &pt, 1);
//     return pt.x;
// }



// LRESULT CALLBACK CustomListViewProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam, UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
//     ListViewConfig* config = (ListViewConfig*)dwRefData;
//     static int HoverLVItem     = -1;
//     static int HoverLViSubItem = -1;

//     switch (uMsg) {
//         case WM_PAINT: {
//             PAINTSTRUCT ps; RECT clientRect, headerRect;
//             HDC hdc = BeginPaint(hwnd, &ps);

//             HPEN hPen = CreatePen(PS_SOLID, 1, config->gridColor);
//             HGDIOBJ oldPen = SelectObject(hdc, hPen);

//             GetClientRect(hwnd, &clientRect);
//             GetWindowRect(config->hHeader, &headerRect);
//             int headerHeight = headerRect.bottom - headerRect.top;
//             int rowCount;
//             int* rowBoundaries = GetRowBoundaries(hwnd, config->realItemHeight, &rowCount);

//             for (int i = 0; i < rowCount; i++) {
//                 int y = rowBoundaries[i];
//                 if (y > headerHeight) {
//                     MoveToEx(hdc, 0, y, 0);
//                     LineTo(hdc, clientRect.right, y);
//                 }
//             }
//             free(rowBoundaries);

//             int colCount;
//             int offsetX = GetHeaderOffsetX(config->hHeader, hwnd);
//             int* colBoundaries = GetColumnBoundaries(config->hHeader, &colCount);

//             for (int i = 0; i < colCount; i++) {
//                 int x = colBoundaries[i] + offsetX;
//                 MoveToEx(hdc, x, headerHeight, NULL);
//                 LineTo(hdc, x, clientRect.bottom);
//             }
//             free(colBoundaries);

//             SelectObject(hdc, oldPen);
//             DeleteObject(hPen);
//             EndPaint(hwnd, &ps);
//             return 0;
//         }

//         case WM_NCPAINT: {
//             RECT rect;
//             LRESULT res = DefSubclassProc(hwnd, uMsg, wParam, lParam);
//             HDC hdc = GetDC(hwnd);

//             GetWindowRect(hwnd, &rect);
//             HGDIOBJ hBrush   = GetStockObject(NULL_BRUSH);
//             HPEN hPen        = CreatePen(0, 3, config->borderColor);
//             HGDIOBJ oldBrush = SelectObject(hdc, hBrush);
//             HGDIOBJ oldPen   = SelectObject(hdc, hPen);
//             Rectangle(hdc, 0, 0, rect.right - rect.left, rect.bottom - rect.top);
//             SelectObject(hdc, oldBrush);
//             SelectObject(hdc, oldPen);
//             DeleteObject(hPen);

//             ReleaseDC(hwnd, hdc);
//             return res;
//         }

//         case WM_MOUSEMOVE: {
//             LVHITTESTINFO hitTest;
//             hitTest.pt.x = lParam << 48 >> 48;
//             hitTest.pt.y = lParam << 32 >> 48;

//             SendMessageW(hwnd, LVM_SUBITEMHITTEST, 0, (LPARAM)&hitTest);
//             int iItem    = hitTest.iItem;
//             int iSubItem = hitTest.iSubItem;

//             if (HoverLVItem != iItem || HoverLViSubItem != iSubItem) {
//                 HoverLVItem     = iItem;
//                 HoverLViSubItem = iSubItem;
//                 InvalidateRect(hwnd, NULL, NULL);

//                 TRACKMOUSEEVENT TME;
//                 TME.cbSize      = sizeof(TME);
//                 TME.dwFlags     = TME_LEAVE;
//                 TME.hwndTrack   = hwnd;
//                 TME.dwHoverTime = HOVER_DEFAULT;
//                 TrackMouseEvent(&TME);
//             }
//             return 0;
//         }

//         case WM_MOUSELEAVE: {
//             if (HoverLVItem != -1) {
//                 HoverLVItem = -1;
//                 InvalidateRect(hwnd, 0, 0);
//             }
//             return 0;
//         }

//         case WM_MOUSEWHEEL:
//         case WM_VSCROLL:
//             if (0x0100 && wParam >= 0x21 && wParam <= 0x28) {
//                 InvalidateRect(hwnd, 0, 0);
//                 break;
//             }

//         case WM_HSCROLL:
//             if (0x0100 && wParam >= 0x21 && wParam <= 0x28) {
//                 LRESULT res = DefSubclassProc(hwnd, uMsg, wParam, lParam);
//                 InvalidateRect(hwnd, 0, 0);
//                 return res;
//             }

//         case WM_NCDESTROY: {
//             if (config) { free(config); }
//             RemoveWindowSubclass(hwnd, CustomListViewProc, uIdSubclass);
//             break;
//         }
//     }

//     return DefSubclassProc(hwnd, uMsg, wParam, lParam);
// }


// LRESULT CALLBACK CustomListViewHeaderProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam, UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
//     ListViewConfig* config = (ListViewConfig*)dwRefData;

//     switch (uMsg) {
//         case WM_PAINT: {
//             PAINTSTRUCT ps; RECT rc;
//             HDC hdc = BeginPaint(hwnd, &ps);

//             GetClientRect(hwnd, &rc);
//             LRESULT count = SendMessageW(hwnd, HDM_GETITEMCOUNT, NULL, NULL);
//             if (count > 0) {
//                 LRESULT lastIndex = SendMessageW(hwnd, HDM_ORDERTOINDEX, count - 1, NULL);
//                 RECT itemRect;
//                 SendMessageW(hwnd, HDM_GETITEMRECT, lastIndex, (LPARAM)&itemRect);
//                 rc.left = itemRect.right;
//             }

//             if (rc.left < rc.right) {
//                 HBRUSH hBrush = CreateSolidBrush(config->headerBkColor);
//                 FillRect(hdc, &rc, hBrush);
//                 DeleteObject(hBrush);
//             }

//             EndPaint(hwnd, &ps);
//             return 0;
//         }
//     }

//     return DefSubclassProc(hwnd, uMsg, wParam, lParam);
// }


// void CustomListView(ListViewConfig* config) {
//     HWND hHeader = (HWND)SendMessageW(config->hwnd, LVM_GETHEADER, NULL, NULL);
//     int realItemHeight = SendMessageW(config->hwnd, LVM_GETITEMSPACING, 1, NULL);
//     RECT headerRect;
//     GetWindowRect((HWND)SendMessageW(config->hwnd, LVM_GETHEADER, NULL, NULL), &headerRect);
//     int headerHeight = headerRect.bottom - headerRect.top;

//     config->hHeader        = hHeader;
//     config->headerBkColor  = HEX2COLORREF(config->headerBkColor);
//     config->gridColor      = HEX2COLORREF(config->gridColor);
//     config->borderColor    = HEX2COLORREF(config->borderColor);
//     config->realItemHeight = realItemHeight + (headerHeight - realItemHeight);

//     SetWindowSubclass(config->hwnd, CustomListViewProc, uIdSubclassListView, (DWORD_PTR)config);
//     SetWindowSubclass(config->hHeader, CustomListViewHeaderProc, uIdSubclassListViewHeader, (DWORD_PTR)config);
// }
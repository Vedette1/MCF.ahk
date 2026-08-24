#pragma once
#pragma comment(lib, "Comctl32.lib")
#include <Windows.h>

#define HEX2COLORREF(hex) ((hex & 0xFF) << 16) | (hex & 0xFF00) | ((hex >> 16) & 0xFF)
#define uIdSubclassBoeder 1
#define uIdSubclassDDL 2
#define uIdSubclassListView 3
#define uIdSubclassListViewHeader 4

struct DDLConfig {
    COLORREF backgroundСolor;
    COLORREF textColor;
    COLORREF highlightColor;
};

struct BorderConfig {
    int width;
    COLORREF color;
};

struct ButtonConfig {
    struct HoverEffect {
        COLORREF DISABLED;
        COLORREF SELECTED;
        COLORREF HOT;
    };

    COLORREF backgroundСolor;
    COLORREF textColor;
    COLORREF borderColor;
    int borderWidth;
    HoverEffect hover;
    int ddlMode;
};

struct ListViewConfig {
    HWND hwnd;
    HWND hHeader;
    COLORREF headerBkColor;
    COLORREF gridColor;
    COLORREF borderColor;
    int realItemHeight;
};

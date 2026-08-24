#include <Windows.h>

typedef void (WINAPI *fnSetPreferredAppMode)(int appMode);
typedef void (WINAPI *fnFlushMenuThemes)(void);

void DarkMode() {
	HMODULE uxtheme = LoadLibraryA("uxtheme");
	if (uxtheme) {
		fnSetPreferredAppMode SetPreferredAppMode = (fnSetPreferredAppMode)GetProcAddress(uxtheme, MAKEINTRESOURCEA(135));
		fnFlushMenuThemes     FlushMenuThemes     = (fnFlushMenuThemes)GetProcAddress(uxtheme, MAKEINTRESOURCEA(136));
		SetPreferredAppMode(2); // ForceDark
		FlushMenuThemes();
	} else {
		MessageBoxA(0, "DarkMode:\nFor some reason uxtheme.dll is not loaded.", "non-critical error", MB_ICONEXCLAMATION);
	}
}
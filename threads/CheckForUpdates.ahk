; Persistent(true)
; global lastRequest := true

; CheckForUpdates(owner, repo, currentV, infoSuccess := true) {
;     global lastRequest
;     if (lastRequest) {
;         lastRequest := false
;         try {
;             http := ComObject("WinHttp.WinHttpRequest.5.1")
;             http.Open("GET", "https://github.com/" owner "/" repo "/releases/latest", false) ; обычная ссылка на Latest, не API (ибо есть проблемы с лимитами)
;             http.Send()
;             finalUrl := http.Option(1) ; итоговый URL после всех перенаправлений (Option(1) это свойство URL)
;         } catch as er {
;             return MsgBox("An unknown error occurred while checking for updates.`n" er.Message,, 0x10)
;         }

;         if RegExMatch(finalUrl, "tag/v?([^/]+)$", &m) { ; ".../releases/tag/v1.0.1" или ".../releases/tag/1.0.1" (v игнорируется)
;             latestV := m[1]
;             if (VerCompare(latestV, currentV) > 0) {
;                 choice := MsgBox("New version available: " latestV "`nWant to watch the release?",, 0x44)
;                 if (choice == "Yes") {
;                     Run(finalUrl)
;                 }
;             } else {
;                 if (infoSuccess) {
;                     MsgBox("You have the latest version installed: " latestV,, 0x40)
;                 }
;             }
;         } else {
;             MsgBox("No releases found.",, 0x30)
;         }
;         lastRequest := true
;     }
; }

; CheckForUpdates("Vedette1", "MCF.ahk", Worker(A_MainThreadID)['GLOBAL_MCF_VERSION'], true)
; if (IniRead(Worker(A_MainThreadID)['GLOBAL_INI_FILE'], "SETTINGS", "CHECK_AUTO_UPDATE", false)) {
;     CheckForUpdates("Vedette1", "MCF.ahk", Worker(A_MainThreadID)['GLOBAL_MCF_VERSION'])
; }
#Requires AutoHotkey v2.0
#SingleInstance Force

class RTF {
   static VsCodeAhk := [
        {color: 0x9CDCFE}, ; AllTextColor
        {color: 0xcf876a, patterns: ['".*?"'], type: "regex"},
        {color: 0xcf876a, patterns: ["'.*?'"], type: "regex"},
        {color: 0xa8d88e, patterns: ["\b0x[0-9a-fA-F]+\b"], type: "regex"},
        {color: 0xa8d88e, patterns: ["\b\d+\b"], type: "regex"},
        {color: 0xf6f5f5, patterns: ["\.|,|:=|=|==|!=|!==|>|<|>=|<=|\?|:|\?\?|\+|-|\*|/|//|\*\*|<<|>>|&|\||\^|~|\+=|-=|\*=|/=|//=|\*\*=|<<=|>>=|&=|\|=|\^=|=|%=|\\"], type: "regex"},
        {color: 0xe7e734, patterns: ["\(|\)"],       type: "regex"},
        {color: 0xf759ea, patterns: ["\[|\]"],       type: "regex"},
        {color: 0x1d99ff, patterns: ["\{|}"],        type: "regex"},
        {color: 0x589d38, patterns: [";.*$"],        type: "regex"},
        {color: 0xC586C0, patterns: ["switch", "if", "else", "loop", "while", "for", "try", "return", "catch", "case"], type: "word"},
        {color: 0x2a71ab, patterns: ["true", "false", "in", "local", "static", "A_WorkingDir", "A_LoopFileFullPath", "A_LoopFileName", "A_UserName", "class", "__New", "this"], type: "word"},
        {color: 0x12d1ab, patterns: ["Map", "Buffer", "Gui", "Offsets"], type: "word"},
        {color: 0xeeeeba, patterns: ["(?i)\b(?!(?:switch|if|else|loop|while|for|try|return|catch|case|Map|__New|Buffer)\b)[a-zA-Z_$][a-zA-Z0-9_$]*(?=\()"], type: "regex"},
    ]


    static CoffSyntax := [
        {color: 0xCE9178},
        {color: 0xF759EA, patterns: ["\[|\]"], type: "regex"}, ; []
        {color: 0xFFFFFF, patterns: ["\.|\:|\-"], type: "regex"}, ; . : -
        {color: 0x73cfc3, patterns: ["\b\d+\b"], type: "regex"}, ; num "0xa8afce"
        {color: 0xB5CEA8, patterns: ["\b0x[0-9a-fA-F]+\b"], type: "regex"}, ; hex
        {color: 0xC586C0, patterns: ["FILE", "SYMBOL_TABLE", "SECTIONS", "RELOCATION", "RELOCATION_RECORDS_FOR"], type: "word"},
        {color: 0x12d1ab, patterns: ["IMAGE_FILE_HEADER", "IMAGE_SYMBOL", "IMAGE_SECTION_HEADER", "IMAGE_RELOCATION"], type: "word"},
        {color: 0x569CD6, patterns: ["Val", "Sec", "Typ", "Aux", "Class", "Idx", "Name", "VSize", "VAddr", "RawSize", "RawPtr", "RelocPtr", "nReloc", "Charact", "Machine", "Reloc", "Type", "NumberOfSections", "TimeDateStamp", "PointerToSymbolTable", "NumberOfSymbols", "SizeOfOptionalHeader", "Characteristics"], type: "word"},
    ]
    

    static HexDump := [
        {color: 0xD4D4D4},
        ;{color: 0x569CD6, patterns: ["^\s*[0-9a-fA-F]+(?=\s+)"], type: "regex"},  ; Адрес слева
        {color: 0xB5CEA8, patterns: ["\b[0-9a-fA-F]{2}\b"], type: "regex"},
        {color: 0x808080, patterns: ["\|"], type: "regex"},
    ]


    static ObjdumpHighlight := [
        {color: 0xD4D4D4},
        {color: 0x6A9955, patterns: ["#.*$"], type: "regex"},               ; комменты
        {color: 0x806bca, patterns: ["^[ ]*[0-9a-fA-F]+:"], type: "regex"}, ; Адреса строк
        {color: 0xd47670, patterns: ["\b[0-9a-fA-F]{2}\b"], type: "regex"}, ; байты
        {color: 0xB5CEA8, patterns: ["\b0x[0-9a-fA-F]+\b"], type: "regex"}, ; 0x... 
        {color: 0x73cfc3, patterns: ["\b\d+\b"], type: "regex"},            ; десятичные числа
        {color: 0xDCDCAA, patterns: ["<[^>]+>:?"], type: "regex"},          ; функции <func>:
        {color: 0xF759EA, patterns: ["\[|\]"], type: "regex"},              ; []
        {color: 0xC586C0, patterns: ["ret", "retq", "call", "callq", "jmp", "je", "jne", "jz", "jnz", "jg", "jge", "jl", "jle", "ja", "jb", "js", "jns", "loop"], type: "word"},
        {color: 0x569CD6, patterns: ["mov", "push", "pop", "add", "sub", "inc", "dec", "cmp", "xor", "or", "and", "shl", "shr", "lea", "nop", "int", "syscall"], type: "word"},
        {color: 0x9CDCFE, patterns: ["rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp", "rip", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp", "ax", "bx", "cx", "dx", "al", "bl", "cl", "dl", "ah", "bh", "ch", "dh"], type: "word"},
        {color: 0x12d1ab, patterns: ["byte", "word", "dword", "qword", "ptr"], type: "word"}
    ]


    static CSyntax := [
        {color: 0xD4D4D4}, 
        {color: 0xFFFFFF, bgColor: 0x223832, patterns: ["\`t"], type: "regex"},
        {color: 0xcf876a, patterns: ['".*?"'], type: "regex"},
        {color: 0xcf876a, patterns: ["'.*?'"], type: "regex"},
        {color: 0xa8d88e, patterns: ["\b0x[0-9a-fA-F]+\b"], type: "regex"},
        {color: 0xa8d88e, patterns: ["\b\d+\.?\d*f?\b"], type: "regex"},
        {color: 0x589d38, patterns: ["//.*$"], type: "regex"},
        {color: 0x589d38, patterns: ["/\*.*?\*/"], type: "regex"},
        {color: 0xC586C0, patterns: ["^\s*#[a-zA-Z_]\w*"], type: "regex"},
        {color: 0xD4D4D4, patterns: ["\.|,|;|\+|-|\*|/|%|&|\||\^|!|=|~|<|>|\?|:"], type: "regex"},
        {color: 0xE7E734, patterns: ["\(|\)"], type: "regex"},
        {color: 0xF759EA, patterns: ["\[|\]"], type: "regex"},
        {color: 0x1D99FF, patterns: ["\{|}"],  type: "regex"},
        {color: 0xC586C0, patterns: ["if", "else", "switch", "case", "default", "break", "continue", "return", "goto", "for", "while", "do", "sizeof"], type: "word"},
        {color: 0x569CD6, patterns: ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "struct", "union", "enum", "typedef", "static", "const", "volatile", "extern", "register", "auto", "bool"], type: "word"},
        {color: 0x569CD6, patterns: ["NULL", "true", "false"], type: "word"},
        {color: 0xeeeeba, patterns: ["\b(?!(?:if|while|for|switch|return|sizeof)\b)[a-zA-Z_]\w*(?=\()"], type: "regex"}
    ]


    static ErrorLog := [
        {color: "0xec5454"},
        ;{color: 0x4557ff, patterns: ["\p{Lu}"], type: "regex"},
        {color: 0xcf876a, patterns: ['".*?"'], type: "regex"},
        {color: 0xcf876a, patterns: ["'.*?'"], type: "regex"},
        {color: 0xa8d88e, patterns: ["\b\d+\b"], type: "regex"},
        {color: 0xE7E734, patterns: ["\(|\)"], type: "regex"},
        {color: 0xF759EA, patterns: ["\[|\]"], type: "regex"},
        {color: 0x1D99FF, patterns: ["\{|}"],  type: "regex"},
        {color: 0xFFFFFF, patterns: ["\.|\!|\||\^|\;|\:|\~"], type: "regex"},
        {color: 0x589d38, patterns: ["//.*$"], type: "regex"},
    ]


    static Log := [
        {color: 0x9CDCFE},
        ;{color: 0x4557ff, patterns: ["\p{Lu}"], type: "regex"},
        {color: 0xcf876a, patterns: ['".*?"'], type: "regex"},
        {color: 0xcf876a, patterns: ["'.*?'"], type: "regex"},
        {color: 0xa8d88e, patterns: ["\b\d+\b"], type: "regex"},
        {color: 0xE7E734, patterns: ["\(|\)"], type: "regex"},
        {color: 0xF759EA, patterns: ["\[|\]"], type: "regex"},
        {color: 0x1D99FF, patterns: ["\{|}"],  type: "regex"},
        {color: 0xFFFFFF, patterns: ["\.|\!"], type: "regex"},
    ]


    static LdScriptSyntax := [
        {color: 0xD4D4D4},
        {color: 0x6A9955, patterns: ["/\*.*?\*/"], type: "regex"},
        {color: 0xCE9178, patterns: ['".*?"'], type: "regex"},
        {color: 0xB5CEA8, patterns: ["\b0x[0-9a-fA-F]+\b", "\b\d+[KMkm]?\b"], type: "regex"},
        {color: 0x569CD6, patterns: ["\.[a-zA-Z0-9_]+"], type: "regex"},
        {color: 0x569CD6, patterns: ["\*"], type: "regex"},
        {color: 0xC586C0, patterns: ["SECTIONS", "MEMORY", "ENTRY", "OUTPUT", "OUTPUT_FORMAT", "OUTPUT_ARCH", "PHDRS", "SEARCH_DIR", "Provide", "KEEP", "INSERT", "AFTER", "BEFORE", "FILL"], type: "word"},
        {color: 0xDCDCAA, patterns: ["ALIGN", "SUBALIGN", "BLOCK", "ADDR", "LOADADDR", "MAX", "MIN", "SIZEOF", "LENGTH", "ORIGIN", "DEFINED"], type: "word"},
        {color: 0xCE9178, patterns: ["/DISCARD/"], type: "regex"},
        {color: 0xFFFFFF, patterns: [":", "=", ">", "<", "\+", "-", "&", "!", ","], type: "regex"},
        {color: 0xE7E734, patterns: ["\(|\)"], type: "regex"},
        {color: 0xF759EA, patterns: ["\[|\]"], type: "regex"},
        {color: 0x1D99FF, patterns: ["\{|}"],  type: "regex"}
    ]



    static EscapeRTF(text) => StrReplace(StrReplace(StrReplace(text, "\", "\\"), "{", "\{"), "}", "\}")

    static StrJoin(arr, sep) => (s := '', i := 0, [(_ => (s .= arr[++i] . sep, i < arr.Length))*], Trim(s, sep))


    ; static GenerateRTF(Text, rules) {
    ;     colorTable  := "{\colortbl;"
    ;     colorMap    := Map()
    ;     ruleIndices := Map()
    ;     patterns    := []
    ;     groupIndex  := 1
    ;     index       := 1

    ;     for group, rule in rules {
    ;         if (!colorMap.Has(color := rule.color)) {
    ;             colorMap[color] := index
    ;             colorTable .= "\red" (color & 0xFF0000) >> 16 "\green" (color & 0x00FF00) >> 8 "\blue" color & 0x0000FF ";"
    ;             index++
    ;         }
    ;         if (rule.HasProp("bgColor") && !colorMap.Has(bg := rule.bgColor)) {
    ;             colorMap[bg] := index
    ;             colorTable .= "\red" (bg & 0xFF0000) >> 16 "\green" (bg & 0x00FF00) >> 8 "\blue" bg & 0x0000FF ";"
    ;             index++
    ;         }
    ;     }

    ;     for group, rule in rules {
    ;         try for pattern in rule.patterns {
    ;             (rule.type == "regex") && patterns.Push("(" pattern ")")
    ;             (rule.type == "word")  && patterns.Push("(\b" RegExReplace(pattern, "([\\+*?()|{}\[\]])", "\$1") "\b)")
    ;             ruleIndices[groupIndex] := group
    ;             groupIndex++
    ;         }
    ;     }

    ;     combinedPattern := patterns.Length ? "i)" . this.StrJoin(patterns, "|") : ""
    ;     defaultBg       := HasProp(rules[1], "bgColor") ? colorMap[rules[1].bgColor] : 0

    ;     for line in StrSplit(Text, "`n") {
    ;         if (combinedPattern && RegExMatch(line, combinedPattern, &match, pos := 1)) {
    ;             while (match) {
    ;                 (match.Pos > pos) && rtfBody .= "\cf" 1 . (defaultBg ? "\highlight" defaultBg : "\highlight0") . " " this.EscapeRTF(SubStr(line, pos, match.Pos - pos))
    ;                 loop (match.Count) {
    ;                     if (match[A_Index] != "") {
    ;                         rule    := rules[ruleIndices[A_Index]]
    ;                         bgColor := rule.HasProp("bgColor") ? colorMap[rule.bgColor] : 0
    ;                         rtfBody .= "\cf" colorMap[rule.color] . (bgColor ? "\highlight" bgColor : "\highlight0") . " " this.EscapeRTF(match[A_Index]) . "\highlight0"
    ;                         break
    ;                     }
    ;                 }
    ;                 if (!RegExMatch(line, combinedPattern, &match, pos := match.Pos + match.Len)) {
    ;                     break
    ;                 }
    ;             }
    ;         }
    ;         (pos <= StrLen(line)) && rtfBody .= "\cf" 1 . (defaultBg ? "\highlight" defaultBg : "\highlight0") . " " this.EscapeRTF(SubStr(line, pos)), rtfBody .= "\par"
    ;     }
    ;     try return "{\rtf1\ansi\deff0 " colorTable "}" rtfBody
    ; }


    static GenerateRTF(Text, rules, ignoreCase := false) {
        colorTable  := "{\colortbl;"
        colorMap    := Map()
        ruleMap     := Map()
        ruleNames   := []
        patterns    := []
        index       := 1

        for group, rule in rules {
            if (!colorMap.Has(color := rule.color)) {
                colorMap[color] := index
                colorTable .= "\red" ((color >> 16) & 0xFF) "\green" ((color >> 8) & 0xFF) "\blue" (color & 0xFF) ";"
                index++
            }
            if (rule.HasProp("bgColor") && !colorMap.Has(bg := rule.bgColor)) {
                colorMap[bg] := index
                colorTable .= "\red" ((bg >> 16) & 0xFF) "\green" ((bg >> 8) & 0xFF) "\blue" (bg & 0xFF) ";"
                index++
            }
        }

        ; паттерны с именованными группами: (?<R1>...), (?<R2>...)
        ruleIdx := 1
        for group, rule in rules {
            try for pattern in rule.patterns {
                pName := "R" . ruleIdx
                ruleMap[pName] := rule
                ruleNames.Push(pName)

                if (rule.type == "regex") {
                    patterns.Push("(?<" pName ">" pattern ")")
                } else if (rule.type == "word") {
                    escaped := RegExReplace(pattern, "([\\.*?+\[\]{}()|^$])", "\$1")
                    patterns.Push("(?<" pName ">\b" escaped "\b)")
                }
                ruleIdx++
            }
        }

        ; combinedPattern := patterns.Length ? "i)" . this.StrJoin(patterns, "|") : ""
        combinedPattern := patterns.Length ? (ignoreCase ? "i)" : "") . this.StrJoin(patterns, "|") : ""
        defaultBg       := HasProp(rules[1], "bgColor") ? colorMap[rules[1].bgColor] : 0
        rtfBody         := ""

        for line in StrSplit(Text, "`n", "`r") {
            pos := 1
            if (combinedPattern) {
                while (RegExMatch(line, combinedPattern, &match, pos)) {
                    ; текст до совпадения (без подсветки)
                    if (match.Pos > pos) {
                        rtfBody .= "\cf1" . (defaultBg ? "\highlight" defaultBg : "\highlight0") . " " . this.EscapeRTF(SubStr(line, pos, match.Pos - pos))
                    }

                    matchedRule := ""
                    for pName in ruleNames {
                        if (match.Pos[pName] > 0) { ; Если позиция > 0 значит эта группа участвовала в совпадении
                            matchedRule := ruleMap[pName]
                            break
                        }
                    }

                    if (matchedRule != "") {
                        bgColor := matchedRule.HasProp("bgColor") ? colorMap[matchedRule.bgColor] : 0
                        fgColor := colorMap[matchedRule.color]
                        rtfBody .= "\cf" fgColor . (bgColor ? "\highlight" bgColor : "\highlight0") . " " . this.EscapeRTF(match[0]) . "\highlight0"
                    }

                    ; сдвиг позиции
                    pos := match.Pos + match.Len
                    if (match.Len == 0) {
                        pos++ ; защита от бесконечного цикла, если регулярка найдет пустое совпадение
                    }
                }
            }
            if (pos <= StrLen(line)) {
                rtfBody .= "\cf1" . (defaultBg ? "\highlight" defaultBg : "\highlight0") . " " . this.EscapeRTF(SubStr(line, pos))
            }
            rtfBody .= "\par"
        }
        try return "{\rtf1\ansi\deff0 " colorTable "}" rtfBody
    }


    static ReplaceSel(text, rules, RE, highlighting := true, ignoreCase := true, SETSEL := false) {
        if (highlighting) {
            if (SETSEL)
                SendMessage(0xB1, -1, -1, RE.hwnd)
            return SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF(text, rules, ignoreCase)), RE.hwnd)
        } else {
            if (SETSEL)
                SendMessage(0xB1, -1, -1, RE.hwnd)
            return SendMessage(0xC2, 1, StrPtr(text), RE.hwnd)
        }
    }
}


class IDE {
    __New(RE, rules) {
        this.RE := RE
        this.rules := rules

        SendMessage(0x0448, 0, 1, this.RE.Hwnd) ; EM_SETTARGETDEVICE
        SendMessage(0x0445, 0, 0x00000001, this.RE.Hwnd) ; EM_SETEVENTMASK, ENM_CHANGE

        OnMessage(0x0111, this.WM_COMMAND.Bind(this)) ; WM_COMMAND
        OnMessage(0x0102, this.WM_CHAR.Bind(this)) ; WM_CHAR
        OnMessage(0x020A, this.WM_MOUSEWHEEL.Bind(this)) ; WM_MOUSEWHEEL

        HotIf((*) => DllCall("GetFocus", "Ptr") == this.RE.hwnd)
        Hotkey("SC00F",  (*) => this.Indent())
        Hotkey("+SC00F", (*) => this.Indent())
        Hotkey("^SC035", (*) => this.Indent())
        Hotkey("^SC02F", (*) {
            SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF(A_Clipboard, this.rules)), this.RE.Hwnd)
            this.SetSel(-1, 0)
        })
        HotIf()
    }


    WM_MOUSEWHEEL(wParam, lParam, msg, hwnd) {
        if (hwnd != this.RE.Hwnd)
            return

        delta := (wParam >> 16)
        if (delta > 0x7FFF)
            delta -= 0x10000 ; (Short)

        if (GetKeyState("Shift", "P")) { ; MK_SHIFT
            Loop 10 ; "скорость" прокрутки
                SendMessage(0x0114, (delta > 0) ? 0 : 1, 0, this.RE.Hwnd) ; WM_HSCROLL
            return 0
        }
    }


    WM_CHAR(wParam, lParam, msg, hwnd) {
        if (hwnd != this.RE.hwnd)
            return

        switch Chr(wParam) {
            case '"' : return InsertChars('""')
            case "'" : return InsertChars("''")
            case "[" : return InsertChars("[]")
            case "{" : return InsertChars("{}")
            case "(" : return InsertChars("()")
        }

        InsertChars(chars) {
            SendMessage(0xC2, 1, StrPtr(chars), this.RE.Hwnd)
            this.SetSel(-1, 0)

            DllCall("SendMessage", "Ptr", this.RE.hwnd, "UInt", 0x00B0, "Ptr*", &start := 0, "Ptr*", &end := 0) ; EM_GETSEL
            if (start > 0 && start == end) {
                this.SetSel(start - 1, start - 1)
            }
            return 0
        }
    }


    WM_COMMAND(wParam, lParam, msg, hwnd) {
        static EN_CHANGE := 0x300
        if (lParam = this.RE.Hwnd) {
            notificationCode := (wParam >> 16) & 0xFFFF
            if (notificationCode = EN_CHANGE && !GetKeyState("SC01D") && !GetKeyState("SC02C")) {
                this.Highlight()
            }
        }
    }


    ; Highlight() {
    ;     Critical(-1)
    ;     sel := this.GetSel()
    ;     SendMessage(0x000B, 0, 0, this.RE.Hwnd) ; WM_SETREDRAW = FALSE
    ;     this.SetSel(0, -1)
    ;     SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF(RTrim(this.RE.Text, "`n"), this.rules)), this.RE.Hwnd)
    ;     ;this.SetSel(-1, -1)
    ;     this.SetSel(sel.Start, sel.End)
    ;     SendMessage(0x000B, 1, 0, this.RE.Hwnd) ; WM_SETREDRAW = TRUE
    ;     DllCall("InvalidateRect", "Ptr", this.RE.Hwnd, "Ptr", 0, "Int", 1)
    ; }


    Highlight() {
        Critical(-1)
        sel := this.GetSel()
        
        SendMessage(0x000B, 0, 0, this.RE.Hwnd) ; WM_SETREDRAW = FALSE


        pt := Buffer(8, 0) ; X и Y в структуру POINT
        SendMessage(0x04DD, 0, pt.Ptr, this.RE.Hwnd) ; EM_GETSCROLLPOS

        lineNumber := SendMessage(0x00C9, -1, 0, this.RE.Hwnd) ; EM_LINEFROMCHAR
        startPos   := SendMessage(0x00BB, lineNumber, 0, this.RE.Hwnd) ; EM_LINEINDEX
        lineLength := SendMessage(0x00C1, startPos, 0, this.RE.Hwnd) ; EM_LINELENGTH

        lineText := ""
        if (lineLength > 0) {
            buf := Buffer((lineLength + 1) * 2, 0)
            NumPut("UShort", lineLength, buf)
            charsCopied := SendMessage(0x00C4, lineNumber, buf, this.RE.Hwnd) ; EM_GETLINE
            lineText := StrGet(buf, charsCopied, "UTF-16")
        }

        endPos := startPos + lineLength
        this.SetSel(startPos, endPos)
        SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF(lineText, this.rules)), this.RE.Hwnd) ; EM_REPLACESEL
        this.SetSel(sel.Start, sel.End)

        SendMessage(0x04DE, 0, pt.Ptr, this.RE.Hwnd) ; EM_SETSCROLLPOS

        SendMessage(0x000B, 1, 0, this.RE.Hwnd) ; WM_SETREDRAW = TRUE
        DllCall("InvalidateRect", "Ptr", this.RE.Hwnd, "Ptr", 0, "Int", 1)
    }


    SetSel(Start, End) {
        CR := Buffer(8, 0)
        NumPut("Int", Start, "Int", End, CR)
        SendMessage(0x0437, 0, CR.Ptr, this.RE.Hwnd)
    }


    GetSel() {
        CR := Buffer(8)
        SendMessage(0x0434, 0, CR, this.RE.Hwnd)
        return {Start: NumGet(CR, 0, "Int"), End: NumGet(CR, 4, "Int") }
    }


    GetSelText() {
        txt := ""
        sel := this.GetSel()
        txtLen := sel.End - sel.Start + 1
        if (txtLen > 1) {
            buf := Buffer(txtLen * 2)
            SendMessage(0x043E, 0, buf, this.RE.Hwnd) ; EM_GETSELTEXT
            txt := StrGet(buf, "UTF-16")
        }
        return txt
    }


    Indent(*) {
        output := ""
        text   := this.GetSelText()
        sel    := this.GetSel()
        startLine       := SendMessage(0x00C9, sel.Start, 0, this.RE.Hwnd) ; EM_LINEFROMCHAR
        endLine         := SendMessage(0x00C9, sel.End, 0, this.RE.Hwnd)
        startPos        := SendMessage(0x00BB, startLine, 0, this.RE.Hwnd)
        endLineStartPos := SendMessage(0x00BB, endLine, 0, this.RE.Hwnd)
        endLineLen      := SendMessage(0x00C1, endLineStartPos, 0, this.RE.Hwnd) ; EM_LINELENGTH
        endPos          := endLineStartPos + endLineLen

        if (sel.Start == sel.End) {
            if (A_ThisHotkey == "SC00F") {
                SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF("`t", this.rules)), this.RE.Hwnd) ; EM_REPLACESEL
            } else if (A_ThisHotkey == "+SC00F") {
                this.SetSel(startPos, endPos)
                text := RegExReplace(this.GetSelText(), "(?m)^(`t| {1,4})", "")
                SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF(text, this.rules)), this.RE.Hwnd)
            } else if (A_ThisHotkey == "^SC035") {
                this.SetSel(startPos, endPos)
                text := RegExReplace(this.GetSelText(), "(?m)^(//)", "", &count)
                if (count == 0)
                    text := RegExReplace(this.GetSelText(), "(?m)^", "//", &count)
                SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF(text, this.rules)), this.RE.Hwnd)
            }
            this.SetSel(-1, 0)
            return
        }

        if (startLine != endLine) {
            lineStartIndex := SendMessage(0x00BB, endLine, 0, this.RE.Hwnd) ; EM_LINEINDEX
            if (sel.End == lineStartIndex)
                endLine -= 1
        }

        this.SetSel(startPos, endPos)

        if (A_ThisHotkey == "SC00F") {
            text := RegExReplace(text, "(?m)^", "`t") ; Tab:
        } else if (A_ThisHotkey == "+SC00F") {
            text := RegExReplace(text, "(?m)^(`t| {1,4})", "") ; Shift+Tab:
        } else if (A_ThisHotkey == "^SC035") {
            text := RegExReplace(this.GetSelText(), "(?m)^(//)", "", &count)
            if (count == 0)
                    text := RegExReplace(this.GetSelText(), "(?m)^", "//", &count)
        }

        for line in StrSplit(text, "`r") {
            output .= line "`n"
        }

        SendMessage(0xC2, 1, StrPtr(RTF.GenerateRTF(RTrim(output, "`n`r"), this.rules)), this.RE.Hwnd) ; EM_REPLACESEL

        ;/////////
        newEndLineStartPos := SendMessage(0x00BB, endLine, 0, this.RE.Hwnd)
        newEndLineLen := SendMessage(0x00C1, newEndLineStartPos, 0, this.RE.Hwnd)
        this.SetSel(startPos, newEndLineStartPos + newEndLineLen)
    }
}
global GLOBAL_WORKING_DIR        := A_Temp "\MCODE"
global GLOBAL_WORKING_OUTPUT_DIR := GLOBAL_WORKING_DIR "\Output"
global GLOBAL_INI_FILE           := GLOBAL_WORKING_DIR "\settings.ini"


global GLOBAL_MCODE_FUNC_FINAL := "
(
GetMcodePtr(x64 := "", x86 := "") {
    p := A_PtrSize, code := StrSplit(RegExReplace(p=8 ? x64 : x86, "\s+"), "|")
    if ((SubStr(code[1], 1, 1) == "$")) {
        oSize   := Integer("0x" SubStr(code[1], 2, 6))
        cmpFmt  := Integer(SubStr(code[1], 8, 1))
        code[1] := SubStr(code[1], 9)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", cbuf := Buffer(size), "UInt*", size, "Ptr", 0, "Ptr", 0)
        DllCall("ntdll\RtlDecompressBuffer", "UShort", cmpFmt, "Ptr", ubuf := Buffer(oSize), "UInt", oSize, "Ptr", cbuf, "UInt", size, "UInt*", &sz := 0, "UInt")
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * 16, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", ubuf, "Ptr", oSize)
    } else {
        crypt := RegExMatch(code[1], "^[0-9a-fA-F]+$") ? 12 : 1
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", 0, "UInt*", &sz := 0, "Ptr", 0, "Ptr", 0)
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * 16, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", ptr, "UInt*", sz, "Ptr", 0, "Ptr", 0)
    }
    
    iatOffset := 0
    Loop (code.Length - 1) {
        item := StrSplit(code[A_Index + 1], ":")
        if (item[1] == "VA") {
            VAsz := Integer(item[2]), offset := Integer(item[3])
            val := NumGet(ptr + offset, VAsz == 8 ? "UInt64" : "UInt")
            NumPut(VAsz == 8 ? "UInt64" : "UInt", val + ptr, ptr + offset)
            continue
        }
        
        pFunc := DllCall("GetProcAddress", "Ptr", DllCall("LoadLibrary", "Str", item[1], "Ptr"), "AStr", item[2], "Ptr")
        patchOffset := Integer(item[3]), disp := Integer(item[4])
        pEntry := ptr + sz + iatOffset

        opcode := NumGet(ptr + patchOffset - 1, "UChar")
        if (opcode == 0xE8 || opcode == 0xE9) {
            if (p == 8) {
                NumPut("UShort", 0x25FF, "UInt", 0x00000000, "Ptr", pFunc, pEntry)
                NumPut("Int", pEntry - (ptr + patchOffset + disp), ptr + patchOffset)
                iatOffset += 16
            } else {
                NumPut("Int", pFunc - (ptr + patchOffset + disp), ptr + patchOffset)
            }
        } else {
            NumPut("Ptr", pFunc, pEntry)
            if (p == 8) {
                NumPut("Int", pEntry - (ptr + patchOffset + disp), ptr + patchOffset)
            } else {
                NumPut("UInt", pEntry, ptr + patchOffset)
            }
            iatOffset += p
        }
    }
    return ptr
}
)"


global GLOBAL_MCODE_FUNC_V4 := "
(
GetMcodePtr(x64 := "", x86 := "") {
    p := A_PtrSize, code := StrSplit(RegExReplace(p=8 ? x64 : x86, "\s+"), "|")
    if ((SubStr(code[1], 1, 1) == "$")) {
        oSize   := Integer("0x" SubStr(code[1], 2, 6))
        cmpFmt  := Integer(SubStr(code[1], 8, 1))
        code[1] := SubStr(code[1], 9)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", cbuf := Buffer(size), "UInt*", size, "Ptr", 0, "Ptr", 0)
        DllCall("ntdll\RtlDecompressBuffer", "UShort", cmpFmt, "Ptr", ubuf := Buffer(oSize), "UInt", oSize, "Ptr", cbuf, "UInt", size, "UInt*", &sz := 0, "UInt")
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * 16, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", ubuf, "Ptr", oSize)
    } else {
        crypt := RegExMatch(code[1], "^[0-9a-fA-F]+$") ? 12 : 1
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", 0, "UInt*", &sz := 0, "Ptr", 0, "Ptr", 0)
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * 16, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", ptr, "UInt*", sz, "Ptr", 0, "Ptr", 0)
    }
    
    iatOffset := 0
    Loop (code.Length - 1) {
        item := StrSplit(code[A_Index + 1], ":")
        if (item[1] == "VA") {
            VAsz := Integer(item[2]), offset := Integer(item[3])
            val := NumGet(ptr + offset, VAsz == 8 ? "UInt64" : "UInt")
            NumPut(VAsz == 8 ? "UInt64" : "UInt", val + ptr, ptr + offset)
            continue
        }
        
        pFunc := DllCall("GetProcAddress", "Ptr", DllCall("LoadLibrary", "Str", item[1], "Ptr"), "AStr", item[2], "Ptr")
        patchOffset := Integer(item[3]), disp := Integer(item[4])
        pEntry := ptr + sz + iatOffset

        opcode := NumGet(ptr + patchOffset - 1, "UChar")
        if (opcode == 0xE8 || opcode == 0xE9) {
            if (p == 8) {
                ; x64 Thunk (14 байт) -> JMP [RIP+0] + абсолютный адрес
                NumPut("UShort", 0x25FF, pEntry)        ; jmp FF 25
                NumPut("UInt", 0x00000000, pEntry + 2)  ; 00 00 00 00 (RIP offset = 0)
                NumPut("Ptr", pFunc, pEntry + 6)        ; 8 байт адреса функции
                ; Патчим оригинальный E8/E9 так, чтобы он указывал на Thunk
                NumPut("Int", pEntry - (ptr + patchOffset + disp), ptr + patchOffset)
                iatOffset += 16 ; Сдвигаем смещение с учетом выравнивания
            } else {
                ; В x86 Thunk не нужен вообще, можно прыгнуть из E8 прямо в API функцию
                NumPut("Int", pFunc - (ptr + patchOffset + disp), ptr + patchOffset)
            }
        } else {
            ; Стандартная IAT запись (например для FF 15 - косвенный вызов)
            NumPut("Ptr", pFunc, pEntry)
            if (p == 8) {
                NumPut("Int", pEntry - (ptr + patchOffset + disp), ptr + patchOffset)
            } else {
                NumPut("UInt", pEntry, ptr + patchOffset)
            }
            iatOffset += p
        }
    }
    return ptr
}
)"


global GLOBAL_MCODE_FUNC_V3 := "
(
GetMcodePtr(x64 := "", x86 := "") {
    p := A_PtrSize, code := StrSplit(RegExReplace(p=8 ? x64 : x86, "\s+"), "|"), iatIndex := 0
    if ((SubStr(code[1], 1, 1) == "$")) {
        oSize   := Integer("0x" SubStr(code[1], 2, 6))
        cmpFmt  := Integer(SubStr(code[1], 8, 1))
        code[1] := SubStr(code[1], 9)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", cbuf := Buffer(size), "UInt*", size, "Ptr", 0, "Ptr", 0)
        DllCall("ntdll\RtlDecompressBuffer", "UShort", cmpFmt, "Ptr", ubuf := Buffer(oSize), "UInt", oSize, "Ptr", cbuf, "UInt", size, "UInt*", &sz := 0, "UInt")
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * p, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", ubuf, "Ptr", oSize)
    } else {
        crypt := RegExMatch(code[1], "^[0-9a-fA-F]+$") ? 12 : 1
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", 0, "UInt*", &sz := 0, "Ptr", 0, "Ptr", 0)
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * p, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", ptr, "UInt*", sz, "Ptr", 0, "Ptr", 0)
    }
    Loop (code.Length - 1) {
        item := StrSplit(code[A_Index + 1], ":")
        if (item[1] == "VA") {
            VAsz := Integer(item[2]), offset := Integer(item[3])
            val := NumGet(ptr + offset, VAsz == 8 ? "UInt64" : "UInt")
            NumPut(VAsz == 8 ? "UInt64" : "UInt", val + ptr, ptr + offset)
            continue
        }
        pFunc := DllCall("GetProcAddress", "Ptr", DllCall("LoadLibrary", "Str", item[1], "Ptr"), "AStr", item[2], "Ptr")
        patchOffset := Integer(item[3]), disp := Integer(item[4])
        pEntry := ptr + sz + (iatIndex * p)
        NumPut("Ptr", pFunc, pEntry)
        NumPut(p = 8 ? "Int" : "UInt", p = 8 ? pEntry - (ptr + patchOffset + disp) : pEntry, ptr + patchOffset)
        iatIndex++
    }
    return ptr
}
)"


global GLOBAL_MCODE_FUNC_V2 := "
(
GetMcodePtr(x64 := "", x86 := "") {
    p := A_PtrSize, code := StrSplit(RegExReplace(p=8 ? x64 : x86, "\s+"), "|"), iatIndex := 0
    if ((SubStr(code[1], 1, 1) == "$")) {
        oSize   := Integer("0x" SubStr(code[1], 2, 6))
        cmpFmt  := Integer(SubStr(code[1], 8, 1))
        code[1] := SubStr(code[1], 9)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", cbuf := Buffer(size), "UInt*", size, "Ptr", 0, "Ptr", 0)
        DllCall("ntdll\RtlDecompressBuffer", "UShort", cmpFmt, "Ptr", ubuf := Buffer(oSize), "UInt", oSize, "Ptr", cbuf, "UInt", size, "UInt*", &sz := 0, "UInt")
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * p, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", ubuf, "Ptr", oSize)
    } else {
        crypt := RegExMatch(code[1], "^[0-9a-fA-F]+$") ? 12 : 1
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", 0, "UInt*", &sz := 0, "Ptr", 0, "Ptr", 0)
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * p, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", ptr, "UInt*", sz, "Ptr", 0, "Ptr", 0)
    }
    Loop (code.Length - 1) {
        item := StrSplit(code[A_Index + 1], ":")
        if (item[1] == "VA") {
            sz := Integer(item[2]), offset := Integer(item[3])
            val := NumGet(ptr + offset, sz == 8 ? "UInt64" : "UInt")
            NumPut(sz == 8 ? "UInt64" : "UInt", val + ptr, ptr + offset)
            continue
        }
        pFunc := DllCall("GetProcAddress", "Ptr", DllCall("LoadLibrary", "Str", item[1], "Ptr"), "AStr", item[2], "Ptr")
        patchOffset := Integer(item[3]), disp := Integer(item[4])
        pEntry := ptr + sz + (iatIndex * p)
        NumPut("Ptr", pFunc, pEntry)
        NumPut(p = 8 ? "Int" : "UInt", p = 8 ? pEntry - (ptr + patchOffset + disp) : pEntry, ptr + patchOffset)
        iatIndex++
    }
    return ptr
}
)"

global GLOBAL_MCODE_FUNC := "
(
GetMcodePtr(x64 := "", x86 := "", p := A_PtrSize) {
    code := StrSplit(RegExReplace(p=8 ? x64 : x86, "\s+"), "|")
    if ((SubStr(code[1], 1, 1) == "$")) {
        oSize   := Integer("0x" SubStr(code[1], 2, 6))
        cmpFmt  := Integer(SubStr(code[1], 8, 1))
        code[1] := SubStr(code[1], 9)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", 1, "Ptr", cbuf := Buffer(size), "UInt*", size, "Ptr", 0, "Ptr", 0)
        DllCall("ntdll\RtlDecompressBuffer", "UShort", cmpFmt, "Ptr", ubuf := Buffer(oSize), "UInt", oSize, "Ptr", cbuf, "UInt", size, "UInt*", &sz := 0, "UInt")
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * p, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("RtlMoveMemory", "Ptr", ptr, "Ptr", ubuf, "Ptr", oSize)
    } else {
        crypt := RegExMatch(code[1], "^[0-9a-fA-F]+$") ? 12 : 1
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", 0, "UInt*", &sz := 0, "Ptr", 0, "Ptr", 0)
        ptr := DllCall("VirtualAlloc", "Ptr", 0, "Ptr", sz + (code.Length - 1) * p, "UInt", 0x3000, "UInt", 0x40, "Ptr")
        DllCall("Crypt32\CryptStringToBinary", "Str", code[1], "UInt", 0, "UInt", crypt, "Ptr", ptr, "UInt*", sz, "Ptr", 0, "Ptr", 0)
    }
    Loop (code.Length - 1) {
        i := StrSplit(code[A_Index + 1], ":")
        pFunc := DllCall("GetProcAddress", "Ptr", DllCall("LoadLibrary", "Str", i[1], "Ptr"), "AStr", i[2], "Ptr")
        pEntry := ptr + sz + (A_Index - 1) * p
        NumPut("Ptr", pFunc, pEntry)
        NumPut(p = 8 ? "Int" : "UInt", p = 8 ? pEntry - (ptr + i[3] + 4) : pEntry, ptr + i[3])
    }
    return ptr
}
)"

global GLOBAL_DEFAULT_LINKER_SCRIPT := "
(
SECTIONS
{
    . = 0;

    .text :
    {
        *(.text*)
        *(.rdata*)
        *(.rodata*)
        *(.data*)
        *(.bss*)
    }

    /DISCARD/ :
    {
        *(.eh_frame)
        *(.pdata)
        *(.xdata)
        *(.reloc)
    }
}
)"

global GLOBAL_C_CODE := "
(
const char* func() {
	return "Hello World!!!";
}
)"

global ASCII_MCODE := "
(
___  ________ ___________ _____ 
|  \/  /  __ \  _  |  _  \  ___|
| .  . | /  \/ | | | | | | |__  
| |\/| | |   | | | | | | |  __| 
| |  | | \__/\ \_/ / |/ /| |___ 
\_|  |_/\____/\___/|___/ \____/ 
)"
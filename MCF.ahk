#Requires AutoHotkey v2.0
#SingleInstance Force
#Include const.ahk
#Include Static_Library_Viewer.ahk
#Include Lib\Demangle.ahk

class Binary {
    static BinaryToStrin(bin, len, flag) {
        DllCall("Crypt32\CryptBinaryToStringW", "Ptr", bin, "UInt", len, "UInt", 0x40000000 | flag, "Ptr", 0, "UInt*", &size := 0)
        DllCall("Crypt32\CryptBinaryToStringW", "Ptr", bin, "UInt", len, "UInt", 0x40000000 | flag, "Ptr", out := Buffer(size * 2), "UInt*", size)
        return StrGet(out, "UTF-16")
    }


    static StringToBinary(str, flag) {
        DllCall("Crypt32\CryptStringToBinaryW", "Str", str, "UInt", 0, "UInt", flag, "Ptr", 0, "UInt*", &size := 0, "Ptr", 0, "Ptr", 0)
        DllCall("Crypt32\CryptStringToBinaryW", "Str", str, "UInt", 0, "UInt", flag, "Ptr", bin := Buffer(size), "UInt*", size, "Ptr", 0, "Ptr", 0)
        return {Ptr: bin, size: size}
    }


    static HexToBase64(hex) {
        o := this.StringToBinary(hex, 12)
        return this.BinaryToStrin(o.Ptr, o.size, 1)
    }


    static Base64ToHex(base64) {
        o := this.StringToBinary(base64, 1)
        return this.BinaryToStrin(o.Ptr, o.size, 12)
    }


    static CompressBuffer(inputBuf, inputSize, compressionFormat) {
        DllCall("ntdll\RtlGetCompressionWorkSpaceSize", "UShort", compressionFormat, "UInt*", &workSpaceSize := 0, "UInt*", &fragmentWorkSpaceSize := 0, "UInt")
        workSpace     := Buffer(workSpaceSize)
        compressedBuf := Buffer(inputSize * 2)

        status := DllCall("ntdll\RtlCompressBuffer", "UShort", compressionFormat + 0x0100, "Ptr", inputBuf, "UInt", inputSize, "Ptr", compressedBuf, "UInt", compressedBuf.Size,
        "UInt", 4096, "UInt*", &finalCompressedSize := 0, "Ptr", workSpace, "UInt")

        if (status != 0)
            throw Error("RtlCompressBuffer failed: " Format("0x{:08X}", status))
        return {buf: compressedBuf, size: finalCompressedSize}
    }


    static DecompressBuffer(compressedBuf, compressedSize, uncompressedSize, compressionFormat) {
        outputBuf := Buffer(uncompressedSize)
        
        status := DllCall("ntdll\RtlDecompressBuffer", "UShort", compressionFormat + 0x0100, "Ptr", outputBuf, "UInt", uncompressedSize, "Ptr", compressedBuf, "UInt", compressedSize,
        "UInt*", &finalUncompressedSize := 0, "UInt")
        
        if (status != 0)
            throw Error("RtlDecompressBuffer failed: " Format("0x{:08X}", status))
        
        return {buf: outputBuf, size: finalUncompressedSize}
    }


    static HexToCompressedBase64(hex, compressionFormat := 0x0002) {
        if (StrLen(hex) <= 2)
            return hex
        try {
            o := this.StringToBinary(hex, 12)
            compressed := this.CompressBuffer(o.Ptr, o.size, compressionFormat)
            metadata := Format("{:06X}", o.size) . Format("{:01X}", compressionFormat)
            return "$" . metadata . this.BinaryToStrin(compressed.buf, compressed.size, 1)
        } catch Error as e {
            return e.Message
        }
    }


    static BinaryToCompressedBase64(bin, size, compressionFormat := 0x0002) {
        try {
            compressed := this.CompressBuffer(bin, size, compressionFormat)
            metadata := Format("{:06X}", size) . Format("{:01X}", compressionFormat)
            return "$" . metadata . this.BinaryToStrin(compressed.buf, compressed.size, 1)
        } catch Error as e {
            return e.Message
        }
    }


    static DecompressedBase64ToHex(base64) {
        try {
            metadata          := SubStr(base64, 1, 8)
            cType             := SubStr(base64, 1, 1)
            originalSize      := Integer("0x" SubStr(base64, 2, 6))
            compressionFormat := Integer(SubStr(base64, 8, 1))
            base64 := StrReplace(base64, metadata)
            o := this.StringToBinary(base64, 1)
            decompressed := this.DecompressBuffer(o.Ptr, o.size, originalSize, compressionFormat)
            return this.BinaryToStrin(decompressed.buf, decompressed.size, 12)
        } catch Error as e {
            return e.Message
        }
    }


    static HexToASCII(data, size, bytesPerLine := 8) {
        hex := "", ascii := "", result := ""
        loop (size) {
            byte := NumGet(data, A_Index - 1, "UChar")
            hex .= Format("{:02X} ", byte)
            ascii .= (byte >= 32 && byte <= 126) ? Chr(byte) " " : ". "

            if (Mod(A_Index, bytesPerLine) = 0 || A_Index = size) {
                bytesInLine := Mod(A_Index, bytesPerLine)
                (bytesInLine = 0) and bytesInLine := bytesPerLine
                Loop (bytesPerLine - bytesInLine) * 3  ; 3 символа на байт (XX + пробел)
                    hex .= " "
                result .= hex . "| " . Trim(ascii) . "`n"
                hex := "", ascii := ""
            }
        }
        return Trim(result, "`n")
    }


    static ExtractHexBytes(data) {
        cleaned := RegExReplace(data, "\|[^\r\n]*")
        cleaned := RegExReplace(cleaned, "m)^[^:\r\n]*:\t([^\t]*).*$", "$1")
        cleaned := RegExReplace(cleaned, "m)^.*?:.*?(\R|$)", "")
        hexStr := "", pos := 1
        
        while (pos := RegExMatch(cleaned, "[0-9A-Fa-f]+", &m, pos)) {
            if (Mod(m.Len, 2) == 0)
                hexStr .= m[]
            pos += m.Len
        }
        
        if (hexStr == "")
            return Error("Could not find valid bytes in the transferred data.")
        return hexStr
    }


    static ParseObjdumpToMap(objdump, &properties?) {
        result     := Map()
        properties := []
        pos        := 1
        while (pos := RegExMatch(objdump, "is)Disassembly of section\s+(?<Name>[^\r\n:]+):\s*(?<Content>.*?)(?=Disassembly of section|\z)", &m, pos)) {
            rawName  := Trim(m[1])
            content  := Trim(m[0], " `t`r`n")
            result[A_Index " " rawName] := content
            properties.Push(A_Index " " rawName)
            pos += StrLen(m[0])
        }
        ;result["ALL"] := objdump
        return result
    }
}


class COFF {
    static IMAGE_SECTION_HEADER_CHARACTERISTICS := Map(
        "IMAGE_SCN_TYPE_NO_PAD",             0x00000008,
        "IMAGE_SCN_CNT_CODE",                0x00000020,
        "IMAGE_SCN_CNT_INITIALIZED_DATA",    0x00000040,
        "IMAGE_SCN_CNT_UNINITIALIZED_DATA",  0x00000080,
        "IMAGE_SCN_LNK_INFO",                0x00000200,
        "IMAGE_SCN_LNK_REMOVE",              0x00000800,
        "IMAGE_SCN_LNK_COMDAT",              0x00001000,
        "IMAGE_SCN_NO_DEFER_SPEC_EXC",       0x00004000,
        "IMAGE_SCN_GPREL",                   0x00008000,
        "IMAGE_SCN_ALIGN_1BYTES",            0x00100000,
        "IMAGE_SCN_ALIGN_2BYTES",            0x00200000,
        "IMAGE_SCN_ALIGN_4BYTES",            0x00300000,
        "IMAGE_SCN_ALIGN_8BYTES",            0x00400000,
        "IMAGE_SCN_ALIGN_16BYTES",           0x00500000,
        "IMAGE_SCN_ALIGN_32BYTES",           0x00600000,
        "IMAGE_SCN_ALIGN_64BYTES",           0x00700000,
        "IMAGE_SCN_ALIGN_128BYTES",          0x00800000,
        "IMAGE_SCN_ALIGN_256BYTES",          0x00900000,
        "IMAGE_SCN_ALIGN_512BYTES",          0x00A00000,
        "IMAGE_SCN_ALIGN_1024BYTES",         0x00B00000,
        "IMAGE_SCN_ALIGN_2048BYTES",         0x00C00000,
        "IMAGE_SCN_ALIGN_4096BYTES",         0x00D00000,
        "IMAGE_SCN_ALIGN_8192BYTES",         0x00E00000,
        "IMAGE_SCN_LNK_NRELOC_OVFL",         0x01000000,
        "IMAGE_SCN_MEM_DISCARDABLE",         0x02000000,
        "IMAGE_SCN_MEM_NOT_CACHED",          0x04000000,
        "IMAGE_SCN_MEM_NOT_PAGED",           0x08000000,
        "IMAGE_SCN_MEM_SHARED",              0x10000000,
        "IMAGE_SCN_MEM_EXECUTE",             0x20000000,
        "IMAGE_SCN_MEM_READ",                0x40000000,
        "IMAGE_SCN_MEM_WRITE",               0x80000000,
    )

    static IMAGE_FILE_HEADER_CHARACTERISTICS := Map(
        "IMAGE_FILE_RELOCS_STRIPPED",         0x0001,
        "IMAGE_FILE_EXECUTABLE_IMAGE",        0x0002,
        "IMAGE_FILE_LINE_NUMS_STRIPPED",      0x0004,
        "IMAGE_FILE_LOCAL_SYMS_STRIPPED",     0x0008,
        "IMAGE_FILE_AGGRESIVE_WS_TRIM",       0x0010,
        "IMAGE_FILE_LARGE_ADDRESS_AWARE",     0x0020,
        "IMAGE_FILE_BYTES_REVERSED_LO",       0x0080,
        "IMAGE_FILE_32BIT_MACHINE",           0x0100,
        "IMAGE_FILE_DEBUG_STRIPPED",          0x0200,
        "IMAGE_FILE_REMOVABLE_RUN_FROM_SWAP", 0x0400,
        "IMAGE_FILE_NET_RUN_FROM_SWAP",       0x0800,
        "IMAGE_FILE_SYSTEM",                  0x1000,
        "IMAGE_FILE_DLL",                     0x2000,
        "IMAGE_FILE_UP_SYSTEM_ONLY",          0x4000,
        "IMAGE_FILE_BYTES_REVERSED_HI",       0x8000,
    )

    static IMAGE_SYMBOL_STORAGE_CLASS := Map(
        "IMAGE_SYM_CLASS_END_OF_FUNCTION", -1,
        "IMAGE_SYM_CLASS_NULL",             0,
        "IMAGE_SYM_CLASS_AUTOMATIC",        1,
        "IMAGE_SYM_CLASS_EXTERNAL",         2,
        "IMAGE_SYM_CLASS_STATIC",           3,
        "IMAGE_SYM_CLASS_REGISTER",         4,
        "IMAGE_SYM_CLASS_EXTERNAL_DEF",     5,
        "IMAGE_SYM_CLASS_LABEL",            6,
        "IMAGE_SYM_CLASS_UNDEFINED_LABEL",  7,
        "IMAGE_SYM_CLASS_MEMBER_OF_STRUCT", 8,
        "IMAGE_SYM_CLASS_ARGUMENT",         9,
        "IMAGE_SYM_CLASS_STRUCT_TAG",       10,
        "IMAGE_SYM_CLASS_MEMBER_OF_UNION",  11,
        "IMAGE_SYM_CLASS_UNION_TAG",        12,
        "IMAGE_SYM_CLASS_TYPE_DEFINITION",  13,
        "IMAGE_SYM_CLASS_UNDEFINED_STATIC", 14,
        "IMAGE_SYM_CLASS_ENUM_TAG",         15,
        "IMAGE_SYM_CLASS_MEMBER_OF_ENUM",   16,
        "IMAGE_SYM_CLASS_REGISTER_PARAM",   17,
        "IMAGE_SYM_CLASS_BIT_FIELD",        18,
        "IMAGE_SYM_CLASS_BLOCK",            100,
        "IMAGE_SYM_CLASS_FUNCTION",         101,
        "IMAGE_SYM_CLASS_END_OF_STRUCT",    102,
        "IMAGE_SYM_CLASS_FILE",             103,
        "IMAGE_SYM_CLASS_SECTION",          104,
        "IMAGE_SYM_CLASS_WEAK_EXTERNAL",    105,
        "IMAGE_SYM_CLASS_CLR_TOKEN",        107,
    )

    static IMAGE_COMDAT_SELECT_NODUPLICATES := 1
    static IMAGE_COMDAT_SELECT_ANY          := 2
    static IMAGE_COMDAT_SELECT_SAME_SIZE    := 3
    static IMAGE_COMDAT_SELECT_EXACT_MATCH  := 4
    static IMAGE_COMDAT_SELECT_ASSOCIATIVE  := 5
    static IMAGE_COMDAT_SELECT_LARGEST      := 6

    static SIZEOF_IMAGE_SECTION_HEADER := 40
    static SIZEOF_IMAGE_FILE_HEADER    := 20
    static SIZEOF_IMAGE_SYMBOL         := 18
    static SIZEOF_IMAGE_RELOCATION     := 10
    static IMAGE_FILE_MACHINE_I386     := 0x14c  ; x86
    static IMAGE_FILE_MACHINE_AMD64    := 0x8664 ; x64

    MACHINE                 => this.IMAGE_FILE_HEADER(0).Machine              ; 0
    NUMBER_OF_SECTIONS      => this.IMAGE_FILE_HEADER(0).NumberOfSections     ; 2
    TIME_DATE_STAMP         => this.IMAGE_FILE_HEADER(0).TimeDateStamp        ; 4
    POINTER_TO_SYMBOL_TABLE => this.IMAGE_FILE_HEADER(0).PointerToSymbolTable ; 8
    NUMBER_OF_SYMBOLS       => this.IMAGE_FILE_HEADER(0).NumberOfSymbols      ; 12
    SIZE_OF_OPTIONAL_HEADER => this.IMAGE_FILE_HEADER(0).SizeOfOptionalHeader ; 16
    CHARACTERISTICS         => this.IMAGE_FILE_HEADER(0).Characteristics      ; 18

    STRING_TABLE_OFFSET         => this.POINTER_TO_SYMBOL_TABLE + (this.NUMBER_OF_SYMBOLS * COFF.SIZEOF_IMAGE_SYMBOL)
    SECTION_HEADER_TABLE_OFFSET => COFF.SIZEOF_IMAGE_FILE_HEADER + this.SIZE_OF_OPTIONAL_HEADER


    /**
     * @param {String}  path - Путь до COFF (.o / .obj) файла.
     * @param {Array}   importDll - Массив dll которые используются в конечном Mcode (если есть внешнии символы). Например если в вашем Mcode есть функция `MessageBox`, то сюда нужно написать `["User32"]`.
     * Если вы забыли указать все dll, то это не критично, вы просто увидите в конце строки байт `UNKNOWN_DLL:MessageBeep`, а не `User32:MessageBeep`. К слову, вы можете сами вписать все нужные dll в конец Mcode, ничего не сломается.
     * @param {Array}   ignoreSections - Массив секций, которые будут игнорироватся при линковке (в основном сюда ничего не нужно дописывать). Для чего это может быть полезно:
     * Например, GCC любит генерировать секцию `.rdata$zzz` - это версия компилятора (то есть dbg info), в конечном Mcode это не нужно (ради экономии места [меньше байт]), и если вы укажите эту секцию в массив `ignoreSections`, то линковщик будет игнорироваться эту секцию.
     * @param {Integer} fullOffsetTable - Если `fullOffsetTable == false`, то линковщик вернет смещения только нужных символов (функции / глобалки*), в ином случае будет полная таблица всех символов.
     * К слову я без понятия как понять какой символ является "НУЖНЫМ", условно MSVC помечает строки (секции со строками) как StorageClass == 2, а GCC так не делает, так что тут все зависит от компилятора.
     * Но в любом случае, в основном полезно видеть все символы, что бы лучше понимать куда компилятор положил тот или иной код, так что рекомендуется оставлять `fullOffsetTable := true`.
     * @param {Integer} entryPoint - Можно задать точку входа по X смещению для нужной функции. Это актуально если есть две и более функции в одном Mcode... Ну например:
     * Есть три функции `[func1, func2, func3]` их смещения `[0x0, 0x10, 0x50]`. Что бы вызвать func3 нужно написать `DllCall(ptr + 0x50)`, но можно задать точку входа `entryPoint := 0x50`,
     * и тогда не придется писать смещению в ручную - `DllCall(ptr)` вызовет именно func3, а не func1. Пока что в `entryPoint` нет смысла, но в дальнейшем линковщик будет поддерживать сборку Shellcode, и тогда это пригодится.
     * @param {Integer | Array} dynamicLinking - Для функций `malloc`, да и в целом большинства функций из `msvcrt` (например), компилятор подразумевает статическую линковку (генерирует call с опкодом `[E8 00 00 00 00] || [E9 00 00 00 00]`, а не jmp инструкции).
     * Это не есть хорошо, ибо раздувает размер конечного Mcode. `dynamicLinking` позволяет указать массив функций, которые будут 100% слинкованны динамически, а не статически.
     * - Если `dynamicLinking := [dllFunc1, dllFunc2, ...]`, то, если символ из массива `dynamicLinking` найден в `importDll`, то эта функция будет динамически слинвокана (она окажется в IAT). Функция `GetMcodePtr` создаст трамплин `[E8|E9 00 00 00 00 + [FF 25 (PTR)]]`.
     * - Если `dynamicLinking := true`, то абсолютно все символы, которые могут быть динамически слинкованы, будут размещены в IAT.
     * - Если `dynamicLinking := false`, то класс не будет пытаться патчить asm инструкции. То есть, если компилятор подразумевает статическую линковку для определенного символа, то он будет статически слинкован.
     * @param {Array} staticLibraries - Массив экземпляров класса StaticLibraryParser для статической линковки.
     */
    __New(obj, importDll := ["User32", "msvcrt", "Kernel32"], ignoreSections := [".pdata", ".xdata", ".rdata$zzz"], fullOffsetTable := true, entryPoint := 0x0, dynamicLinking := true, staticLibraries := [], dynamicSubstitution := Map(), staticSubstitution := Map(), demangleLvl := 1) {
        this.obj                 := obj                 ; Путь до COFF (.o / .obj) файла.
        this.importDll           := importDll           ; Массив dll которые используются в конечном Mcode (если есть внешнии символы).
        this.ignoreSections      := ignoreSections      ; Массив секций, которые будут игнорироватся при линковке (в основном сюда ничего не нужно дописывать).
        this.fullOffsetTable     := fullOffsetTable     ; Если fullOffsetTable == false, то линковщик вернет смещения только нужных символов (функции / глобалки*), в ином случае будет полная таблица всех символов.
        this.entryPoint          := entryPoint          ; Точка входа.
        this.dynamicLinking      := dynamicLinking      ; Управление динамической линковкой: false, true или массив конкретных функций.
        this.staticLibraries     := staticLibraries     ; Массив статических библиотек (экземпляры StaticLibraryParser).
        this.dynamicSubstitution := dynamicSubstitution ; Подмена динамических символов.
        this.staticSubstitution  := staticSubstitution  ; Подмена статических символов.
        this.demangleLvl         := demangleLvl         ; Деманглирование символов в таблице смещений. Работает только с GCC / Clang. MSVC не поддерживается.
        this.dbgLogInfo          := ""

        this.imports           := []  ; Массив объектов импортируемых символов из dll (__imp_).
        this.unresolvedSymbols := []  ; Массив объектов неразрешённых символов (статическая линковка).

        this.exportedSymbols := Map() ; Таблица смещений всех функций / секций / глобальных переменных, и тд. которые есть в конечном Mcode.
        this.VAreloc         := []    ; Массив VA релокаций - VirtualAlloc + RVA (известно только при запуске). В 99% случаев VA релокаций не будет в конечном Mcode.
        this.sectionFilter   := []    ; Массив 0 && 1. Фильтрует бесполезные секции при линковке, что бы не захватывать их в конечный Mcode (например это .xdata | .pdata).
        this.alignment       := []    ; Массив выравнивания данных по границе в X байт. Для производительности нужно учитывать выравнивание байт при объединение секций.
        this.headerCharact   := Map() ; Все константы характеристик [key == Idx sec, value == const flags]. Это dbg info.
        this.relocations     := []    ; Массив объектов - содержит все релокации, их тип, symbolIndex, а так же именна секций + функций [IMAGE_RELOCATION()]. Dbg info.
        this.symbolsMap      := Map() ; Все символы COFF [key == symbolIndex, value == IMAGE_SYMBOL()].
        this.sections        := []    ; Массив объектов - содержит все секции COFF [IMAGE_SECTION_HEADER()].

        if (this.obj is String && FileExist(this.obj)) {
            file      := FileOpen(this.obj, "r")
            this.size := file.Length
            this.ptr  := Buffer(this.size)
            file.RawRead(this.ptr)
            file.Close()
        } else if (HasProp(this.obj, "Ptr") && HasProp(this.obj, "Size")) {
            this.size := this.obj.Size
            this.ptr  := {Ptr: this.obj.Ptr, Size: this.obj.Size}
        } else {
            throw Error("Invalid object input type.")
        }

        this.is64 := this.IMAGE_FILE_HEADER(0).Machine == COFF.IMAGE_FILE_MACHINE_AMD64
        this.is32 := this.IMAGE_FILE_HEADER(0).Machine == COFF.IMAGE_FILE_MACHINE_I386
        if (this.is32 + this.is64 != 1)
           throw Error("Not a valid 32/64 bit COFF file...")

        this.ReadSymbol()
        this.ReadSection()
        this.ReadComdatInfo()
        this.HeaderCharacteristics()
    }


    IMAGE_RELOCATION(offset) {
        return {
            VirtualAddress:   NumGet(this.ptr, offset + 0, "UInt"),
           ;RelocCount:       NumGet(this.ptr, offset + 4, "UInt"),
            SymbolTableIndex: NumGet(this.ptr, offset + 4, "UInt"),
            Type:             NumGet(this.ptr, offset + 8, "UShort"),
        }
    }


    IMAGE_FILE_HEADER(offset) {
        return {
            Machine:              NumGet(this.ptr, offset + 0,  "UShort"),
            NumberOfSections:     NumGet(this.ptr, offset + 2,  "UShort"),
            TimeDateStamp:        NumGet(this.ptr, offset + 4,  "UInt"),
            PointerToSymbolTable: NumGet(this.ptr, offset + 8,  "UInt"),
            NumberOfSymbols:      NumGet(this.ptr, offset + 12, "UInt"),
            SizeOfOptionalHeader: NumGet(this.ptr, offset + 16, "UShort"),
            Characteristics:      NumGet(this.ptr, offset + 18, "UShort"),
        }
    }


    IMAGE_SECTION_HEADER(offset) {
        Name := StrGet(this.ptr.Ptr + offset, 8, "UTF-8")
        if (InStr(Name, "/")) {
            offStr := Integer(StrReplace(Name, "/", ""))
            Name := StrGet(this.ptr.Ptr + this.STRING_TABLE_OFFSET + offStr, "UTF-8") ; .rdata$zzz
        }
        return {
            Name:                 Name,
            VirtualSize:          NumGet(this.ptr, offset + 8,  "UInt"), ; PhysicalAddress / VirtualSize
            VirtualAddress:       NumGet(this.ptr, offset + 12, "UInt"),
            SizeOfRawData:        NumGet(this.ptr, offset + 16, "UInt"),
            PointerToRawData:     NumGet(this.ptr, offset + 20, "UInt"),
            PointerToRelocations: NumGet(this.ptr, offset + 24, "UInt"),
            PointerToLinenumbers: NumGet(this.ptr, offset + 28, "UInt"),
            NumberOfRelocations:  NumGet(this.ptr, offset + 32, "UShort"),
            NumberOfLinenumbers:  NumGet(this.ptr, offset + 34, "UShort"),
            Characteristics:      NumGet(this.ptr, offset + 36, "UInt"),
        }
    }


    IMAGE_SYMBOL(offset) {
        if (NumGet(this.ptr, offset, "UInt")) {
            Name := StrGet(this.ptr.Ptr + offset, 8, "UTF-8")
        } else {
            Name := StrGet(this.ptr.Ptr + this.STRING_TABLE_OFFSET + NumGet(this.ptr, offset + 4, "UInt"), "UTF-8")
        }

        return {
            Name:               Name,
            Value:              NumGet(this.ptr, offset + 8,  "UInt"),
            SectionIndex:       NumGet(this.ptr, offset + 12, "Short"), ; SectionNumber / SectionIndex
            Type:               NumGet(this.ptr, offset + 14, "UShort"),
            StorageClass:       NumGet(this.ptr, offset + 16, "UChar"),
            NumberOfAuxSymbols: NumGet(this.ptr, offset + 17, "UChar"),
        }
    }


    ReadSymbol() {
        this.weakExternals := Map()
        symbolIndex := 0
        while (symbolIndex < this.NUMBER_OF_SYMBOLS) {
            symOffset  := this.POINTER_TO_SYMBOL_TABLE + (symbolIndex * COFF.SIZEOF_IMAGE_SYMBOL)
            nextSymbol := this.IMAGE_SYMBOL(symOffset)
            this.symbolsMap[symbolIndex] := nextSymbol

            ; парсинг aux для WEAK_EXTERNAL
            if (nextSymbol.StorageClass == 105 && nextSymbol.NumberOfAuxSymbols > 0) {
                auxOffset := this.POINTER_TO_SYMBOL_TABLE + ((symbolIndex + 1) * COFF.SIZEOF_IMAGE_SYMBOL)
                this.weakExternals[symbolIndex] := {
                    TagIndex:        NumGet(this.ptr, auxOffset + 0, "UInt"),
                    Characteristics: NumGet(this.ptr, auxOffset + 4, "UInt")
                }
            }

            symbolIndex += 1 + nextSymbol.NumberOfAuxSymbols ; Стандартный пропуск: +1 сам символ, +NumberOfAuxSymbols его доп записи
        }
    }


    ReadSection() {
        loop (this.NUMBER_OF_SECTIONS) {
            section := this.IMAGE_SECTION_HEADER(this.SECTION_HEADER_TABLE_OFFSET + ((A_Index - 1) * COFF.SIZEOF_IMAGE_SECTION_HEADER))
            
            loop (section.NumberOfRelocations) {
                relocOffset := section.PointerToRelocations + ((A_Index - 1) * COFF.SIZEOF_IMAGE_RELOCATION)
                reloc := this.IMAGE_RELOCATION(relocOffset)
                
                funcName := "UNKNOWN_FUNC_NAME"
                symbolIndex := reloc.SymbolTableIndex
                if (this.symbolsMap.Has(symbolIndex)) {
                    funcName := this.symbolsMap[symbolIndex].Name
                }

                this.relocations.Push({reloc: reloc.VirtualAddress, section: funcName, type: reloc.Type, SymbolTableIndex: symbolIndex})
            }
            this.sections.Push(section)
        }
    }


    ReadComdatInfo() {
        this.comdatSections := Map()
        for symIdx, symbol in this.symbolsMap {
            if (symbol.StorageClass == 3 && symbol.NumberOfAuxSymbols > 0 && symbol.SectionIndex > 0) {
                secIdx := symbol.SectionIndex
                if (secIdx > this.sections.Length)
                    continue
                if !(this.sections[secIdx].Characteristics & COFF.IMAGE_SECTION_HEADER_CHARACTERISTICS.Get("IMAGE_SCN_LNK_COMDAT"))
                    continue

                auxOffset := this.POINTER_TO_SYMBOL_TABLE + ((symIdx + 1) * COFF.SIZEOF_IMAGE_SYMBOL)
                
                ; Ищем настоящее имя COMDAT - ключом является имя EXTERNAL символа, указывающего на эту секцию.
                realComdatName := symbol.Name 
                for _, extSym in this.symbolsMap {
                    if (extSym.SectionIndex == secIdx && extSym.StorageClass == 2) {
                        realComdatName := extSym.Name
                        break
                    }
                }

                this.comdatSections[secIdx] := {
                    Length:       NumGet(this.ptr, auxOffset + 0,  "UInt"),
                    NumRelocs:    NumGet(this.ptr, auxOffset + 4,  "UShort"),
                    NumLineNums:  NumGet(this.ptr, auxOffset + 6,  "UShort"),
                    CheckSum:     NumGet(this.ptr, auxOffset + 8,  "UInt"),
                    AssocSection: NumGet(this.ptr, auxOffset + 12, "UShort"),
                    Selection:    NumGet(this.ptr, auxOffset + 14, "UChar"),
                    SymbolName:   realComdatName ; найденное имя функции, а не секции (.text$mn например)
                }
            }
        }
    }


    HeaderCharacteristics() {
        static ALIGN_MASK                := 0x00F00000
        static IMAGE_SCN_LNK_REMOVE      := 0x00000800
        static IMAGE_SCN_LNK_INFO        := 0x00000200
        static IMAGE_SCN_MEM_DISCARDABLE := 0x02000000

        for i, sec in this.sections {
            charact    := []
            hasAlign   := false
            isUseless  := false

            if (sec.Characteristics & IMAGE_SCN_LNK_REMOVE) || (sec.Characteristics & IMAGE_SCN_LNK_INFO) || (sec.Characteristics & IMAGE_SCN_MEM_DISCARDABLE) {
                isUseless := true
            }

            if (!isUseless) {
                for ignoreName in this.ignoreSections {
                    if (sec.Name == ignoreName) {
                        isUseless := true
                        break
                    }
                }
            }

            alignBytes := 0
            for name, value in COFF.IMAGE_SECTION_HEADER_CHARACTERISTICS {
                if InStr(name, "ALIGN") {
                    if ((sec.Characteristics & ALIGN_MASK) == value) {
                        charact.Push(name)
                        hasAlign := true
                        alignBytes := RegExReplace(name, "\D+", "")
                    }
                } else {
                    if (sec.Characteristics & value)
                        charact.Push(name)
                }
            }
            this.alignment.Push(hasAlign ? (alignBytes != "" ? Integer(alignBytes) : 4) : 4)
            this.headerCharact[i " " sec.Name] := charact ; dbg info [ПОТОМ ДОДЕЛАТЬ]
            this.sectionFilter.Push(isUseless ? 1 : 0) ; Нужные секции для линковки
        }
    }


    ApplyRelocation(mcode, targetAddress, patchAddress, relocType) {
        static IMAGE_REL_AMD64_ABSOLUTE := 0x0000
        static IMAGE_REL_AMD64_ADDR64   := 0x0001
        static IMAGE_REL_AMD64_ADDR32   := 0x0002
        static IMAGE_REL_AMD64_ADDR32NB := 0x0003
        static IMAGE_REL_AMD64_REL32    := 0x0004
        static IMAGE_REL_AMD64_REL32_1  := 0x0005
        static IMAGE_REL_AMD64_REL32_2  := 0x0006
        static IMAGE_REL_AMD64_REL32_3  := 0x0007
        static IMAGE_REL_AMD64_REL32_4  := 0x0008
        static IMAGE_REL_AMD64_REL32_5  := 0x0009

        static IMAGE_REL_I386_ABSOLUTE := 0x0000
        static IMAGE_REL_I386_DIR32    := 0x0006
        static IMAGE_REL_I386_DIR32NB  := 0x0007
        static IMAGE_REL_I386_REL32    := 0x0014

        if (this.is64) {
            switch relocType {
                case IMAGE_REL_AMD64_ABSOLUTE : return
                case IMAGE_REL_AMD64_ADDR64   : NumPut("Int64", targetAddress + NumGet(mcode, patchAddress, "Int64"), mcode, patchAddress), this.VAreloc.Push({offset: patchAddress, size: 8})
                case IMAGE_REL_AMD64_ADDR32   : NumPut("UInt",  targetAddress + NumGet(mcode, patchAddress, "UInt"), mcode, patchAddress), this.VAreloc.Push({offset: patchAddress, size: 4})
                case IMAGE_REL_AMD64_ADDR32NB : NumPut("UInt",  targetAddress + NumGet(mcode, patchAddress, "UInt"), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32    : NumPut("Int",   targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 4), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_1  : NumPut("Int",   targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 5), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_2  : NumPut("Int",   targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 6), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_3  : NumPut("Int",   targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 7), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_4  : NumPut("Int",   targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 8), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_5  : NumPut("Int",   targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 9), mcode, patchAddress)
                default: throw Error(Format("Unsupported relocation type [x64]: 0x{:04X}", relocType))
            }
        } else {
            switch relocType {
                case IMAGE_REL_I386_ABSOLUTE : return
                case IMAGE_REL_I386_DIR32    : NumPut("UInt", targetAddress + NumGet(mcode, patchAddress, "UInt"), mcode, patchAddress), this.VAreloc.Push({offset: patchAddress, size: 4})
                case IMAGE_REL_I386_DIR32NB  : NumPut("UInt", targetAddress + NumGet(mcode, patchAddress, "UInt"), mcode, patchAddress)
                case IMAGE_REL_I386_REL32    : NumPut("Int",  targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 4), mcode, patchAddress)
                default: throw Error(Format("Unsupported relocation type [x86]: 0x{:04X}", relocType))
            }
        }
    }


    Linker() {
        layout               := []
        currentOffset        := this.entryPoint <= 0 ? 0 : this.entryPoint <= 0xFF ? 2 : this.entryPoint <= 0xFFFFFFFF ? 5 : 0
        IAT                  := "|"
        unresolvedSymbolsNew := []
        shortDbgInfo         := ""
        this.dbgLogInfo      := "[Layout] Analyzing and merging sections:`n"

        ; --- Очередь объектных файлов для статической линковки ---
        objQueue := [{coff: this, originKey: "main.obj"}]
        visitedObjKeys := Map()
        visitedObjKeys["main.obj"] := true
        
        globalSymbolOffsets := Map() ; Глобальная таблица символов (имя -> абсолютное смещение в Mcode)
        comdatRegistry      := Map() ; key = COMDAT-имя, value = {offset, size, checksum}
        pendingRelocations  := []    ; Внутренние релокации, которые нужно пропатчить позже
        pendingExternalRefs := []    ; Внешние ссылки, которые нужно разрешить (статика или динамика)

        ; 1: Рекурсивно извлекаем и парсим все нужные .obj файлы
        while objQueue.Length > 0 {
            currentObjWrapper    := objQueue.RemoveAt(1)
            coffObj              := currentObjWrapper.coff
            this.dbgLogInfo      .= "`n[Obj] Processing object: " currentObjWrapper.originKey "`n"
            localToGlobalOffsets := Map()
            discardedSections    := Map() ; отброшенные секции COMDAT

            ; Лейаут секций текущего объекта (с сортировкой $-групп и COMDAT-логикой)
            sortedIndices := coffObj.GetSortedSectionIndices()
            for idx, i in sortedIndices {
                sec     := coffObj.sections[i]
                secSize := Max(sec.SizeOfRawData, sec.VirtualSize)
                if (secSize == 0) {
                    this.dbgLogInfo .= "`t[Skip] Empty section '" sec.Name "'`n"
                    continue
                }

                ; --- COMDAT-обработка ---
                if (coffObj.comdatSections.Has(i)) {
                    comdat     := coffObj.comdatSections[i]
                    comdatName := comdat.SymbolName
                    selection  := comdat.Selection

                    if (comdatRegistry.Has(comdatName)) {
                        existing := comdatRegistry[comdatName]

                        if (selection == COFF.IMAGE_COMDAT_SELECT_NODUPLICATES) {
                            throw Error("COMDAT NODUPLICATES violation: symbol '" comdatName "' in '" coffObj.obj "'")
                        } else if (selection == COFF.IMAGE_COMDAT_SELECT_SAME_SIZE) {
                            if (existing.size != secSize)
                                throw Error("COMDAT SAME_SIZE violation: symbol '" comdatName "' (" existing.size " vs " secSize ")")
                            this.dbgLogInfo .= "`t[COMDAT SAME_SIZE] Duplicate '" comdatName "' skipped.`n"
                        } else if (selection == COFF.IMAGE_COMDAT_SELECT_EXACT_MATCH) {
                            if (existing.checksum != comdat.CheckSum)
                                throw Error("COMDAT EXACT_MATCH violation: symbol '" comdatName "' (checksum mismatch)")
                            this.dbgLogInfo .= "`t[COMDAT EXACT_MATCH] Duplicate '" comdatName "' skipped.`n"
                        } else if (selection == COFF.IMAGE_COMDAT_SELECT_LARGEST) {
                            this.dbgLogInfo .= "`t[COMDAT LARGEST] Duplicate '" comdatName "' skipped (first-wins MVP).`n"
                        } else if (selection == COFF.IMAGE_COMDAT_SELECT_ASSOCIATIVE) {
                            this.dbgLogInfo .= "`t[COMDAT ASSOCIATIVE] Duplicate '" comdatName "' skipped.`n"
                        } else {
                            this.dbgLogInfo .= "`t[COMDAT ANY] Duplicate '" comdatName "' skipped.`n"
                        }

                        localToGlobalOffsets[i] := existing.offset
                        discardedSections[i]    := true ; помечается как удаленная
                        layout.Push({CoffObj: coffObj, Section: sec, OriginalIndex: i, NewOffset: existing.offset, IsComdatDup: true})
                        continue
                    }
                }

                ; --- Обычное добавление секции ---
                alignVal      := coffObj.alignment[i]
                currentOffset := (currentOffset + alignVal - 1) & ~(alignVal - 1)
                localToGlobalOffsets[i] := currentOffset
                layout.Push({CoffObj: coffObj, Section: sec, OriginalIndex: i, NewOffset: currentOffset})
                this.dbgLogInfo .= "`t[OK] Section '" sec.Name "' merged. New offset: 0x" Format("{:X}", currentOffset) ", Size: " secSize "`n"

                ; Регистрируем COMDAT в глобальном реестре
                if (coffObj.comdatSections.Has(i)) {
                    comdat := coffObj.comdatSections[i]
                    comdatRegistry[comdat.SymbolName] := {offset: currentOffset, size: secSize, checksum: comdat.CheckSum}
                }

                currentOffset += secSize
            }

            ; Регистрация публичных символов текущего объекта в глобальной таблице
            for symIdx, symbol in coffObj.symbolsMap {
                if (symbol.SectionIndex > 0 && symbol.StorageClass == 2) {
                    if (localToGlobalOffsets.Has(symbol.SectionIndex)) {
                        symName := symbol.Name
                        symAddr := localToGlobalOffsets[symbol.SectionIndex] + symbol.Value
                        ; COMDAT уже разрулен на уровне секций - здесь просто first-wins для символов
                        if (!globalSymbolOffsets.Has(symName))
                            globalSymbolOffsets[symName] := localToGlobalOffsets[symbol.SectionIndex] + symbol.Value
                        else if (!coffObj.comdatSections.Has(symbol.SectionIndex))
                            this.dbgLogInfo .= "`t[Warning] Duplicate non-COMDAT symbol '" symName "' ignored.`n"
                    }
                }
            }

            ; Сбор релокаций
            for i, sec in coffObj.sections {
                if (coffObj.sectionFilter[i] || discardedSections.Has(i))
                    continue

                loop (sec.NumberOfRelocations) {
                    relocOffset    := sec.PointerToRelocations + ((A_Index - 1) * COFF.SIZEOF_IMAGE_RELOCATION)
                    reloc          := coffObj.IMAGE_RELOCATION(relocOffset)
                    symbolIndex    := reloc.SymbolTableIndex
                    symbol         := coffObj.symbolsMap[symbolIndex]
                    absPatchOffset := localToGlobalOffsets[i] + reloc.VirtualAddress

                    if (symbol.StorageClass == 2 && symbol.SectionIndex == 0) {
                        origName    := symbol.Name
                        cleanName   := origName
                        isImport    := false
                        substituted := false
                        
                        if (this.is64) {
                            if (origName ~= "^__imp_") {
                                cleanName := SubStr(origName, 7)
                                isImport := true
                            }
                        } else if (this.is32) {
                            if (origName ~= "^__imp__") { ; Это импорт (__imp__Func@X)
                                cleanName := RegExReplace(SubStr(origName, 8), "@\d+$")
                                isImport := true
                            } else if (origName ~= "^___") { ; Внутренние функции (___mingw_vsprintf)
                                cleanName := origName
                                isImport := false
                            } else if (origName ~= "^_") { ; Обычные функции (_main)
                                cleanName := RegExReplace(SubStr(origName, 2), "@\d+$")
                                isImport := false
                            }
                        }

                        ; Подмена символов.
                        if (this.dynamicSubstitution.Has(cleanName)) {
                            cleanName   := this.dynamicSubstitution[cleanName]
                            isImport    := true
                            substituted := true
                        } else if (this.staticSubstitution.Has(cleanName)) {
                            cleanName   := this.staticSubstitution[cleanName]
                            isImport    := false
                            substituted := true
                        }
                        pendingExternalRefs.Push({func: cleanName, orig: origName, type: reloc.Type, patchOffset: absPatchOffset, isImport: isImport, substituted: substituted}) ; чистое имя (func) и оригинальное (orig)
                    } else if (symbol.StorageClass == 105) { ; --- WEAK EXTERNAL ---
                        weakInfo    := coffObj.weakExternals.Has(symbolIndex) ? coffObj.weakExternals[symbolIndex] : {TagIndex: 0, Characteristics: 1}
                        fallbackSym := (weakInfo.TagIndex > 0 && coffObj.symbolsMap.Has(weakInfo.TagIndex)) ? coffObj.symbolsMap[weakInfo.TagIndex] : ""
                        origName  := symbol.Name
                        cleanName := origName
                        isImport  := false

                        ; Чистим имя так же, как для обычных внешних
                        if (this.is64) {
                            if (origName ~= "^__imp_") {
                                cleanName := SubStr(origName, 7)
                                isImport  := true
                            }
                        } else if (this.is32) {
                            if (origName ~= "^__imp__") {
                                cleanName := RegExReplace(SubStr(origName, 8), "@\d+$")
                                isImport  := true
                            } else if (origName ~= "^___") {
                                cleanName := origName
                                isImport  := false
                            } else if (origName ~= "^_") {
                                cleanName := RegExReplace(SubStr(origName, 2), "@\d+$")
                                isImport  := false
                            }
                        }

                        ; Определяем fallback-имя
                        fallbackName := ""
                        if (fallbackSym && fallbackSym.Name != "") {
                            fallbackName := fallbackSym.Name
                            ; Чистим fallback имя тоже
                            if (this.is64) {
                                if (fallbackName ~= "^__imp_")
                                    fallbackName := SubStr(fallbackName, 7)
                            } else if (this.is32) {
                                if (fallbackName ~= "^__imp__") {
                                    fallbackName := RegExReplace(SubStr(fallbackName, 8), "@\d+$")
                                } else if (fallbackName ~= "^___") {
                                    ; Ничего не делаем, оставляем как есть
                                } else if (fallbackName ~= "^_") {
                                    fallbackName := RegExReplace(SubStr(fallbackName, 2), "@\d+$")
                                }
                            }
                        }

                        pendingExternalRefs.Push({
                            func: cleanName,
                            orig: origName,
                            type: reloc.Type,
                            patchOffset: absPatchOffset,
                            isImport: isImport,
                            isWeak: true,
                            weakSearch: weakInfo.Characteristics,
                            fallbackName: fallbackName,
                            fallbackTagIndex: weakInfo.TagIndex
                        })

                    } else {
                        pendingRelocations.Push({CoffObj: coffObj, Reloc: reloc, Symbol: symbol, PatchOffset: absPatchOffset})
                    }
                }
            }

            ; Поиск неразрешенных символов в статических библиотеках
            if (this.staticLibraries.Length > 0) {
                for ref in pendingExternalRefs {
                if (ref.substituted) ; Подменённые символы НЕ ищем в статических библиотеках
                    continue

                if (ref.HasProp("isWeak") && ref.isWeak && ref.weakSearch == 1)
                    continue

                    symToFind := ref.orig
                    if (globalSymbolOffsets.Has(symToFind))
                        continue ; Уже разрешено предыдущим объектом
                    for lib in this.staticLibraries {
                        if (lib.ResolvedSymbols.Has(symToFind)) {
                            objInfos := lib.ResolvedSymbols[symToFind] ; MultiMap возвращает массив
                            for objInfo in objInfos {
                                objKey := lib.ArchiveDir "\" objInfo.ObjFile
                                if (!visitedObjKeys.Has(objKey)) {
                                    visitedObjKeys[objKey] := true
                                    try {
                                        ; Извлекаем .obj в память (Buffer) и парсим как COFF
                                        buf := lib.ExtractMemberToBuffer(objInfo.ObjFile)
                                        newCoff := COFF(buf, this.importDll, this.ignoreSections, this.fullOffsetTable, 0, this.dynamicLinking, this.staticLibraries)

                                        if (this.is64 != newCoff.is64) ; Проверка битности
                                            throw Error("Architecture mismatch: main object is " (this.is64 ? "x64" : "x86") ", but '" objInfo.ObjFile "' is " (newCoff.is64 ? "x64" : "x86"))

                                        objQueue.Push({coff: newCoff, originKey: objKey})
                                        this.dbgLogInfo .= "`t[Static] Extracted '" objInfo.ObjFile "' from library for symbol '" symToFind "'`n"
                                    } catch as er {
                                        this.dbgLogInfo .= "`t[Error] Failed to extract '" objInfo.ObjFile "': " er.Message "`n"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        ; 2: Выделение памяти и копирование сырых данных
        totalSize := currentOffset
        if (totalSize == 0)
            throw Error("No executable code or data found.")

        mcode := Buffer(totalSize, 0)
        COFF.EntryPoint(this.entryPoint + (this.entryPoint == 0 ? 0 : this.alignment[1]), mcode)
        
        for item in layout {
            ; COMDAT-дубликаты не копируем (их данные уже лежат в оригинале)
            if (item.HasProp("IsComdatDup") && item.IsComdatDup)
                continue
            if (item.Section.PointerToRawData > 0 && Max(item.Section.SizeOfRawData, item.Section.VirtualSize) > 0) {
                DllCall("RtlMoveMemory", "Ptr", mcode.Ptr + item.NewOffset, "Ptr", item.CoffObj.ptr.Ptr + item.Section.PointerToRawData, "UPtr", item.Section.SizeOfRawData)
            }
        }

        this.dbgLogInfo .= "`n[Relocations] Processing relocations and patching:`n"

        for relocInfo in pendingRelocations {
            coffObj := relocInfo.CoffObj
            symbol  := relocInfo.Symbol
            targetGlobalOffset := -1

            if (symbol.SectionIndex == -1) { ; Абсолютный символ
                targetGlobalOffset := symbol.Value
            } else {
                for item in layout {
                    if (ObjPtr(item.CoffObj) = ObjPtr(coffObj) && item.OriginalIndex = symbol.SectionIndex) {
                        if (symbol.StorageClass == COFF.IMAGE_SYMBOL_STORAGE_CLASS.Get("IMAGE_SYM_CLASS_SECTION")) {  ; адрес символа = начало секции, Value игнорируется
                            targetGlobalOffset := item.NewOffset
                        } else {
                            targetGlobalOffset := item.NewOffset + symbol.Value
                        }
                        break
                    }
                }
            }

            if (targetGlobalOffset == -1)
                throw Error("Failed to find section for internal symbol '" symbol.Name "'.")

            this.ApplyRelocation(mcode, targetGlobalOffset, relocInfo.PatchOffset, relocInfo.Reloc.Type)
        }

        ; Разрешение внешних ссылок (статика или динамика)
        this.imports := []
        this.unresolvedSymbols := []


        for ref in pendingExternalRefs {
            symToFind := ref.orig
            if (!ref.substituted && globalSymbolOffsets.Has(symToFind)) {
                this.ApplyRelocation(mcode, globalSymbolOffsets[symToFind], ref.patchOffset, ref.type) ; патчим как обычно
            } else if (ref.HasProp("isWeak") && ref.isWeak) {
                ; --- WEAK EXTERNAL: символ не найден ---
                if (ref.fallbackName != "" && globalSymbolOffsets.Has(ref.fallbackName)) {
                    ; Fallback найден — используем его адрес
                    this.ApplyRelocation(mcode, globalSymbolOffsets[ref.fallbackName], ref.patchOffset, ref.type)
                    this.dbgLogInfo .= "`t[Weak] Symbol '" ref.func "' not found, using fallback '" ref.fallbackName "'`n"

                } else if (ref.weakSearch == 1) {
                    ; SEARCH_NOLIBRARY: не искать, патчим нулём. Для REL32 это означает: call/jmp на следующую инструкцию (nop-like). Для ADDR32/ADDR64 это просто 0
                    this.ApplyRelocation(mcode, 0, ref.patchOffset, ref.type)
                    this.dbgLogInfo .= "`t[Weak] Symbol '" ref.func "' not found, patched with 0 (NOLIBRARY)`n"

                } else {
                    ; Не нашли ни символ, ни fallback — в unresolved
                    if (ref.isImport) {
                        this.imports.Push(ref)
                    } else {
                        this.unresolvedSymbols.Push(ref)
                    }
                }

            } else {
                ; Обычный внешний символ не найден
                if (ref.isImport) {
                    this.imports.Push(ref)
                } else {
                    this.unresolvedSymbols.Push(ref)
                }
            }
        }

        ;============================================ кастомный мини IAT + VA reloc ============================================
        this.dbgLogInfo .= "`n[IAT] Generating Import Address Table (IAT):`n"
        loadedDlls := Map()
        for dll in this.importDll {
            if (hMod := DllCall("LoadLibrary", "Str", dll, "Ptr")) {
                loadedDlls[dll] := hMod
                this.dbgLogInfo .= "`tLoaded DLL: '" dll "'`n"
            } else {
                this.dbgLogInfo .= "`t[Warning] Failed to load DLL: '" dll "'`n"
            }
        }

        ResolveAndAdd(exp, writeIAT := true) {
            disp := this.is32 ? 4 : exp.type
            for dll, hMod in loadedDlls {
                if (DllCall("GetProcAddress", "Ptr", hMod, "AStr", exp.func, "Ptr")) {
                    if (writeIAT) {
                        IAT .= dll ":" exp.func ":" exp.patchOffset ":" disp "|"
                    }
                    this.dbgLogInfo .= "`t[OK] Symbol '" exp.func "' found in " dll ". Added to IAT.`n"
                    return true
                }
            }
            if (writeIAT) {
                this.dbgLogInfo .= "`t[Skip] Symbol '" exp.func "' not found in loaded DLLs (UNKNOWN_DLL). Skipped in IAT.`n"
            }
            return false
        }

        if (this.imports.Length) {
            line := true
            this.dbgLogInfo .= "`n[IAT] Processing dynamic imports (__imp_):`n"
            for exp in this.imports {
                if !(ResolveAndAdd(exp)) {
                    if (line) {
                        shortDbgInfo .= "Not found imports [DLL]:`n"
                        line := false
                    }
                    shortDbgInfo .= "`tsymbol: '" exp.func "' -> offset: " Format("0x{:X}", exp.patchOffset) " -> reloc type " Format("0x{:X}", exp.type) "`n"
                }
            }
        }

        if (this.unresolvedSymbols.Length) {
            this.dbgLogInfo .= "`n[IAT] Processing unresolved symbols (static):`n"
            if (this.dynamicLinking == true) {
                this.dbgLogInfo .= "`tdynamicLinking = true. Attempting to link all unresolved symbols dynamically.`n"
                for exp in this.unresolvedSymbols {
                    if !(ResolveAndAdd(exp))
                        unresolvedSymbolsNew.Push(exp)
                }
            } else if (this.dynamicLinking is Array) {
                this.dbgLogInfo .= "`tdynamicLinking = Array. Checking specific symbols for dynamic linking.`n"
                for exp in this.unresolvedSymbols {
                    isDynRequested := false
                    for dynFunc in this.dynamicLinking {
                        if (exp.func == dynFunc) {
                            isDynRequested := true
                            break
                        }
                    }
                    
                    if (isDynRequested) {
                        if !(ResolveAndAdd(exp))
                            unresolvedSymbolsNew.Push(exp)
                    } else {
                        unresolvedSymbolsNew.Push(exp)
                    }
                }
            } else {
                this.dbgLogInfo .= "`tdynamicLinking = false. Unresolved symbols are ignored.`n"
                for exp in this.unresolvedSymbols {
                    unresolvedSymbolsNew.Push(exp)
                }
            }
            this.unresolvedSymbols := unresolvedSymbolsNew

            if (this.unresolvedSymbols.Length) {
                shortDbgInfo .= "Unresolved symbols not found (static)`n"
                for exp in this.unresolvedSymbols {
                    shortDbgInfo .= "`tsymbol: '" exp.func "' -> offset: " Format("0x{:X}", exp.patchOffset) " -> reloc type " Format("0x{:X}", exp.type) . (ResolveAndAdd(exp, false) ? " // It can be made dynamic`n" : " // This cannot be made dynamic.`n")
                }
            }
        }

        if (this.VAreloc.Length) {
            this.dbgLogInfo .= "`n[IAT] Adding VA relocations:`n"
            for va in this.VAreloc {
                IAT .= "VA:" va.size ":" va.offset "|"
                this.dbgLogInfo .= "`tAdded VA relocation (size: " va.size ", offset: 0x" Format("{:X}", va.offset) ")`n"
            }
        }

        ;============================================ таблица символов ============================================
        this.exportedSymbols := Map()
        for i, symbol in this.symbolsMap {
            if (symbol.SectionIndex > 0 && (symbol.StorageClass == 2) || this.fullOffsetTable) {
                secOffset := -1
                for item in layout {
                    if (item.OriginalIndex == symbol.SectionIndex && ObjPtr(item.CoffObj) = ObjPtr(this)) {
                        secOffset := item.NewOffset
                        break
                    }
                }
                
                if (secOffset != -1) {
                    this.exportedSymbols[i] := {symbol: symbol.Name, offset: Format("0x{:X}", secOffset + symbol.Value), opt: symbol.StorageClass != 2 ? " [dispensable] | " : ""}
                }
            }
        }

        this.dbgLogInfo .= "`n[Linker] Linking process completed " . (shortDbgInfo == "" ? "successfully, most likely no errors!`n" : "with errors. Check main GUI for potential issues...`n")
        return {
            hex:      Binary.BinaryToStrin(mcode, mcode.Size, 12)           . RTrim(IAT, "|"),
            base64:   Binary.BinaryToStrin(mcode, mcode.Size, 1)            . RTrim(IAT, "|"),
            compress: Binary.BinaryToCompressedBase64(mcode, mcode.Size, 2) . RTrim(IAT, "|"),
            table:    Demangle.ExportedSymbolsDump(this.exportedSymbols, this.demangleLvl),
            dbg:      {ALL: this.dbgLogInfo, short: shortDbgInfo}
        }
    }


    ; Возвращает массив индексов секций (1-based), отсортированных с учётом $-суффиксов. Секции из sectionFilter (useless) не включаются.
    GetSortedSectionIndices() {
        ; Сравнение имён секций: сначала по префиксу (до $), затем по суффиксу (после $). Секции без $ считаются как префикс с пустым суффиксом (идут первыми в группе).
        CompareSectionNames(name1, name2) {
            pos1 := InStr(name1, "$")
            pos2 := InStr(name2, "$")

            if (pos1 == 0 && pos2 == 0)
                return StrCompare(name1, name2)

            prefix1 := pos1 ? SubStr(name1, 1, pos1 - 1) : name1
            prefix2 := pos2 ? SubStr(name2, 1, pos2 - 1) : name2
            suffix1 := pos1 ? SubStr(name1, pos1 + 1) : ""
            suffix2 := pos2 ? SubStr(name2, pos2 + 1) : ""

            cmp := StrCompare(prefix1, prefix2)
            if (cmp != 0)
                return cmp

            return StrCompare(suffix1, suffix2)
        }

        indices := []
        for i, sec in this.sections {
            if (!this.sectionFilter[i])
                indices.Push(i)
        }
        ; Bubble sort по CompareSectionNames
        n := indices.Length
        Loop n - 1 {
            Loop n - A_Index {
                if (CompareSectionNames(this.sections[indices[A_Index]].Name, this.sections[indices[A_Index + 1]].Name) > 0) {
                    tmp := indices[A_Index]
                    indices[A_Index] := indices[A_Index + 1]
                    indices[A_Index + 1] := tmp
                }
            }
        }
        return indices
    }


    AllInfo() {
        info := "FILE [IMAGE_FILE_HEADER]:`n"
        info .= Format("  {1:-22} 0x{2:04X}`n", "Machine:",              this.MACHINE)
        info .= Format("  {1:-22} {2}`n",       "NumberOfSections:",     this.NUMBER_OF_SECTIONS)
        info .= Format("  {1:-22} 0x{2:08X}`n", "TimeDateStamp:",        this.TIME_DATE_STAMP)
        info .= Format("  {1:-22} 0x{2:08X}`n", "PointerToSymbolTable:", this.POINTER_TO_SYMBOL_TABLE)
        info .= Format("  {1:-22} {2}`n",       "NumberOfSymbols:",      this.NUMBER_OF_SYMBOLS)
        info .= Format("  {1:-22} 0x{2:04X}`n", "SizeOfOptionalHeader:", this.SIZE_OF_OPTIONAL_HEADER)
        info .= Format("  {1:-22} 0x{2:04X}`n", "Characteristics:",      this.CHARACTERISTICS)

        info .= "`nSYMBOL_TABLE [IMAGE_SYMBOL]:`n"
        for i, sym in this.symbolsMap {
            name := sym.Name
            if (StrLen(name) > 24)
                name := SubStr(name, 1, 21) "..."

            info .= Format("  [{1:04}] {2:-24} Val:0x{3:08X}  Sec:{4:-6}  Typ:{5:-6} Aux:{6:-4} Class:{7}`n",
                i,
                name,
                sym.Value,
                sym.SectionIndex > -1 ? Format("0x{:X}", sym.SectionIndex & 0xFFFF) : sym.SectionIndex,
                Format("0x{:X}", sym.Type),
                sym.NumberOfAuxSymbols,
                sym.StorageClass
            )
        }
        info .= "`nSECTIONS [IMAGE_SECTION_HEADER]:`n"
        
        info .= Format(
            "  {1:-7} {2:-16} {3:-11} {4:-11} {5:-11} {6:-11} {7:-11} {8:-8} {9}`n",
            "Idx", "Name", "VSize", "VAddr", "RawSize", "RawPtr", "RelocPtr", "nReloc", "Charact"
        )
        
        for i, sec in this.sections {
            secName := sec.Name
            if (StrLen(secName) > 16)
                secName := SubStr(secName, 1, 13) "..."

            info .= Format(
                "  [{1:04}]  {2:-16} 0x{3:08X}  0x{4:08X}  0x{5:08X}  0x{6:08X}  0x{7:08X}  {8:-8} 0x{9:08X}`n",
                i,
                secName,
                sec.VirtualSize,
                sec.VirtualAddress,
                sec.SizeOfRawData,
                sec.PointerToRawData,
                sec.PointerToRelocations,
                sec.NumberOfRelocations,
                sec.Characteristics
            )
        }

        info .= "`nRELOCATION [IMAGE_RELOCATION]:"
        relocIdx := 1
        for sec in this.sections {
            secName := sec.Name
            if (StrLen(secName) > 80)
                secName := SubStr(secName, 1, 77) "..."

            if (sec.NumberOfRelocations) {
                info .= "`n  RELOCATION_RECORDS_FOR [" secName "]:`n"
                info .= Format("    {1:-7} {2:-15} {3:-11} {4:-11}`n", "Idx", "Sec", "Reloc", "Type")
                loop (sec.NumberOfRelocations) {
                    rSection := this.relocations[relocIdx].section
                    if (StrLen(rSection) > 16)
                        rSection := SubStr(rSection, 1, 13) "..."

                    info .= Format("    [{1:04}] {2:-16} 0x{3:08X}  0x{4:04X}`n",
                        this.relocations[relocIdx].SymbolTableIndex,
                        rSection,
                        this.relocations[relocIdx].reloc,
                        this.relocations[relocIdx].type
                    )
                    relocIdx++
                }
            }
        }
        return info
    }


    ObjCopy(dump := false, bytesPerLine := 8, &prop?) {
        m := Map(), prop := []
        for sec in this.sections {
            hex := sec.SizeOfRawData == 0 ? "Empty section" : Binary.BinaryToStrin(this.ptr.Ptr + sec.PointerToRawData, sec.SizeOfRawData, 12)
            if (dump) {
                m[A_Index " " sec.Name] := {hex: hex, dump: sec.SizeOfRawData == 0 ? "Empty section" : Binary.HexToASCII(this.ptr.Ptr + sec.PointerToRawData, sec.SizeOfRawData, bytesPerLine)}
            } else {
                m[A_Index " " sec.Name] := {hex: hex}
            }
            prop.Push(A_Index " " sec.Name)
        }
        return m
    }


    static EntryPoint(jmpOffset, buf) {
        if (!(jmpOffset is Integer) || jmpOffset <= 0)
            return 0
        if (jmpOffset <= 0xFF + 2) {
            NumPut("UChar", 0xEB, "UChar", jmpOffset - 2, buf) ; jmp rel8 [EB 00]
        } else if (jmpOffset<= 0xFFFFFFFF + 5) {
            NumPut("UChar", 0xE9, "UInt", jmpOffset - 5, buf) ; jmp rel32 [E9 00 00 00 00]
        } else return 0
    }
}


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
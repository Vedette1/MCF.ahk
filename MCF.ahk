#Requires AutoHotkey v2.0
#SingleInstance Force
#Include const.ahk
#Include Static_Library_Viewer.ahk
#Include Lib\MCF_MCODE.ahk
#Include Lib\PEExportParser.ahk

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
            throw Error("Could not find valid bytes in the transferred data.")
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
     * @param {Integer | Array} dynamicLinking - Для функций `malloc`, да и в целом большинства функций из `msvcrt` (например), компилятор подразумевает статическую линковку (генерирует call с опкодом `[E8 00 00 00 00] || [E9 00 00 00 00]`, а не jmp инструкции).
     * Это не есть хорошо, ибо раздувает размер конечного Mcode. `dynamicLinking` позволяет указать массив функций, которые будут 100% слинкованны динамически, а не статически.
     * - Если `dynamicLinking := [dllFunc1, dllFunc2, ...]`, то, если символ из массива `dynamicLinking` найден в `importDll`, то эта функция будет динамически слинвокана (она окажется в IAT). Функция `GetMcodePtr` создаст трамплин `[E8|E9 00 00 00 00 + [FF 25 (PTR)]]`.
     * - Если `dynamicLinking := true`, то абсолютно все символы, которые могут быть динамически слинкованы, будут размещены в IAT.
     * - Если `dynamicLinking := false`, то класс не будет пытаться патчить asm инструкции. То есть, если компилятор подразумевает статическую линковку для определенного символа, то он будет статически слинкован.
     * @param {Array} staticLibraries - Массив экземпляров класса StaticLibraryParser для статической линковки.
     */
    __New(obj, importDll := ["User32", "msvcrt", "Kernel32"], ignoreSections := [".pdata", ".xdata", ".rdata$zzz"], fullOffsetTable := true, dynamicLinking := true, staticLibraries := [], dynamicSubstitution := Map(), staticSubstitution := Map(), useOrdinals := true, usePEParser := false) {
        this.obj                 := obj                      ; Путь до COFF (.o / .obj) файла.
        this.importDll           := importDll                ; Массив dll которые используются в конечном Mcode (если есть внешнии символы).
        this.ignoreSections      := ignoreSections           ; Массив секций, которые будут игнорироватся при линковке (в основном сюда ничего не нужно дописывать).
        this.fullOffsetTable     := fullOffsetTable          ; Если fullOffsetTable == false, то линковщик вернет смещения только нужных символов (функции / глобалки*), в ином случае будет полная таблица всех символов.
        this.dynamicLinking      := dynamicLinking           ; Управление динамической линковкой: false, true или массив конкретных функций.
        this.staticLibraries     := staticLibraries          ; Массив статических библиотек (экземпляры StaticLibraryParser).
        this.dynamicSubstitution := dynamicSubstitution      ; Подмена динамических символов.
        this.staticSubstitution  := staticSubstitution       ; Подмена статических символов.
        this.useOrdinals         := useOrdinals              ; В мини IAT будут записываться ординалы функций (порядковый номер), а не их именна. Это экономит место, а так же делает Mcode более сложночитаемым.
        this.usePEParser         := usePEParser              ; Если `false` используется LoadLibrary + GetProcAddress для поиска символов в dll для IAT, в ином случае dll не загружаются в память, а читаются файлы.
        
        this.dbgLogInfo          := "" ; Полный лог сборки.
        this.shortDbgInfo        := "" ; Ошибки для main окна GUI (только ошибки и предупреждения).

        this.imports           := []  ; Массив объектов импортируемых символов из dll (__imp_).
        this.unresolvedSymbols := []  ; Массив объектов неразрешённых символов (статическая линковка).

        this.exportedSymbols := Map() ; Таблица смещений всех функций / секций / глобальных переменных, и тд. которые есть в конечном Mcode.
        this.VAreloc         := []    ; Массив VA релокаций - VirtualAlloc + RVA (известно только при запуске). В 99% случаев VA релокаций не будет в конечном Mcode.
        this.sectionFilter   := []    ; Массив 0 && 1. Фильтрует бесполезные секции при линковке, что бы не захватывать их в конечный Mcode (например это .xdata | .pdata).
        this.alignment       := []    ; Массив выравнивания данных по границе в X байт. Для производительности нужно учитывать выравнивание байт при объединение секций.
        this.relocations     := []    ; Массив объектов - содержит все релокации, их тип, symbolIndex, а так же именна секций + функций [IMAGE_RELOCATION()]. Dbg info.
        this.symbolsMap      := Map() ; Все символы COFF [key == symbolIndex, value == IMAGE_SYMBOL()].
        this.sections        := []    ; Массив объектов - содержит все секции COFF [IMAGE_SECTION_HEADER()].
        this.commonSymbols   := Map() ; COMMON (-fcommon): имя -> {offset, size}

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
                if (secIdx > this.sections.Length || this.comdatSections.Has(secIdx))
                    continue
                if !(this.sections[secIdx].Characteristics & COFF.IMAGE_SECTION_HEADER_CHARACTERISTICS.Get("IMAGE_SCN_LNK_COMDAT"))
                    continue

                auxOffset := this.POINTER_TO_SYMBOL_TABLE + ((symIdx + 1) * COFF.SIZEOF_IMAGE_SYMBOL)
                selection := NumGet(this.ptr, auxOffset + 14, "UChar")

                realComdatName := symbol.Name
                ; Имя-ключ ищем ТОЛЬКО для не-ассоциативных секций (у ASSOCIATIVE нет своего символа-ключа)
                if (selection != COFF.IMAGE_COMDAT_SELECT_ASSOCIATIVE) {
                    found := false
                    ; Приоритет: ищем публичный EXTERNAL символ (StorageClass == 2) в этой секции
                    for _, extSym in this.symbolsMap {
                        if (extSym.SectionIndex == secIdx && extSym.StorageClass == 2) {
                            realComdatName := extSym.Name
                            found := true
                            break
                        }
                    }
                    ; Если EXTERNAL нет (например, static COMDAT с StorageClass == 3), берется первый символ в этой секции, который не является самим заголовком секции (otherIdx != symIdx)
                    if (!found) {
                        for otherIdx, otherSym in this.symbolsMap {
                            if (otherIdx != symIdx && otherSym.SectionIndex == secIdx) {
                                realComdatName := otherSym.Name
                                break
                            }
                        }
                    }
                }

                this.comdatSections[secIdx] := {
                    Length:       NumGet(this.ptr, auxOffset + 0,  "UInt"),
                    NumRelocs:    NumGet(this.ptr, auxOffset + 4,  "UShort"),
                    NumLineNums:  NumGet(this.ptr, auxOffset + 6,  "UShort"),
                    CheckSum:     NumGet(this.ptr, auxOffset + 8,  "UInt"),
                    AssocSection: NumGet(this.ptr, auxOffset + 12, "UShort"),
                    Selection:    selection,
                    SymbolName:   realComdatName
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
            isUseless := (sec.Characteristics & (IMAGE_SCN_LNK_REMOVE | IMAGE_SCN_LNK_INFO | IMAGE_SCN_MEM_DISCARDABLE)) != 0
            if (!isUseless) {
                for ignoreName in this.ignoreSections {
                    if (sec.Name == ignoreName) {
                        isUseless := true
                        break
                    }
                }
            }

            alignBytes := 4
            for name, value in COFF.IMAGE_SECTION_HEADER_CHARACTERISTICS {
                if (InStr(name, "ALIGN") && (sec.Characteristics & ALIGN_MASK) == value) {
                    res := RegExReplace(name, "\D+", "")
                    alignBytes := res != "" ? Integer(res) : 4
                    break
                }
            }
            this.alignment.Push(alignBytes)
            this.sectionFilter.Push(isUseless ? 1 : 0)
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


    CleanSymbolName(rawName) {
        if (this.is64) {
            if (rawName ~= "^__imp_")
                return {name: SubStr(rawName, 7), isImport: true}
        } else if (this.is32) {
            if (rawName ~= "^__imp__") ; Это импорт (__imp__Func@X)
                return {name: RegExReplace(SubStr(rawName, 8), "@\d+$"), isImport: true}
            if (rawName ~= "^___")     ; Внутренние функции (___mingw_vsprintf) - не трогаем
                return {name: rawName, isImport: false}
            if (rawName ~= "^_")       ; Обычные функции (_main)
                return {name: RegExReplace(SubStr(rawName, 2), "@\d+$"), isImport: false}
        }
        return {name: rawName, isImport: false}
    }


    ParseExternalReloc(coffObj, reloc, symbolIndex, symbol, patchOffset := 0) {
        if (symbol.StorageClass == 2 && symbol.SectionIndex == 0) {
            origName  := symbol.Name
            cleaned   := this.CleanSymbolName(origName)
            cleanName := cleaned.name
            isImport  := cleaned.isImport
            isCommon  := (!isImport && symbol.Value > 0) ; SectionIndex == 0 && Value > 0 -> COMMON (tentative definition), Value == размер переменной. У обычного undefined-символа Value == 0.
            if (this.dynamicSubstitution.Has(cleanName)) {
                cleanName := this.dynamicSubstitution[cleanName]
                isImport  := true
                isCommon  := false          ; подмена отменяет COMMON
            } else if (this.staticSubstitution.Has(cleanName)) {
                cleanName := this.staticSubstitution[cleanName]
                isImport  := false
                isCommon  := false
            }
            return {func: cleanName, orig: origName, type: reloc.Type, patchOffset: patchOffset, isImport: isImport, isWeak: false, isCommon: isCommon, commonSize: symbol.Value}
        }
        
        else if (symbol.StorageClass == 105) { ; WEAK EXTERNAL
            weakInfo    := coffObj.weakExternals.Has(symbolIndex) ? coffObj.weakExternals[symbolIndex] : {TagIndex: 0, Characteristics: 1}
            fallbackSym := (weakInfo.TagIndex > 0 && coffObj.symbolsMap.Has(weakInfo.TagIndex)) ? coffObj.symbolsMap[weakInfo.TagIndex] : ""
            origName    := symbol.Name
            cleaned     := this.CleanSymbolName(origName)

            return {
                func:             cleaned.name,
                orig:             origName,
                type:             reloc.Type,
                patchOffset:      patchOffset,
                isImport:         cleaned.isImport,
                isWeak:           true,
                weakSearch:       weakInfo.Characteristics,
                fallbackName:     (fallbackSym && fallbackSym.Name != "") ? fallbackSym.Name : "", ; Сырое имя для поиска в globalSymbolOffsets
                fallbackTagIndex: weakInfo.TagIndex
            }
        }
        return ""
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
        currentOffset        := 0x0
        IAT                  := "|"
        mcodeBuildRules      := {IAT: [], VA: []} ; Все даные вроде IAT, VA релокаций, и тд. которые будут использоваться парсером для генерации Mcode под X формат.
        unresolvedSymbolsNew := []
        this.shortDbgInfo    := ""
        this.dbgLogInfo      := "[Layout] Analyzing and merging sections:`n"

        commonRegistry      := Map() ; имя -> {size, originKey}. Кандидаты на "виртуальный .bss"
        globalSymbolOffsets := Map("__ImageBase", 0, "___ImageBase", 0) ; Глобальная таблица символов (имя -> абсолютное смещение в Mcode) (ImageBase - поддержка MSVC)
        pendingRelocations  := []    ; Внутренние релокации, которые нужно пропатчить позже
        pendingExternalRefs := []    ; Внешние ссылки, которые нужно разрешить (статика или динамика)

        ; =================================================================================================
        ; 1: Сбор всех нужных .obj файлов и построение графа зависимостей из статических библиотек (.lib)
        ; =================================================================================================
        objQueue       := [{coff: this, originKey: "main.obj"}]
        visitedObjKeys := Map("main.obj", true)
        allObjects     := [] ; Все собранные объекты: [{coff, originKey}]
        knownSymbols := Map("__ImageBase", true, "___ImageBase", true) ; Символы, которые уже найдены в загруженных .obj (ImageBase - поддержка MSVC)

        while objQueue.Length > 0 {
            currentObjWrapper := objQueue.RemoveAt(1)
            coffObj           := currentObjWrapper.coff
            allObjects.Push(currentObjWrapper)

            ; Регистрируем публичные символы, которые предоставляет этот .obj
            for _, symbol in coffObj.symbolsMap {
                if (symbol.StorageClass != 2)
                    continue
                if (symbol.SectionIndex > 0 && !coffObj.sectionFilter[symbol.SectionIndex]) {
                    knownSymbols[symbol.Name] := true
                } else if (symbol.SectionIndex == 0 && symbol.Value > 0 && !this.CleanSymbolName(symbol.Name).isImport) {
                    ; COMMON - это тоже определение (пусть и слабое), из-за него не вытаскиваем член из .lib
                    knownSymbols[symbol.Name] := true
                }
            }

            ; Если есть статические библиотеки, ищем в них недостающие внешние символы для текущего .obj
            if (this.staticLibraries.Length > 0) {
                for i, sec in coffObj.sections {
                    if (coffObj.sectionFilter[i])
                        continue

                    loop (sec.NumberOfRelocations) {
                        relocOffset := sec.PointerToRelocations + ((A_Index - 1) * COFF.SIZEOF_IMAGE_RELOCATION)
                        reloc       := coffObj.IMAGE_RELOCATION(relocOffset)
                        symbolIndex := reloc.SymbolTableIndex
                        symbol      := coffObj.symbolsMap[symbolIndex]

                        extRef := this.ParseExternalReloc(coffObj, reloc, symbolIndex, symbol)
                        if (!extRef || extRef.isImport || (extRef.HasProp("isCommon") && extRef.isCommon))
                            continue
                        if (extRef.isWeak && extRef.weakSearch == 1) ; SEARCH_NOLIBRARY
                            continue

                        symToFind := extRef.orig
                        if (knownSymbols.Has(symToFind))
                            continue

                        for lib in this.staticLibraries {
                            if (lib.ResolvedSymbols.Has(symToFind)) {
                                for objInfo in lib.ResolvedSymbols[symToFind] {
                                    objKey := lib.ArchiveDir "\" objInfo.ObjFile
                                    if (!visitedObjKeys.Has(objKey)) {
                                        visitedObjKeys[objKey] := true
                                        try {
                                            buf     := lib.ExtractMemberToBuffer(objInfo.ObjFile)
                                            newCoff := COFF(buf, this.importDll, this.ignoreSections)

                                            if (this.is64 != newCoff.is64)
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
        }

        ; =================================================================================================
        ; 2: Глобальное разрешение COMDAT 
        ; =================================================================================================
        comdatRegistry    := Map() ; key = comdatName, value = {winnerCoff, winnerSecIdx, size, checksum, offset}
        discardedSections := Map() ; key = ObjPtr(coffObj) ":" secIdx -> true (все отброшенные секции)
        comdatRedirect    := Map() ; key = ObjPtr(coffObj) ":" secIdx -> comdatName (перенаправление дубликатов на победителя)

        ; 2.1: Обработка основных COMDAT-секций (все кроме ASSOCIATIVE)
        for objWrapper in allObjects {
            coffObj := objWrapper.coff
            for i, sec in coffObj.sections {
                if (coffObj.sectionFilter[i])
                    continue
                secSize := Max(sec.SizeOfRawData, sec.VirtualSize)
                if (secSize == 0 || !coffObj.comdatSections.Has(i))
                    continue

                comdat    := coffObj.comdatSections[i]
                selection := comdat.Selection
                if (selection == COFF.IMAGE_COMDAT_SELECT_ASSOCIATIVE)
                    continue ; Ассоциативные секции разрешаются на позже (2.2)

                comdatName := comdat.SymbolName
                secKey     := ObjPtr(coffObj) ":" i

                if (!comdatRegistry.Has(comdatName)) {
                    comdatRegistry[comdatName] := {
                        winnerCoff:   coffObj,
                        winnerSecIdx: i,
                        size:         secSize,
                        checksum:     comdat.CheckSum,
                        selection:    selection,
                        offset:       0
                    }
                } else {
                    existing := comdatRegistry[comdatName]

                    if (selection == COFF.IMAGE_COMDAT_SELECT_NODUPLICATES) {
                        throw Error("COMDAT NODUPLICATES violation: symbol '" comdatName "' in '" objWrapper.originKey "'")
                    } else if (selection == COFF.IMAGE_COMDAT_SELECT_SAME_SIZE) {
                        if (existing.size != secSize)
                            throw Error("COMDAT SAME_SIZE violation: symbol '" comdatName "' (" existing.size " vs " secSize ")")
                        this.dbgLogInfo .= "`t[COMDAT SAME_SIZE] Duplicate '" comdatName "' skipped.`n"
                    } else if (selection == COFF.IMAGE_COMDAT_SELECT_EXACT_MATCH) {
                        if (existing.checksum != comdat.CheckSum)
                            throw Error("COMDAT EXACT_MATCH violation: symbol '" comdatName "' (checksum mismatch)")
                        this.dbgLogInfo .= "`t[COMDAT EXACT_MATCH] Duplicate '" comdatName "' skipped.`n"
                    } else if (selection == COFF.IMAGE_COMDAT_SELECT_LARGEST || existing.selection == COFF.IMAGE_COMDAT_SELECT_LARGEST) {
                        ; Если новая секция больше текущего победителя — заменяем победителя
                        if (secSize > existing.size) {
                            oldWinnerKey := ObjPtr(existing.winnerCoff) ":" existing.winnerSecIdx
                            discardedSections[oldWinnerKey] := true
                            comdatRedirect[oldWinnerKey]    := comdatName

                            this.dbgLogInfo .= "`t[COMDAT LARGEST] Symbol '" comdatName "' replaced with larger section (" secSize " > " existing.size ").`n"
                            existing.winnerCoff   := coffObj
                            existing.winnerSecIdx := i
                            existing.size         := secSize
                            existing.checksum     := comdat.CheckSum
                            existing.selection    := COFF.IMAGE_COMDAT_SELECT_LARGEST
                            continue
                        } else {
                            this.dbgLogInfo .= "`t[COMDAT LARGEST] Duplicate '" comdatName "' skipped (" secSize " <= " existing.size ").`n"
                        }
                    } else {
                        this.dbgLogInfo .= "`t[COMDAT ANY] Duplicate '" comdatName "' skipped.`n"
                    }

                    ; Текущая секция проиграла отбор — помечается как удаленная
                    discardedSections[secKey] := true
                    comdatRedirect[secKey]    := comdatName
                }
            }
        }

        ; Вспомогательная функция для проверки цепочек ассоциативных секций (Секция В -> Секция Б -> Секция А)
        IsSectionDiscarded(coffObj, secIdx, visited := Map()) {
            if (secIdx <= 0 || secIdx > coffObj.sections.Length || coffObj.sectionFilter[secIdx])
                return true
            secKey := ObjPtr(coffObj) ":" secIdx
            if (discardedSections.Has(secKey))
                return true
            if (coffObj.comdatSections.Has(secIdx)) {
                comdat := coffObj.comdatSections[secIdx]
                if (comdat.Selection == COFF.IMAGE_COMDAT_SELECT_ASSOCIATIVE) {
                    if (visited.Has(secIdx))
                        return true
                    visited[secIdx] := true
                    return IsSectionDiscarded(coffObj, comdat.AssocSection, visited)
                }
            }
            return false
        }

        ; 2.2: Обработка IMAGE_COMDAT_SELECT_ASSOCIATIVE (зависит от итогов 2.1)
        for objWrapper in allObjects {
            coffObj := objWrapper.coff
            for i, sec in coffObj.sections {
                if (coffObj.sectionFilter[i] || !coffObj.comdatSections.Has(i))
                    continue
                comdat := coffObj.comdatSections[i]
                if (comdat.Selection == COFF.IMAGE_COMDAT_SELECT_ASSOCIATIVE) {
                    if (IsSectionDiscarded(coffObj, comdat.AssocSection)) {
                        discardedSections[ObjPtr(coffObj) ":" i] := true
                        this.dbgLogInfo .= "`t[COMDAT ASSOCIATIVE] Section '" sec.Name "' (#" i ") discarded (parent section #" comdat.AssocSection " was discarded).`n"
                    }
                }
            }
        }

        ; =================================================================================================
        ; 3: Разметка памяти (Layout), регистрация символов и сбор релокаций
        ; =================================================================================================
        objLocalOffsets := Map() ; ObjPtr(coffObj) -> Map(secIdx -> globalOffset)

        ; Шаг 3.1: Выделяем смещения (currentOffset) только для выживших секций
        for objWrapper in allObjects {
            coffObj := objWrapper.coff
            this.dbgLogInfo .= "`n[Obj] Processing object: " objWrapper.originKey "`n"
            localToGlobalOffsets := Map()
            objLocalOffsets[ObjPtr(coffObj)] := localToGlobalOffsets

            for _, i in coffObj.GetSortedSectionIndices() {
                sec     := coffObj.sections[i]
                secSize := Max(sec.SizeOfRawData, sec.VirtualSize)
                if (secSize == 0) {
                    this.dbgLogInfo .= "`t[Skip] Empty section '" sec.Name "'`n"
                    continue
                }

                secKey := ObjPtr(coffObj) ":" i
                if (discardedSections.Has(secKey))
                    continue ; Пропускаем отброшенные COMDAT и ASSOCIATIVE секции

                alignVal      := coffObj.alignment[i]
                currentOffset := (currentOffset + alignVal - 1) & ~(alignVal - 1)
                localToGlobalOffsets[i] := currentOffset
                layout.Push({CoffObj: coffObj, Section: sec, OriginalIndex: i, NewOffset: currentOffset})
                this.dbgLogInfo .= "`t[OK] Section '" sec.Name "' merged. New offset: 0x" Format("{:X}", currentOffset) ", Size: " secSize "`n"

                ; Если это победитель COMDAT — запоминаем его финальное смещение в реестре
                if (coffObj.comdatSections.Has(i) && coffObj.comdatSections[i].Selection != COFF.IMAGE_COMDAT_SELECT_ASSOCIATIVE) {
                    comdatName := coffObj.comdatSections[i].SymbolName
                    comdatRegistry[comdatName].offset := currentOffset
                }

                currentOffset += secSize
            }
        }

        ; 3.2: Привязываем отброшенные дубликаты к смещениям победителей, собираем символы и релокации
        for objWrapper in allObjects {
            coffObj              := objWrapper.coff
            localToGlobalOffsets := objLocalOffsets[ObjPtr(coffObj)]

            ; Заполняем смещения для отброшенных COMDAT-дубликатов (теперь смещения всех победителей известны)
            for i, sec in coffObj.sections {
                secKey := ObjPtr(coffObj) ":" i
                if (comdatRedirect.Has(secKey)) {
                    winnerOffset := comdatRegistry[comdatRedirect[secKey]].offset
                    localToGlobalOffsets[i] := winnerOffset
                    layout.Push({CoffObj: coffObj, Section: sec, OriginalIndex: i, NewOffset: winnerOffset, IsComdatDup: true})
                }
            }

            ; Регистрация публичных символов из выживших секций в глобальной таблице
            for symIdx, symbol in coffObj.symbolsMap {
                if (symbol.SectionIndex > 0 && symbol.StorageClass == 2) {
                    secKey := ObjPtr(coffObj) ":" symbol.SectionIndex
                    if (!discardedSections.Has(secKey) && localToGlobalOffsets.Has(symbol.SectionIndex)) {
                        symName := symbol.Name
                        symAddr := localToGlobalOffsets[symbol.SectionIndex] + symbol.Value
                        if (!globalSymbolOffsets.Has(symName))
                            globalSymbolOffsets[symName] := symAddr
                        else if (!coffObj.comdatSections.Has(symbol.SectionIndex))
                            this.dbgLogInfo .= "`t[Warning] Duplicate non-COMDAT symbol '" symName "' ignored.`n"
                    }
                } else if (symbol.SectionIndex == 0 && symbol.StorageClass == 2 && symbol.Value > 0 && !this.CleanSymbolName(symbol.Name).isImport) {
                    ; COMMON: секции нет, Value == размер. Берём максимальный размер среди всех дубликатов.
                    if (!commonRegistry.Has(symbol.Name) || commonRegistry[symbol.Name].size < symbol.Value)
                        commonRegistry[symbol.Name] := {size: symbol.Value, originKey: objWrapper.originKey}
                }
            }

            ; Сбор релокаций из выживших секций
            for i, sec in coffObj.sections {
                secKey := ObjPtr(coffObj) ":" i
                if (coffObj.sectionFilter[i] || discardedSections.Has(secKey))
                    continue

                loop (sec.NumberOfRelocations) {
                    relocOffset    := sec.PointerToRelocations + ((A_Index - 1) * COFF.SIZEOF_IMAGE_RELOCATION)
                    reloc          := coffObj.IMAGE_RELOCATION(relocOffset)
                    symbolIndex    := reloc.SymbolTableIndex
                    symbol         := coffObj.symbolsMap[symbolIndex]
                    absPatchOffset := localToGlobalOffsets[i] + reloc.VirtualAddress

                    extRef := this.ParseExternalReloc(coffObj, reloc, symbolIndex, symbol, absPatchOffset)
                    if (extRef) {
                        pendingExternalRefs.Push(extRef)
                    } else {
                        pendingRelocations.Push({CoffObj: coffObj, Reloc: reloc, Symbol: symbol, PatchOffset: absPatchOffset})
                    }
                }
            }
        }

        ; =================================================================================================
        ; 3.3: COMMON (-fcommon) - "виртуальный .bss" в хвосте Mcode
        ; =================================================================================================
        this.commonSymbols := Map()
        if (commonRegistry.Count) {
            this.dbgLogInfo .= "`n[COMMON] Allocating common (uninitialized) globals:`n"
            for name, info in commonRegistry {
                ; Сильное определение побеждает COMMON - отдельное место не нужно
                if (globalSymbolOffsets.Has(name)) {
                    this.dbgLogInfo .= "`t[COMMON] '" name "' merged into strong definition at 0x" Format("{:X}", globalSymbolOffsets[name]) "`n"
                    continue
                }
                ; В COFF у COMMON нет поля alignment, поэтому выравнивание по размеру, но не больше 16 байт.
                alignVal := 1
                while (alignVal < info.size && alignVal < 16)
                    alignVal *= 2
                currentOffset := (currentOffset + alignVal - 1) & ~(alignVal - 1)
                globalSymbolOffsets[name] := currentOffset
                this.commonSymbols[name]  := {offset: currentOffset, size: info.size}
                this.dbgLogInfo .= "`t[COMMON] '" name "' -> offset 0x" Format("{:X}", currentOffset) ", size " info.size ", align " alignVal " (" info.originKey ")`n"
                currentOffset += info.size
            }
        }

        ; =================================================================================================
        ; 4: Выделение памяти и копирование сырых данных
        ; =================================================================================================
        totalSize := currentOffset
        if (totalSize == 0)
            throw Error("No executable code or data found.")

        mcode := Buffer(totalSize, 0)
        
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
            if (!ref.isImport && globalSymbolOffsets.Has(symToFind)) {
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

        if (this.usePEParser) {
            for dll in this.importDll {
                try {
                    dllExports := PEExportParser(dll, this.is64)
                    loadedDlls[dll] := dllExports.Exports
                    this.dbgLogInfo .= "`tLoaded DLL (Parsed): '" dllExports.DllPath "'`n"
                } catch as er {
                    throw Error(er.Message)
                }
            }
        } else {
            for dll in this.importDll {
                if (hMod := DllCall("LoadLibrary", "Str", dll, "Ptr")) {
                    loadedDlls[dll] := hMod
                    this.dbgLogInfo .= "`tLoaded DLL (LoadLibrary): '" dll "'`n"
                } else {
                    this.dbgLogInfo .= "`t[Warning] Failed to load DLL: '" dll "'`n"
                }
            }
        }

        ; Я так и не понял есть ли вообще смысл использовать PE парсер для поиска символов, ведь по сути их имена не отличаются у разных архитектур (и одноименных dll)...
        ; Как будто LoadLibrary + GetProcAddress работает отлично как для x86 так и для x64...
        ; В общем пусть будет два варианта, ибо я так и не понял что лучше оставить.
        ; PE парсер работает криво, то есть в 10-20% нужно указывать абсалютный путь к нужной dll - это не удобно, но не критично.
        ResolveAndAdd(exp, writeIAT := true) {
            disp := this.is32 ? 4 : exp.type
            for dll in this.importDll {
                if (this.usePEParser) {
                    dllExport := loadedDlls[dll]
                    if (dllExport.Has(exp.func)) {
                        if (writeIAT) {
                            exportFunc := this.useOrdinals ? dllExport[exp.func].Ordinal : exp.func
                            mcodeBuildRules.IAT.Push({Dll: dll, ExportFunc: exp.func, PatchOffset: exp.patchOffset, Disp: disp})
                        }
                        this.dbgLogInfo .= "`t[OK] Symbol '" exp.func " [" dllExport[exp.func].Ordinal "]' found in " dll ". Added to IAT.`n"
                        return true
                    }
                } else {
                    if !(loadedDlls.Has(dll))
                        continue
                    hMod := loadedDlls[dll]
                    if (DllCall("GetProcAddress", "Ptr", hMod, "AStr", exp.func, "Ptr")) {
                        if (writeIAT) {
                            mcodeBuildRules.IAT.Push({Dll: dll, ExportFunc: exp.func, PatchOffset: exp.patchOffset, Disp: disp})
                        }
                        this.dbgLogInfo .= "`t[OK] Symbol '" exp.func "' found in " dll ". Added to IAT.`n"
                        return true
                    }
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
                        this.shortDbgInfo .= "Not found imports [DLL]:`n"
                        line := false
                    }
                    this.shortDbgInfo .= "`tsymbol: '" exp.func "' -> offset: " Format("0x{:X}", exp.patchOffset) " -> reloc type " Format("0x{:X}", exp.type) "`n"
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
                this.shortDbgInfo .= "Unresolved symbols not found (static)`n"
                for exp in this.unresolvedSymbols {
                    this.shortDbgInfo .= "`tsymbol: '" exp.func "' -> offset: " Format("0x{:X}", exp.patchOffset) " -> reloc type " Format("0x{:X}", exp.type) . (ResolveAndAdd(exp, false) ? " // It can be made dynamic`n" : " // This cannot be made dynamic.`n")
                }
            }
        }

        if (this.VAreloc.Length) {
            this.dbgLogInfo .= "`n[IAT] Adding VA relocations:`n"
            for va in this.VAreloc {
                mcodeBuildRules.VA.Push({Size: va.size, Offset: va.offset})
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
                    this.exportedSymbols[i] := {symbol: symbol.Name, offset: secOffset + symbol.Value, opt: symbol.StorageClass != 2 ? "[dispensable] | " : ""}
                }
            }
        }

        for symIdx, symbol in this.symbolsMap {
            if (symbol.SectionIndex == 0 && symbol.StorageClass == 2 && this.commonSymbols.Has(symbol.Name)) {
                info := this.commonSymbols[symbol.Name]
                this.exportedSymbols[symIdx] := {symbol: symbol.Name, offset: info.offset, opt: "[common] | "}
            }
        }

        this.dbgLogInfo .= "`n[Linker] Linking process completed " . (this.shortDbgInfo == "" ? "successfully, most likely no errors!`n" : "with errors. Check main GUI for potential issues...`n")

        return {Mcode: mcode, McodeBuildRules: mcodeBuildRules}
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
}


; Класс обертка над "COFF". Отвечает за сборку Mcode в целом, и парсинг данных под X вывод.
class MCF_Builder {
    class Blob {
        static SIZEOF_BLOB_HDR := 64
        static SIZEOF_IMP_REC  := 17
        static SIZEOF_VA_REC   := 5

        ; MCF 1.0.7
        ; TDM-GCC 10.3.0
        ; -m64 -Os -fPIC -nostdlib -fno-ident -fomit-frame-pointer -fno-stack-protector -fno-asynchronous-unwind-tables -falign-functions=1 -falign-jumps=1 -falign-loops=1 -Wl,--build-id=none
        ; offset["sc_main"] := ptr + 0x100 ;
        ; offset["sc_start"] := ptr + 0x0 ;
        static stub_x64 := "
        (
        00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e800000000594883e945e9a000000031c088140148ffc048
        c1ea084883f80875f031c0448844010848ffc049c1e8084883f80875eec38b413c4989d08b94018800000031c085d274654801ca575653448b4a208b7a184901c939c7764b458b1c814531d24901cb4489d3418a341b418a
        1c184084f6740a4038de752741ffc2ebe684db751e448b42244801c04801c8460fb704008b421c4a8d14818b04024801c8eb0748ffc0ebb131c05b5e5fc3c34157415641554154555756534883ec7881394d4353310f857f
        0100008b41044531e44889cb83e0018944242c0f85400100008b411c4c8d7c24608b691049b865006c003300320048ba6b00650072006e008b71248b7918448b61204c89f989442448e8f9feffff65488b04256000000048
        8b40184c8d4020488b40204885c00f841f0100004939c00f8416010000668378480f76214c8b485031d266418b0c1183c92066413b0c17750c4883c2024883fa1075e7eb05488b00ebc14c8b68204d85ed0f84dc0000004c
        8d54245041b86172794148ba4c6f61644c6962724c89d1e87bfeffff4c89f949b8646472657373000048ba47657450726f6341e85ffeffff4c89d24c89e9e87bfeffff4c89fa4989c6e870feffff4989c74d85f60f846e01
        00004885c00f846501000089f84189e94801de4531ed48894424384a8d04234a8d2c0b4531e448894424304183caff31c944396b0877578b4c24488b44242c39430c0f87ff0000004585e47504834b04018b432885c00f84
        1a0100004585e40f85110100004883c4784801d85b5e5f5d415c415d415e415fffe04183ccffe9f300000041bcfeffffffe9e80000004489ef486bff1148037c24384801df8b074439d0741089c148034c243041ffd6448b
        174889c14885c974328b4704488b542430448954244c48894c24404801c2807f1000480f45d041ffd7488b4c2440448b54244c4885c04889c2750541ffc4eb4f8b47084801e8448a48ff458d59184180fb01772566c706ff
        254989f34883c610c746f200000000488956f68b570c4801c24929d3448918eb164889168b570c4989f34883c6084801c24929d344891841ffc5e9eafeffff8b44242c488d04804801c84801d88b104801ea807804087505
        48012aeb02012aff44242ce9cbfeffff41bcfdffffff4883c4784489e05b5e5f5d415c415d415e415fc3909090909090
        )"

        ; MCF 1.0.7
        ; TDM-GCC 10.3.0
        ; -m32 -Os -fPIC -nostdlib -fno-ident -fomit-frame-pointer -fno-stack-protector -fno-asynchronous-unwind-tables -falign-functions=1 -falign-jumps=1 -falign-loops=1 -Wl,--build-id=none
        ; offset["_sc_main"] := ptr + 0x105 ; 
        ; offset["sc_start"] := ptr + 0x0 ; 
        static stub_x86 := "
        (
        00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e8000000005883e84550e8b600000083c404c35756538b74
        241089c389d08b7c241489ca31c988040b410facd008c1ea0883f90875f031c089f20facfe088854030840c1ef0883f80875ed5b5e5fc35589d557565383ec0c8b503c8b74107885f6745801c631d28b4e208b7e1801c189
        3c24894c24083b142474408b4c240831ff8b1c9101c3895c24048b5c24048a4c3d008a1c3b84db740738cb751b47ebea84c9751401d201c20356240fb7128d149003561c0302eb0542ebbb31c083c40c5b5e5f5dc3555756
        5383ec6c8bac2480000000817d004d4353310f859f0100008b450431ff83e001894424180f856f0100008b45108d5c2450ba6b006500b972006e00894424108b4524894424148b4518894424208b451c894424348b4520c7
        042465006c00c7442404330032008944242489d8e8dafeffff64a1300000008b400c8d701c8b401c85c00f843701000039c60f842f010000668378280f761a8b782c31d2668b0c5783c920663b0c5375084283fa0875edeb
        048b00ebcb8b701085f60f84ff000000c7042461727941ba4c6f6164b94c6962728d442440c744240400000000e869feffffc7042464647265b9726f634189d8c744240473730000ba47657450e849feffff8d54244089f0
        e87afeffff89da8944242c89f0e86dfeffff837c242c00894424300f845801000085c00f84500100008b4424108b5c2420c7442420ffffffff31ff01e801eb894424108b442414c74424140000000001e88944241c8b4424
        24c74424240000000001e8894424288b44242439450877518b4c24348b44241031d201e98b74241839750c0f87cb00000085ff7504834d04018b452885c00f84e200000085ff0f85da00000083c46c01e85b5e5f5dffe083
        cfffe9c7000000bffeffffffe9bd0000008b033b4424207418034424288904248b44242cffd051894424148b0389442420837c24140074278b53048b44242801d0807b10000f45c2894424048b4424148904248b442430ff
        d0525285c0750347eb368b7424100373088a56ff83c21880fa0177198b4b0cc744243c0000000001f1894c24382b4424388906eb0b8b4c241c8344241c048901ff44242483c311e913ffffff8b5c24100319807904087507
        0103115304eb068b7424100133ff44241883c105e903ffffffbffdffffff83c46c89f85b5e5f5dc3
        )"


        __New(mcodeBuffer, buildRulesObj, is64 := true, entryPoint := 0) {
            this.mcodeBuffer      := mcodeBuffer
            this.mcodeSize        := mcodeBuffer.Size
            this.buildRulesObj    := buildRulesObj
            this.VA_size          := is64 ? 8 : 4
            this.entryPoint       := entryPoint

            this.stubBuffer       := Binary.StringToBinary(RegExReplace(is64 ? MCF_Builder.Blob.stub_x64 : MCF_Builder.Blob.stub_x86, "\s+"), 12)
            this.importCount      := this.buildRulesObj.IAT.Length
            this.VACount          := this.buildRulesObj.VA.Length
            this.IATSize          := this.importCount * (is64 ? 16 : 4)
            this.imp_RVA          := this.stubBuffer.size + this.mcodeSize
            this.VA_RVA           := this.imp_RVA + (this.importCount * MCF_Builder.Blob.SIZEOF_IMP_REC)
            this.pool_RVA         := this.VA_RVA + (this.VACount * MCF_Builder.Blob.SIZEOF_VA_REC)
            this.IAT_RVA          := this.pool_RVA + this.GetStringPoolSize()
            this.totalSize        := this.IAT_RVA + this.IATSize
            this.Payload_RVA      := this.stubBuffer.size ; DllCall(Ptr + Payload_RVA + offset)
        }


        Build() {
            if (this.buildRulesObj.IAT.Length == 0 && this.buildRulesObj.VA.Length == 0) {
                this.Payload_RVA := 0
                return this.mcodeBuffer ; Если Mcode и так PIC, то нет смысла тянуть стаб
            }

            FinalBlob := Buffer(this.totalSize, 0)
            RtlMoveMemory(FinalBlob.Ptr, this.stubBuffer.Ptr, this.stubBuffer.size)
            NumPut("UInt", 0x3153434D,            ; MAGIC (MCS1)
                   "UInt", 0,                     ; flags (0)
                   "UInt", this.importCount,      ; n_imports
                   "UInt", this.VACount,          ; n_va
                   "UInt", this.stubBuffer.size,  ; payload_rva
                   "UInt", this.mcodeSize,        ; payload_size
                   "UInt", this.imp_RVA,          ; imp_rva
                   "UInt", this.VA_RVA,           ; va_rva
                   "UInt", this.pool_RVA,         ; pool_rva
                   "UInt", this.IAT_RVA,          ; iat_rva
                   "UInt", this.entryPoint,       ; entry_rva (0 для MCode, иначе смещение внутри Payload)
                FinalBlob)

            RtlMoveMemory(FinalBlob.Ptr + this.stubBuffer.size, this.mcodeBuffer.Ptr, this.mcodeSize)

            current_pool_offset := 0
            for i, imp in this.buildRulesObj.IAT {
                o     := this.imp_RVA + ((i - 1) * MCF_Builder.Blob.SIZEOF_IMP_REC)
                isOrd := IsInteger(imp.ExportFunc)

                NumPut("UInt", current_pool_offset, FinalBlob.Ptr + 0 + o)
                written_bytes := StrPut(imp.Dll, FinalBlob.Ptr + this.pool_RVA + current_pool_offset, "CP0")
                current_pool_offset += written_bytes

                if (isOrd) {
                    NumPut("UInt", imp.ExportFunc, FinalBlob.Ptr + 4 + o)
                } else {
                    NumPut("UInt", current_pool_offset, FinalBlob.Ptr + 4 + o)
                    written_bytes := StrPut(imp.ExportFunc, FinalBlob.Ptr + this.pool_RVA + current_pool_offset, "CP0")
                    current_pool_offset += written_bytes
                }

                NumPut("UInt",  imp.PatchOffset, FinalBlob.Ptr + 8  + o)
                NumPut("UInt",  imp.Disp,        FinalBlob.Ptr + 12 + o)
                NumPut("UChar", isOrd,           FinalBlob.Ptr + 16 + o)
            }

            for i, va_data in this.buildRulesObj.VA {
                o := this.VA_RVA + ((i - 1) * MCF_Builder.Blob.SIZEOF_VA_REC)
                NumPut("UInt",  va_data.Offset, FinalBlob.Ptr + 0 + o)
                NumPut("UChar", va_data.Size,        FinalBlob.Ptr + 4 + o)
            }

            return FinalBlob
        }


        GetStringPoolSize() {
            stringPoolSize := 0
            for imp in this.buildRulesObj.IAT {
                stringPoolSize += StrPut(imp.Dll, "CP0")
                if (!IsInteger(imp.ExportFunc)) { ; НЕ ординал
                    stringPoolSize += StrPut(imp.ExportFunc, "CP0")
                }
            }
            return stringPoolSize
        }
    }

    static BUILD_AHK_MCODE           := 1 ; Привязан к языку "ahk v2" (требуется функция загрузчик "GetMcodePtr" - суммарно меньше байт).
    static BUILD_PIC_SHELLCODE       := 2 ; Обычный Shellcode со своей точкой входа.
    static BUILD_PIC_MCODE_LIBRARIES := 3 ; Тоже самое что и AHK_MCODE, но только не зависит от языка (произвольный вызов функций в отличии от Shellcode).
    static BUILD_EXE                 := 4 ; Обычный PE Exe (не реализовано).
    static BUILD_DLL                 := 5 ; Обычный PE Dll (не реализовано).
    static BUILD_FROM_CACHE          := 6 ; Сборка из json правил + bin (не реализовано).

    __New(obj, importDll, ignoreSections, fullOffsetTable, dynamicLinking, staticLibraries, dynamicSubstitution, staticSubstitution, useOrdinals, usePEParser, demangleLvl := 1, languageFormat := "AHK", entryPoint := "mainA") {
        this.demangleLvl    := demangleLvl    ; Деманглирование символов в таблице смещений. (1 - только имнна, 2 - только сигнатуры, 3 - имена + сиги).
        this.languageFormat := languageFormat ; AHK | C / C++ (меняется вывод самого Mcode + таблицы смещений).
        this.entryPoint     := entryPoint     ; Пользовательский символ (или ручное смещение "цифра") который будет являться точкой входа (кроме "main", ибо это слово зарезервировано компилятором).

        this.coffObj    := COFF(obj, importDll, ignoreSections, fullOffsetTable, dynamicLinking, staticLibraries, dynamicSubstitution, staticSubstitution, useOrdinals, usePEParser)
        this.__mcodeObj := this.coffObj.Linker()

        this.McodeRaw        := this.__mcodeObj.Mcode
        this.McodeBuildRules := this.__mcodeObj.McodeBuildRules
        this.OtherDbgInfo    := "" ; Прочая dbg info (оповещения о сборки X формата Mcode)
    }


    AutoBuild(buildFormat) {
        switch (buildFormat) {
            case MCF_Builder.BUILD_AHK_MCODE           : return this.AHKMcode()
            case MCF_Builder.BUILD_PIC_SHELLCODE       : return this.PICShellcode()
            case MCF_Builder.BUILD_PIC_MCODE_LIBRARIES : return this.PICMcodeLibrary()
            case MCF_Builder.BUILD_EXE                 : return this.Exe()
            case MCF_Builder.BUILD_DLL                 : return this.Dll()
            case MCF_Builder.BUILD_FROM_CACHE          : return this.JsonCache()
            default                                    : throw Error("AutoBuild: Unsupported build type...")
        }
    }


    AHKMcode() {
        ret               := {hex: "", base64: "", compress: "", table: "", dbg: {ALL: "", short: "", other: ""}}
        dataTail          := "|"
        this.OtherDbgInfo .= 'You are assembling "AHK Mcode"...`n'

        for prop in this.McodeBuildRules.IAT {
            dataTail .= prop.Dll ":" prop.ExportFunc ":" prop.PatchOffset ":" prop.Disp "|"
        }
        for prop in this.McodeBuildRules.VA {
            dataTail .= "VA:" prop.Size ":" prop.Offset "|"
        }

        dataTail          := RTrim(dataTail, "|")
        ret.hex           := Binary.BinaryToStrin(this.McodeRaw, this.McodeRaw.Size, 12)           . dataTail
        ret.base64        := Binary.BinaryToStrin(this.McodeRaw, this.McodeRaw.Size, 1)            . dataTail
        ret.compress      := Binary.BinaryToCompressedBase64(this.McodeRaw, this.McodeRaw.Size, 2) . dataTail
        ret.table         := Demangle.ExportedSymbolsDump(this.coffObj.exportedSymbols, this.demangleLvl, this.languageFormat, 0)
        this.OtherDbgInfo .= 'The assembly was successful!'
        ret.dbg.ALL       := this.coffObj.dbgLogInfo
        ret.dbg.short     := this.coffObj.shortDbgInfo
        ret.dbg.other     := this.OtherDbgInfo

        return ret
    }


    PICShellcode() {
        ret               := {hex: "", base64: "", compress: "", table: "", dbg: {ALL: "", short: "", other: ""}}
        this.OtherDbgInfo .= 'You are assembling "PIC Shellcode"...`n'

        b                 := MCF_Builder.Blob(this.McodeRaw, this.McodeBuildRules, this.coffObj.is64, 0)
        b.entryPoint      := this.SearchEntryPoint(b.Payload_RVA)
        finalBlob         := b.Build()
        ret.hex           := Binary.BinaryToStrin(finalBlob, finalBlob.Size, 12)
        ret.base64        := Binary.BinaryToStrin(finalBlob, finalBlob.Size, 1)
        ret.compress      := Binary.BinaryToCompressedBase64(finalBlob, finalBlob.Size, 2)
        ret.table         := Demangle.ExportedSymbolsDump(this.coffObj.exportedSymbols, this.demangleLvl, this.languageFormat, b.Payload_RVA)
        ret.dbg.ALL       := this.coffObj.dbgLogInfo
        ret.dbg.short     := this.coffObj.shortDbgInfo
        ret.dbg.other     := this.OtherDbgInfo

        return ret
    }


    PICMcodeLibrary() {
        ret               := {hex: "", base64: "", compress: "", table: "", dbg: {ALL: "", short: "", other: ""}}
        this.otherDbgInfo .= 'You are assembling "PIC Mcode Library"...`n'

        b                 := MCF_Builder.Blob(this.McodeRaw, this.McodeBuildRules, this.coffObj.is64, 0)
        finalBlob         := b.Build()
        ret.hex           := Binary.BinaryToStrin(finalBlob, finalBlob.Size, 12)
        ret.base64        := Binary.BinaryToStrin(finalBlob, finalBlob.Size, 1)
        ret.compress      := Binary.BinaryToCompressedBase64(finalBlob, finalBlob.Size, 2)
        ret.table         := Demangle.ExportedSymbolsDump(this.coffObj.exportedSymbols, this.demangleLvl, this.languageFormat, b.Payload_RVA)
        this.otherDbgInfo .= 'The assembly was successful!'
        ret.dbg.ALL       := this.coffObj.dbgLogInfo
        ret.dbg.short     := this.coffObj.shortDbgInfo
        ret.dbg.other     := this.OtherDbgInfo

        return ret
    }


    Exe() {
        throw Error("The EXE build is not supported! Choose other build options...")
    }


    Dll() {
        throw Error("The DLL build is not supported! Choose other build options...")
    }


    JsonCache() {
        throw Error("JsonCache: Not implemented...")
    }


    SearchEntryPoint(Payload_RVA) {
        for i, sym in this.coffObj.exportedSymbols {
            if (this.entryPoint is String && sym.symbol == this.entryPoint) {
                if (sym.symbol == "main") {
                    this.otherDbgInfo .= 'ERROR: You cannot use the symbol "main" as an entry point, as it is reserved by the compiler. Please change it to something else of your choosing.`n'
                    return 0
                }
                this.otherDbgInfo .= 'Entry point successfully set "' sym.symbol ' -> ' Format("0x{:X}", sym.offset + Payload_RVA) '"`nThe assembly was successful!`n'
                return sym.offset + Payload_RVA
            } else if (IsInteger(this.entryPoint)) {
                this.otherDbgInfo .= "Entry point successfully set... This is the number " Format("0x{:X}", this.entryPoint) ". This is acceptable. However, ensure that it is a valid offset.`nThe assembly was successful!`n"
                return this.entryPoint
            } else {
                this.otherDbgInfo .= 'ERROR: Entry point "' this.entryPoint '" not found. In the settings window, specify the actual symbol name that will serve as YOUR entry point, or the offset (number).`n'
                return 0
            }
        }
    }
}
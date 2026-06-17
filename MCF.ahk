#Requires AutoHotkey v2.0
#SingleInstance Force
#Include const.ahk

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
            result[rawName] := content
            properties.Push(rawName)
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

    static SIZEOF_IMAGE_SECTION_HEADER := 40
    static SIZEOF_IMAGE_FILE_HEADER    := 20
    static SIZEOF_IMAGE_SYMBOL         := 18
    static SIZEOF_IMAGE_RELOCATION     := 10
    static IMAGE_FILE_MACHINE_I386     := 0x14c  ; x86
    static IMAGE_FILE_MACHINE_AMD64    := 0x8664 ; x64

    static IMAGE_SYM_CLASS_FILE := 103

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
     */
    __New(path, importDll := ["User32", "msvcrt"], ignoreSections := [".pdata", ".xdata", ".rdata$zzz"], fullOffsetTable := true, entryPoint := 0x0) {
        this.path            := path            ; Путь до COFF (.o / .obj) файла.
        this.importDll       := importDll       ; Массив dll которые используются в конечном Mcode (если есть внешнии символы).
        this.ignoreSections  := ignoreSections  ; Массив секций, которые будут игнорироватся при линковке (в основном сюда ничего не нужно дописывать).
        this.fullOffsetTable := fullOffsetTable ; Если fullOffsetTable == false, то линковщик вернет смещения только нужных символов (функции / глобалки*), в ином случае будет полная таблица всех символов.
        this.entryPoint      := entryPoint      ; Точка входа.

        this.exportedSymbols := Map() ; Таблица смещений всех функций / секций / глобальных переменных, и тд. которые есть в конечном Mcode.
        this.VAreloc         := []    ; Массив VA релокаций - VirtualAlloc + RVA (известно только при запуске). В 99% случаев VA релокаций не будет в конечном Mcode.
        this.sectionFilter   := []    ; Массив 0 && 1. Фильтрует бесполезные секции при линковке, что бы не захватывать их в конечный Mcode (например это .xdata | .pdata).
        this.alignment       := []    ; Массив выравнивания данных по границе в X байт. Для производительности нужно учитывать выравнивание байт при объединение секций.
        this.headerCharact   := Map() ; Все константы характеристик [key == Idx sec, value == const flags]. Это dbg info.
        this.export          := []    ; Массив объектов - содержит релокации + функции (без секций), а так же sectionIndex + patchOffset.
        this.relocations     := []    ; Массив объектов - содержит все релокации, их тип, symbolIndex, а так же именна секций + функций [IMAGE_RELOCATION()]. Dbg info.
        this.symbolsMap      := Map() ; Все символы COFF [key == symbolIndex, value == IMAGE_SYMBOL()].
        this.sections        := []    ; Массив объектов - содержит все секции COFF [IMAGE_SECTION_HEADER()].
        this.file            := FileOpen(this.path, "r")
        this.size            := this.file.Length
        this.ptr             := Buffer(this.size)
        this.file.RawRead(this.ptr)
        this.file.Close()

        this.is64 := this.IMAGE_FILE_HEADER(0).Machine == COFF.IMAGE_FILE_MACHINE_AMD64
        this.is32 := this.IMAGE_FILE_HEADER(0).Machine == COFF.IMAGE_FILE_MACHINE_I386
        if (this.is32 + this.is64 != 1)
           throw Error("Not a valid 32/64 bit COFF file...")

        this.ReadSymbol()
        this.ReadSection()
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
        symbolIndex := 0
        while (symbolIndex < this.NUMBER_OF_SYMBOLS) {
            nextSymbol := this.IMAGE_SYMBOL(this.POINTER_TO_SYMBOL_TABLE + (symbolIndex * COFF.SIZEOF_IMAGE_SYMBOL))
            this.symbolsMap[symbolIndex] := nextSymbol
            if (nextSymbol.StorageClass == COFF.IMAGE_SYM_CLASS_FILE) {
                symbolIndex++ ; Имя файла хранится в auxiliary записи, которая следует сразу за основным символом (Зачем это надо? Для красоты!)
                continue
            }
            symbolIndex += 1 + nextSymbol.NumberOfAuxSymbols ; Вспомогательные символы (Auxiliary Symbols)
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

                ; if (this.symbolsMap.Has(symbolIndex) && this.symbolsMap[symbolIndex].StorageClass == 2 && !this.symbolsMap[symbolIndex].SectionIndex) {
                ;     if (funcName ~= "^__imp_")
                ;         funcName := SubStr(funcName, 7)
                ;     this.export.Push({reloc: reloc.VirtualAddress, func: funcName}) ; Только нужные релокации + функции (без секций)
                ; }
                
                this.relocations.Push({reloc: reloc.VirtualAddress, section: funcName, type: reloc.Type, SymbolTableIndex: symbolIndex})
            }
            this.sections.Push(section)
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

            for name, value in COFF.IMAGE_SECTION_HEADER_CHARACTERISTICS {
                if InStr(name, "ALIGN") {
                    if ((sec.Characteristics & ALIGN_MASK) == value) {
                        charact.Push(name)
                        hasAlign := true
                        alignBytes := RegExReplace(name, "\D+", "")
                        this.alignment.Push(alignBytes != "" ? Integer(alignBytes) : 0)
                    }
                } else {
                    if (sec.Characteristics & value) {
                        charact.Push(name)
                    }
                }
            }

            if (!hasAlign) {
                this.alignment.Push(4) ; минимальное выравнивае, чтобы математика не ломалась если у секции нет ALIGN флага.
            }

            this.headerCharact[i " " sec.Name] := charact ; dbg info [ПОТОМ ДОДЕЛАТЬ]
            this.sectionFilter.Push(isUseless ? 1 : 0) ; Нужные секции для линковки
        }
    }


    ApplyRelocation(mcode, targetAddress, patchAddress, relocType) {
        static IMAGE_REL_AMD64_ADDR64   := 0x0001
        static IMAGE_REL_AMD64_ADDR32   := 0x0002
        static IMAGE_REL_AMD64_ADDR32NB := 0x0003
        static IMAGE_REL_AMD64_REL32    := 0x0004
        static IMAGE_REL_AMD64_REL32_1  := 0x0005
        static IMAGE_REL_AMD64_REL32_2  := 0x0006
        static IMAGE_REL_AMD64_REL32_3  := 0x0007
        static IMAGE_REL_AMD64_REL32_4  := 0x0008
        static IMAGE_REL_AMD64_REL32_5  := 0x0009

        static IMAGE_REL_I386_DIR32   := 0x0006
        static IMAGE_REL_I386_DIR32NB := 0x0007
        static IMAGE_REL_I386_REL32   := 0x0014

        if (this.is64) {
            switch relocType {
                case IMAGE_REL_AMD64_ADDR64   : NumPut("Int64", targetAddress, mcode, patchAddress), this.VAreloc.Push({offset: patchAddress, size: 8})
                case IMAGE_REL_AMD64_ADDR32   : NumPut("UInt", targetAddress, mcode, patchAddress),  this.VAreloc.Push({offset: patchAddress, size: 4})
                case IMAGE_REL_AMD64_ADDR32NB : NumPut("UInt", targetAddress, mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32    : NumPut("Int", targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 4), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_1  : NumPut("Int", targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 5), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_2  : NumPut("Int", targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 6), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_3  : NumPut("Int", targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 7), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_4  : NumPut("Int", targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 8), mcode, patchAddress)
                case IMAGE_REL_AMD64_REL32_5  : NumPut("Int", targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 9), mcode, patchAddress)
                default: throw Error(Format("Unsupported relocation type [x64]: 0x{:04X}", relocType))
            }
        } else {
            switch relocType {
                case IMAGE_REL_I386_DIR32   : NumPut("UInt", targetAddress, mcode, patchAddress), this.VAreloc.Push({offset: patchAddress, size: 4})
                case IMAGE_REL_I386_DIR32NB : NumPut("UInt", targetAddress, mcode, patchAddress)
                case IMAGE_REL_I386_REL32   : NumPut("Int", targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 4), mcode, patchAddress)
                default: throw Error(Format("Unsupported relocation type [x86]: 0x{:04X}", relocType))
            }
        }
    }


    Linker() {
        ; layout := []
        ; currentOffset := 0

        ; for i, sec in this.sections {
        ;     if (this.sectionFilter[i])
        ;         continue

        ;     currentOffset := (currentOffset + this.alignment[i] - 1) & ~(this.alignment[i] - 1) ; Выравнивание
        ;     layout.Push({Section: sec, OriginalIndex: i, NewOffset: currentOffset})
        ;     currentOffset += Max(sec.SizeOfRawData, sec.VirtualSize) ; sec.VirtualSize - нужен для .bss (наверное), хотя я в этом не уверен
        ; }

        ; totalSize := currentOffset
        ; if (totalSize == 0)
        ;     throw Error("No executable code or data found.")
            
        ; mcode := Buffer(totalSize, 0)
        ; for item in layout {
        ;     if (item.Section.PointerToRawData > 0 && Max(item.Section.SizeOfRawData, item.Section.VirtualSize) > 0) {
        ;         DllCall("RtlMoveMemory", "Ptr", mcode.Ptr + item.NewOffset, "Ptr", this.ptr.Ptr + item.Section.PointerToRawData, "UPtr", item.Section.SizeOfRawData)
        ;     }
        ; }


        layout        := []
        currentOffset := this.entryPoint <= 0 ? 0 : this.entryPoint <= 0xFF ? 2 : this.entryPoint <= 0xFFFFFFFF ? 5 : 0

        for i, sec in this.sections {
            if (this.sectionFilter[i])
                continue

            currentOffset := (currentOffset + this.alignment[i] - 1) & ~(this.alignment[i] - 1) ; Выравнивание
            layout.Push({Section: sec, OriginalIndex: i, NewOffset: currentOffset})
            currentOffset += Max(sec.SizeOfRawData, sec.VirtualSize)
        }

        totalSize := currentOffset
        if (totalSize == 0)
            throw Error("No executable code or data found.")
            
        mcode := Buffer(totalSize, 0)
        COFF.EntryPoint(this.entryPoint + (this.entryPoint == 0 ? 0 : this.alignment[1]), mcode)
        for item in layout {
            if (item.Section.PointerToRawData > 0 && Max(item.Section.SizeOfRawData, item.Section.VirtualSize) > 0) {
                DllCall("RtlMoveMemory", "Ptr", mcode.Ptr + item.NewOffset, "Ptr", this.ptr.Ptr + item.Section.PointerToRawData, "UPtr", item.Section.SizeOfRawData)
            }
        }

        ; релокации (патчинг адресов)
        for item in layout {
            loop (item.Section.NumberOfRelocations) {
                relocOffset := item.Section.PointerToRelocations + ((A_Index - 1) * COFF.SIZEOF_IMAGE_RELOCATION)
                reloc       := this.IMAGE_RELOCATION(relocOffset)
                symbolIndex := reloc.SymbolTableIndex
                symbol      := this.symbolsMap[symbolIndex]
                
                targetSectionNewOffset := -1
                for targetItem in layout { ; Ищем куда переехала секция на которую ссылается символ
                    if (targetItem.OriginalIndex == symbol.SectionIndex) {
                        targetSectionNewOffset := targetItem.NewOffset
                        break
                    }
                }

                ; Внешнии символы
                if (this.symbolsMap.Has(symbolIndex) && this.symbolsMap[symbolIndex].StorageClass == 2 && !this.symbolsMap[symbolIndex].SectionIndex) {
                    funcName := this.symbolsMap[symbolIndex].Name
                    if (funcName ~= "^__imp_")
                        funcName := SubStr(funcName, 7)
                    this.export.Push({func: funcName, type: reloc.Type, sectionIndex: item.OriginalIndex, patchOffset: item.NewOffset + reloc.VirtualAddress})
                    continue
                }

                if (targetSectionNewOffset == -1)
                    throw Error("targetSectionNewOffset == -1 [DBG INFO]")

                targetAddress := targetSectionNewOffset + symbol.Value ; реальный адрес, куда указывает символ в новом буфере. symbol.Value - это смещение символа внутри его родной секции
                patchAddress := item.NewOffset + reloc.VirtualAddress  ; адрес самой инструкции, которую нужно пропатчить
                this.ApplyRelocation(mcode, targetAddress, patchAddress, reloc.Type) ; патчинг релокаций внутренних символов
            }
        }

        ;============================================ кастомный мини IAT + VA reloc ============================================

        loadedDlls := Map()
        for dll in this.importDll {
            if (hMod := DllCall("LoadLibrary", "Str", dll, "Ptr")) {
                loadedDlls[dll] := hMod
            }
        }

        IAT := "|"
        if (this.export.Length) {
            for exp in this.export {
                disp := this.is32 ? 4 : exp.type ; для x64 значение констант (exp.type - тип релокации) соответствует displacement (смещение RIP-relative), а для x86 там всегда цифра 4.
                found := false
                for dll, hMod in loadedDlls {
                    if (DllCall("GetProcAddress", "Ptr", hMod, "AStr", exp.func, "Ptr")) {
                        IAT .= dll ":" exp.func ":" exp.patchOffset ":" disp "|"
                        found := true
                        break
                    }
                }
                
                if (!found) {
                    IAT .= "UNKNOWN_DLL:" exp.func ":" exp.patchOffset ":" disp "|"
                }
            }
        }

        ; VA-релокации (если они есть) размещаются в тот же IAT-хвост, но с префиксом "VA"
        for va in this.VAreloc {
            IAT .= "VA:" va.size ":" va.offset "|"
        }

        ;============================================ таблица символов ============================================

        for i, symbol in this.symbolsMap {
            if (symbol.SectionIndex > 0 && (symbol.StorageClass == 2) || this.fullOffsetTable) { ; Обычно функции и глобалки имеют StorageClass == 2 (External), а остальное не важно (там в основном секции)
                secOffset := -1
                for item in layout {
                    if (item.OriginalIndex == symbol.SectionIndex) {
                        secOffset := item.NewOffset
                        break
                    }
                }
                
                if (secOffset != -1) {
                    ;this.exportedSymbols[i] := symbol.Name " := " Format("0x{:X}", secOffset + symbol.Value)
                    this.exportedSymbols[i] := {symbol: symbol.Name, offset: Format("0x{:X}", secOffset + symbol.Value), opt: symbol.StorageClass != 2 ? " [dispensable]" : ""} ; итоговый оффсет = адрес секции + смещение внутри секции
                }
            }
        }

        ;============================================ конечный Mcode + таблица ============================================
        ; hex := ""
        ;     loop (mcode.Size)
        ;         hex .=  Format("{:02X}", NumGet(mcode,  A_Index - 1, "UChar"))
        ;return {mcode: Binary.BinaryToStrin(mcode, mcode.Size, 12) . RTrim(IAT, "|"), table: this.exportedSymbols}

        exportedSymbolsStr := "offset := Map()`n"
        for value, symbol in this.exportedSymbols {
            exportedSymbolsStr .= "offset[" Chr(34) symbol.symbol Chr(34) "] := " symbol.offset " `; " value symbol.opt "`n"
        }

        return {
            hex:      Binary.BinaryToStrin(mcode, mcode.Size, 12)           . RTrim(IAT, "|"),
            base64:   Binary.BinaryToStrin(mcode, mcode.Size, 1)            . RTrim(IAT, "|"),
            compress: Binary.BinaryToCompressedBase64(mcode, mcode.Size, 2) . RTrim(IAT, "|"),
            table:    RTrim(exportedSymbolsStr, "`n") ; this.exportedSymbols
        }
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
                m[sec.Name] := {hex: hex, dump: sec.SizeOfRawData == 0 ? "Empty section" : Binary.HexToASCII(this.ptr.Ptr + sec.PointerToRawData, sec.SizeOfRawData, bytesPerLine)}
            } else {
                m[sec.Name] := {hex: hex}
            }
            prop.Push(sec.Name)
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


class StaticLibraryParser {
    static IMAGE_ARCHIVE_START := "!<arch>`n"
    static SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER := 60

    MAGIC => StrGet(this.ptr.Ptr, 8, "UTF-8")

    __New(libPath) {
        this.firstSymbolMap  := Map()   ; Имя символа -> смещение
        this.secondSymbolMap := Map()   ; Имя символа -> смещение
        this.longNames       := []      ; Индексированный массив строк из Longnames Member
        this.Members         := []      ; [{Name: "file.o", DataOffset: ..., Size: ...}, ...]

        this.file := FileOpen(libPath, "r")
        this.size := this.file.Length
        this.ptr  := Buffer(this.size)
        this.file.RawRead(this.ptr)
        this.file.Close()

        if (this.MAGIC != StaticLibraryParser.IMAGE_ARCHIVE_START)
            throw Error("This is not a valid static library archive.")

        this.ParseAllMembers()
    }


    IMAGE_ARCHIVE_MEMBER_HEADER(offset) {
        return {
            Name:        Trim(StrGet(this.ptr.Ptr + offset + 0,  16, "UTF-8"), " `n`r"),
            Date:        Trim(StrGet(this.ptr.Ptr + offset + 16, 12, "UTF-8"), " `n`r"),
            UserID:      Trim(StrGet(this.ptr.Ptr + offset + 28, 6,  "UTF-8"), " `n`r"),
            GroupID:     Trim(StrGet(this.ptr.Ptr + offset + 34, 6,  "UTF-8"), " `n`r"),
            Mode:        Trim(StrGet(this.ptr.Ptr + offset + 40, 8,  "UTF-8"), " `n`r"),
            Size:        Integer(Trim(StrGet(this.ptr.Ptr + offset + 48, 10, "UTF-8"), " `n`r")),
            EndOfHeader: Trim(StrGet(this.ptr.Ptr + offset + 58, 2,  "UTF-8"), " `n`r")
        }
    }


    ; First Linker Member (имя "/") – таблица символов и смещений -> https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#first-linker-member
    ParseFirstLinkerMember(offset) {
        NumberOfSymbols     := this.SwapEndian(NumGet(this.ptr, offset, "UInt"))
        currentStringOffset := offset + 4 + (NumberOfSymbols * 4)

        Loop NumberOfSymbols {
            Offsets := this.SwapEndian(NumGet(this.ptr, offset + 4 + ((A_Index - 1) * 4), "UInt"))
            StringTable := StrGet(this.ptr.Ptr + currentStringOffset, "CP0")
            this.firstSymbolMap[StringTable] := Offsets
            currentStringOffset += StrLen(StringTable) + 1
        }
    }


    ; Second Linker Member (имя "/" + A_index == 2) – таблица символов и смещений №2 -> https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#second-linker-member
    ParseSecondLinkerMember(offset) {
        offsetsArray := []
        indicesArray := []

        NumberOfMembers := NumGet(this.ptr, offset, "UInt")  ; NumberOfMembers (Little-Endian)
        offset += 4
        Loop NumberOfMembers {
            offsetsArray.Push(NumGet(this.ptr, offset, "UInt")) ; массив смещений (Offsets)
            offset += 4
        }

        NumberOfSymbols := NumGet(this.ptr, offset, "UInt") ; NumberOfSymbols (Little-Endian)
        offset += 4
        Loop NumberOfSymbols {
            indicesArray.Push(NumGet(this.ptr, offset, "UShort")) ; массив индексов (Indices). Они привязывают символ к файлу из offsetsArray.
            offset += 2
        }

        Loop NumberOfSymbols { ; StringTable (имена символов)
            symName := StrGet(this.ptr.Ptr + offset, "CP0")
            objOffset := offsetsArray[indicesArray[A_Index]] ; Индексы начинаются с 1 (а не с 0).
            this.secondSymbolMap[symName] := objOffset
            offset += StrLen(symName) + 1 ; offset == длина строки + 1 (null-терминатор)
        }
    }


    ; В ar архивах если имя символа больше 16 байт то hdr.Name будут храниться отдельно -> https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#longnames-member
    ParseLongnamesMember(offset) {
        this.longnamesOffset := offset
        ; end := offset + size
        ; longNamesStr := ""
        ; while (offset < end) {
        ;     str := StrGet(this.ptr.Ptr + offset, "CP0")
        ;     longNamesStr .= str
        ;     offset += StrLen(str) + 1
        ; }
        ; this.longNames := StrSplit(longNamesStr, "/")
    }


    ResolveName(rawName) {
        if (rawName == "" || rawName == "/" || rawName == "//")
            return rawName

        if (SubStr(rawName, 1, 1) == "/") { ; Если имя начинается со слэша + цифра (например "/15") - это длинное имя
            nameOffset := Integer(SubStr(rawName, 2))
            absOffset  := this.longnamesOffset + nameOffset
            realName   := ""
            while (true) {
                ; По какой то причине .a и .lib отличаються друг от друга в плане завершающего строку символа, и об этом не написанно в документации microsoft.
                ; Как я понял есть три вариации нуль-терминатора - это классика (0x00 - MSVC), и перенос строки (GNU) или слэш (GNU-терминатор перед \n).
                b := NumGet(this.ptr, absOffset + A_Index - 1, "UChar")
                if (b == 0 || b == 10 || b == 47) ; NUL | LF | /
                    break
                realName .= Chr(b)
            }
            return realName

        } else if (SubStr(rawName, -1) == "/") { ; Если имя заканчивается на слэш (например "main.obj/") - это короткое имя
            return SubStr(rawName, 1, StrLen(rawName) - 1)
        } else { ; Все остальное как есть
            return Trim(rawName)
        }
    }


    ParseAllMembers() {
        offset            := 8 ; данные идут сразу за сигнатурой "!<arch>`n"
        linkerMemberCount := 0
        while (offset < this.size) { ; ДОДЕЛАТЬ: У архивов ar есть подархивы (вложенные) - по хорошему, их тоже нужно достовать рекурсивно, хотя я без понятия зачем нужен архив в архиве, мда.
            hdr        := this.IMAGE_ARCHIVE_MEMBER_HEADER(offset)
            dataOffset := offset + StaticLibraryParser.SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER

            if (hdr.Name == "/") {
                linkerMemberCount++
                if (linkerMemberCount == 1) { ; ДОДЕЛАТЬ: Нужно выбирапть между FirstLinkerMember и SecondLinkerMember, а не парсить оба варинанта, ибо SecondLinkerMember парсится быстрее, но при этом он есть тольо у .lib.
                    this.ParseFirstLinkerMember(dataOffset)
                } else if (linkerMemberCount == 2) {
                    this.ParseSecondLinkerMember(dataOffset)
                }
            } else if (hdr.Name == "//") {
                this.ParseLongnamesMember(dataOffset)
            } else {
                this.Members.Push({ ; ДОДЕЛАТЬ: Нужно структурировать данные под линковщик, что бы бьло проще с ними работать.
                    Name: this.ResolveName(hdr.Name),
                    DataOffset: dataOffset,
                    Size: hdr.Size
                })
            }

            ; смещение следующего файла с учетом выравнивания
            next := dataOffset + hdr.Size
            if (hdr.Size & 1) ; Если нечетный размер, добавляется 1 байт
                next += 1
            offset := next
        }
    }

    SwapEndian(n) => ((n & 0xFF) << 24) | ((n & 0xFF00) << 8) | ((n >> 8) & 0xFF00) | ((n >> 24) & 0xFF) ; Big-Endian -> Little-Endian
}

; parser := StaticLibraryParser("D:\GCC_tdm64-gcc-9.2.0\lib\libctf.a")
; parser := StaticLibraryParser("D:\Visual Studio\VC\Tools\MSVC\14.43.34808\lib\x64\clang_rt.stats_client-x86_64.lib")
; parser := StaticLibraryParser("D:\GCC_tdm64-gcc-9.2.0\lib\gcc\x86_64-w64-mingw32\10.3.0\libssp.a")
; dbg parser.firstSymbolMap, parser.Members
; GetObjectByName(parser, "ssp.o")



GetObjectByName(lib, name) {
    for member in lib.Members {
        if (member.Name == name) {
            buf := Buffer(member.Size)
            DllCall("RtlMoveMemory", "Ptr", buf.Ptr, "Ptr", lib.ptr.Ptr + member.DataOffset, "UPtr", member.Size)
            f := FileOpen(GLOBAL_WORKING_DIR "\temp.o", "rw")
            f.RawWrite(buf)
            f.Close()
        }
    }
}



; Не используется...
class PEImports {
    static IMAGE_DOS_SIGNATURE           := 0x5A4D
    static IMAGE_NT_SIGNATURE            := 0x00004550
    static IMAGE_NT_OPTIONAL_HDR64_MAGIC := 0x20B
    static IMAGE_NT_OPTIONAL_HDR32_MAGIC := 0x10B
    static SIZEOF_IMAGE_DATA_DIRECTORY   := 8   ; RVA (4) + Size (4)
    static OFFSET_TO_OPTIONAL_HEADER     := 24  ; после Signature + FileHeader

    static SIZEOF_IMAGE_SECTION_HEADER    := 40
    static SIZEOF_IMAGE_IMPORT_DESCRIPTOR := 20

    E_MAGIC  => this.IMAGE_DOS_HEADER(0).e_magic
    E_LFANEW => this.IMAGE_DOS_HEADER(0).e_lfanew

    NUMBER_OF_SECTIONS      => this.IMAGE_NT_HEADERS(this.E_LFANEW).NumberOfSections
    SIZE_OF_OPTIONAL_HEADER => this.IMAGE_NT_HEADERS(this.E_LFANEW).SizeOfOptionalHeader
    MAGIC                   => this.IMAGE_NT_HEADERS(this.E_LFANEW).Magic


    __New(path) {
        this.sections := []
        this.imports  := []
        this.file     := FileOpen(path, "r")
        this.size     := this.file.Length
        this.ptr      := Buffer(this.size)
        this.file.RawRead(this.ptr)
        this.file.Close()

        if (this.E_MAGIC != PEImports.IMAGE_DOS_SIGNATURE)
            throw Error("Not a valid DOS file (MZ signature missing)...")

        if (NumGet(this.ptr, this.E_LFANEW, "UInt") != PEImports.IMAGE_NT_SIGNATURE)
            throw Error("Not a valid PE file (PE signature missing)...")

        this.is64           := this.Magic == PEImports.IMAGE_NT_OPTIONAL_HDR64_MAGIC
        dataDirectoryOffset := this.E_LFANEW + PEImports.OFFSET_TO_OPTIONAL_HEADER + (this.is64 ? 112 : 96) + PEImports.SIZEOF_IMAGE_DATA_DIRECTORY
        this.ImportRVA      := NumGet(this.ptr, dataDirectoryOffset, "UInt") ; IMAGE_DATA_DIRECTORY : VirtualAddress

        this.ReadSections()
        this.ReadImports()
    }


    IMAGE_DOS_HEADER(offset) {
        ; https://docs.rs/pelite/latest/pelite/image/struct.IMAGE_DOS_HEADER.html
        return {
            e_magic: NumGet(this.ptr, offset + 0, "UShort"),
            ;...
            e_lfanew: NumGet(this.ptr, offset + 60, "UInt"),
        }
    }


    IMAGE_NT_HEADERS(offset) { ; IMAGE_NT_HEADERS64 || IMAGE_NT_HEADERS32
        ; https://docs.rs/pelite/latest/pelite/pe32/image/type.IMAGE_NT_HEADERS.html
        return {
            ;Signature:           NumGet(this.ptr, offset + 0,  "UInt")
            ;Machine:             NumGet(this.ptr, offset + 4,  "UShort"),
            NumberOfSections:     NumGet(this.ptr, offset + 6,  "UShort"),
            SizeOfOptionalHeader: NumGet(this.ptr, offset + 20, "UShort"),
            Magic:                NumGet(this.ptr, offset + 24, "UShort"),
            ;...
        }
    }


    IMAGE_SECTION_HEADER(offset) {
        return {
            ;Name:                Name,
            VirtualSize:          NumGet(this.ptr, offset + 8,  "UInt"), ; PhysicalAddress / VirtualSize
            VirtualAddress:       NumGet(this.ptr, offset + 12, "UInt"),
            SizeOfRawData:        NumGet(this.ptr, offset + 16, "UInt"),
            PointerToRawData:     NumGet(this.ptr, offset + 20, "UInt"),
            ;...
        }
    }



    IMAGE_IMPORT_DESCRIPTOR(offset) {
        return {
            OriginalFirstThunk: NumGet(this.ptr, offset + 0,  "UInt"),
            TimeDateStamp:      NumGet(this.ptr, offset + 4,  "UInt"),
            ForwarderChain:     NumGet(this.ptr, offset + 8,  "UInt"),
            NameRVA:            NumGet(this.ptr, offset + 12, "UInt"), ; Name / NameRVA
            FirstThunk:         NumGet(this.ptr, offset + 16, "UInt"),
        }
    }


    ; Перевод адреса из памяти (RVA) в физическое смещение в файле
    RvaToOffset(rva) {
        if (rva == 0)
            return 0
            
        for sec in this.sections {
            if (rva >= sec.VirtualAddress && rva < sec.VirtualAddress + sec.VirtualSize) { ; Если RVA попадает в диапазон этой секции
                return rva - sec.VirtualAddress + sec.PointerToRawData
            }
        }
        return 0
    }


    ReadSections() {
        sectionOffset := this.e_lfanew + 24 + this.SIZE_OF_OPTIONAL_HEADER ; Секции начинаются сразу после Optional Header
        loop this.NUMBER_OF_SECTIONS {
            this.sections.Push(this.IMAGE_SECTION_HEADER(sectionOffset))
            sectionOffset += PEImports.SIZEOF_IMAGE_SECTION_HEADER
        }
    }


    ReadImports() {
        if (this.ImportRVA == 0)
            return []
        importOffset := this.RvaToOffset(this.ImportRVA)

        while (true) {
            functions := []
            importDesc := this.IMAGE_IMPORT_DESCRIPTOR(importOffset)

            if (importDesc.OriginalFirstThunk == 0 && importDesc.NameRVA == 0 && importDesc.FirstThunk == 0) ; Массив заканчивается нулевой структурой
                break

            dllName := StrGet(this.ptr.Ptr + this.RvaToOffset(importDesc.NameRVA), "UTF-8") ; Имя DLL

            ; Некоторые компиляторы не заполняют OriginalFirstThunk, по крайней мере так написано в интернете - в таком случае нужно читать из FirstThunk
            thunkOffset := this.RvaToOffset(importDesc.OriginalFirstThunk ? importDesc.OriginalFirstThunk : importDesc.FirstThunk)

            ; Идем по массиву Thunk Data (4 байта для 32 / 8 байт для 64)
            while (true) {
                thunkValue := this.is64 ? NumGet(this.ptr, thunkOffset, "UInt64") : NumGet(this.ptr, thunkOffset, "UInt")
                if (thunkValue == 0)
                    break

                if ((thunkValue >> (this.is64 ? 63 : 31)) & 1) { ; isOrdinal... Импортируется ли функция по Ординалу или по Имени (самый старший бит = 1)
                    ; functions.Push("Ordinal: " ordinalNum)
                    functions.Push(thunkValue & 0xFFFF) ; ordinalNum... Если функция импортируется без имени, только по номеру
                } else {
                    ; Если по имени, RVA указывает на структуру IMAGE_IMPORT_BY_NAME. Первые 2 байта это Hint (не надо) далее идет имя строки...
                    funcNameRVA := thunkValue & 0x7FFFFFFF
                    funcNameOffset := this.RvaToOffset(funcNameRVA) + 2
                    funcName := StrGet(this.ptr.Ptr + funcNameOffset, "UTF-8")
                    functions.Push(funcName)
                }
                thunkOffset += this.is64 ? 8 : 4
            }
            this.imports.Push({dll: dllName, functions: functions})
            importOffset += PEImports.SIZEOF_IMAGE_IMPORT_DESCRIPTOR
        }
    }
}


/**
 * - Я без понятия как получать именна dll, кроме как собрать exe с пустой main и прочитать все импорты...
 * - Вроде бы это работает неплохо, но нужно тестить...
 * |user32:MessageBoxA:2
 * UPD:: Идея нуждается в доработке. Возможно этот код будет удален как и PEImports
 */
GetIAT(objPath, pePath) {
    IAT := [], STR := "|"
    exports := COFF(objPath).export
    imports := PEImports(pePath).imports
    ;dbg exports, imports
    for exp in exports {
        for imp in imports {
            for func in imp.functions {
                if (exp.func == func) {
                    IAT.Push({dll: imp.dll, func: exp.func, reloc: exp.reloc})
                }
            }
        }
    }

    loop (IAT.Length) {
        STR .= StrReplace(IAT[A_Index].dll, ".dll") ":" IAT[A_Index].func ":" IAT[A_Index].reloc "|"
    }

    return {arr: IAT, str: RTrim(STR, "|")}
}
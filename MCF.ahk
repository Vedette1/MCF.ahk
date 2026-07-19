#Requires AutoHotkey v2.0
#SingleInstance Force
#Include const.ahk
#Include Static_Library_Viewer.ahk

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

; Мне лень это делать...
Locale := Map(
    "layout_analysis",   Map("ru", "[Layout] Анализ и объединение секций:`n", "en", "[Layout] Analyzing and merging sections:`n"),
    "layout_ignore",     Map("ru", "`t[Игнор] Секция '{1}' пропущена.`n", "en", "`t[Ignore] Section '{1}' skipped.`n"),
    "layout_ok",         Map("ru", "`t[ОК] Секция '{1}' объединена. Новое смещение: {2}, Размер: {3}`n", "en", "`t[OK] Section '{1}' merged. New offset: {2}, Size: {3}`n"),
    
    "err_no_code",       Map("ru", "Не найдено исполняемого кода или данных.", "en", "No executable code or data found."),
    
    "reloc_processing",  Map("ru", "`n[Relocations] Обработка релокаций и патчинг:`n", "en", "`n[Relocations] Processing relocations and patching:`n"),
    "reloc_import",      Map("ru", "`t[Импорт] Найден символ из DLL: '{1}' (патч по смещению {2})`n", "en", "`t[Import] Found DLL symbol: '{1}' (patched at offset {2})`n"),
    "reloc_static",      Map("ru", "`t[Статика] Найден неразрешенный символ: '{1}' (требует статической линковки)`n", "en", "`t[Static] Found unresolved symbol: '{1}' (requires static linking)`n"),
    
    "err_target_sec",    Map("ru", "targetSectionNewOffset == -1`nЭта ошибка обычно возникает из-за того, что вы игнорируете определенную секцию. Удалите все секции из [ignoreSections | Игнорировать секции:] и попробуйте собрать Mcode заново.", 
                             "en", "targetSectionNewOffset == -1`nThis error most likely occurs because you're ignoring a specific section. Remove all sections from [ignoreSections | Ignore Sections:] and try building Mcode again."),
    
    "iat_init",          Map("ru", "`n[IAT] Формирование таблицы импортов (IAT):`n", "en", "`n[IAT] Generating Import Address Table (IAT):`n"),
    "iat_dll_loaded",    Map("ru", "`tЗагружена DLL: {1}`n", "en", "`tLoaded DLL: {1}`n"),
    "iat_dll_fail",      Map("ru", "`t[Внимание] Не удалось загрузить DLL: {1}`n", "en", "`t[Warning] Failed to load DLL: {1}`n"),
    "iat_sym_found",     Map("ru", "`t[ОК] Символ '{1}' найден в {2}. Добавлен в IAT.`n", "en", "`t[OK] Symbol '{1}' found in {2}. Added to IAT.`n"),
    "iat_sym_skip",      Map("ru", "`t[Пропуск] Символ '{1}' не найден в загруженных DLL (UNKNOWN_DLL). В IAT не записывается.`n", "en", "`t[Skip] Symbol '{1}' not found in loaded DLLs (UNKNOWN_DLL). Skipped in IAT.`n"),
    
    "iat_dyn_imp",       Map("ru", "`n[IAT] Обработка динамических импортов (__imp_):`n", "en", "`n[IAT] Processing dynamic imports (__imp_):`n"),
    "short_no_imports",  Map("ru", "Не найдены импорты [DLL]:`n", "en", "Not found imports [DLL]:`n"),
    "short_sym_info",    Map("ru", "`tсимвол: '{1}' -> смещение: {2} -> тип релокации {3}`n", "en", "`tsymbol: '{1}' -> offset: {2} -> reloc type {3}`n"),
    
    "iat_unresolved",    Map("ru", "`n[IAT] Обработка неразрешенных символов (статика):`n", "en", "`n[IAT] Processing unresolved symbols (static):`n"),
    "dyn_mode_true",     Map("ru", "`tРежим dynamicLinking = true. Попытка связать все неразрешенные символы динамически.`n", "en", "`tMode dynamicLinking = true. Attempting to link all unresolved symbols dynamically.`n"),
    "dyn_mode_arr",      Map("ru", "`tРежим dynamicLinking = Array. Проверка конкретных символов для динамической линковки.`n", "en", "`tMode dynamicLinking = Array. Checking specific symbols for dynamic linking.`n"),
    "dyn_mode_false",    Map("ru", "`tРежим dynamicLinking = false. Неразрешенные символы игнорируются.`n", "en", "`tMode dynamicLinking = false. Unresolved symbols are ignored.`n"),
    
    "short_static_unres",Map("ru", "Неразрешенные статические символы не найдены`n", "en", "Unresolved symbols not found (static)`n"),
    "sym_can_be_dyn",    Map("ru", " // [Поддерживает динамическую линковку]`n", "en", " // [Supports dynamic linking]`n"),
    "sym_cannot_be_dyn", Map("ru", " // [Динамическая линковка невозможна]`n", "en", " // [Dynamic linking impossible]`n"),
    
    "va_adding",         Map("ru", "`n[IAT] Добавление VA-релокаций:`n", "en", "`n[IAT] Adding VA relocations:`n"),
    "va_added",          Map("ru", "`tДобавлена VA-релокация (размер: {1}, смещение: {2})`n", "en", "`tAdded VA relocation (size: {1}, offset: {2})`n"),
    
    "linker_done",       Map("ru", "`n[Linker] Процесс линковки завершен ", "en", "`n[Linker] Linking process completed "),
    "linker_success",    Map("ru", "успешно, скорее всего ошибок нет!`n", "en", "successfully, most likely no errors!`n"),
    "linker_failed",     Map("ru", "с ошибками. Потенциальные проблемы смотрите в основном GUI...`n", "en", "with errors. Check main GUI for potential issues...`n")
)


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
     */
    __New(path, importDll := ["User32", "msvcrt", "Kernel32"], ignoreSections := [".pdata", ".xdata", ".rdata$zzz"], fullOffsetTable := true, entryPoint := 0x0, dynamicLinking := true, logLang := "en") {
        this.path            := path            ; Путь до COFF (.o / .obj) файла.
        this.importDll       := importDll       ; Массив dll которые используются в конечном Mcode (если есть внешнии символы).
        this.ignoreSections  := ignoreSections  ; Массив секций, которые будут игнорироватся при линковке (в основном сюда ничего не нужно дописывать).
        this.fullOffsetTable := fullOffsetTable ; Если fullOffsetTable == false, то линковщик вернет смещения только нужных символов (функции / глобалки*), в ином случае будет полная таблица всех символов.
        this.entryPoint      := entryPoint      ; Точка входа.
        this.dynamicLinking  := dynamicLinking  ; Управление динамической линковкой: false, true или массив конкретных функций.
        this.logLang         := logLang         ; Язык лога (RU || EN)
        this.dbgLogInfo      := ""

        this.imports           := []  ; Массив объектов импортируемых символов из dll (__imp_).
        this.unresolvedSymbols := []  ; Массив объектов неразрешённых символов (статическая линковка).

        this.exportedSymbols := Map() ; Таблица смещений всех функций / секций / глобальных переменных, и тд. которые есть в конечном Mcode.
        this.VAreloc         := []    ; Массив VA релокаций - VirtualAlloc + RVA (известно только при запуске). В 99% случаев VA релокаций не будет в конечном Mcode.
        this.sectionFilter   := []    ; Массив 0 && 1. Фильтрует бесполезные секции при линковке, что бы не захватывать их в конечный Mcode (например это .xdata | .pdata).
        this.alignment       := []    ; Массив выравнивания данных по границе в X байт. Для производительности нужно учитывать выравнивание байт при объединение секций.
        this.headerCharact   := Map() ; Все константы характеристик [key == Idx sec, value == const flags]. Это dbg info.
        ; this.export          := []    ; Массив объектов - содержит релокации + функции (без секций), а так же sectionIndex + patchOffset.
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
            if (nextSymbol.StorageClass == COFF.IMAGE_SYMBOL_STORAGE_CLASS.Get("IMAGE_SYM_CLASS_FILE")) {
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
                case IMAGE_REL_AMD64_ADDR32   : NumPut("UInt",  targetAddress, mcode, patchAddress),  this.VAreloc.Push({offset: patchAddress, size: 4})
                case IMAGE_REL_AMD64_ADDR32NB : NumPut("UInt",  targetAddress, mcode, patchAddress)
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
                case IMAGE_REL_I386_DIR32   : NumPut("UInt", targetAddress, mcode, patchAddress), this.VAreloc.Push({offset: patchAddress, size: 4})
                case IMAGE_REL_I386_DIR32NB : NumPut("UInt", targetAddress, mcode, patchAddress)
                case IMAGE_REL_I386_REL32   : NumPut("Int",  targetAddress + NumGet(mcode, patchAddress, "Int") - (patchAddress + 4), mcode, patchAddress)
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

        this.dbgLogInfo := "[Layout] Analyzing and merging sections:`n"
        for i, sec in this.sections {
            if (this.sectionFilter[i]) {
                this.dbgLogInfo .= "`t[Ignore] Section '" sec.Name "' skipped.`n"
                continue
            }

            currentOffset := (currentOffset + this.alignment[i] - 1) & ~(this.alignment[i] - 1) ; Выравнивание
            layout.Push({Section: sec, OriginalIndex: i, NewOffset: currentOffset})
            this.dbgLogInfo .= "`t[OK] Section '" sec.Name "' merged. New offset: 0x" Format("{:X}", currentOffset) ", Size: " Max(sec.SizeOfRawData, sec.VirtualSize) "`n"
            currentOffset += Max(sec.SizeOfRawData, sec.VirtualSize)
        }

        totalSize := currentOffset
        if (totalSize == 0) {
            throw Error("No executable code or data found.")
        }
            
        mcode := Buffer(totalSize, 0)
        COFF.EntryPoint(this.entryPoint + (this.entryPoint == 0 ? 0 : this.alignment[1]), mcode)
        for item in layout {
            if (item.Section.PointerToRawData > 0 && Max(item.Section.SizeOfRawData, item.Section.VirtualSize) > 0) {
                DllCall("RtlMoveMemory", "Ptr", mcode.Ptr + item.NewOffset, "Ptr", this.ptr.Ptr + item.Section.PointerToRawData, "UPtr", item.Section.SizeOfRawData)
            }
        }

        this.dbgLogInfo .= "`n[Relocations] Processing relocations and patching:`n"
        for item in layout { ; релокации (патчинг адресов)
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

                ; Внешние символы
                if (this.symbolsMap.Has(symbolIndex) && this.symbolsMap[symbolIndex].StorageClass == 2 && !this.symbolsMap[symbolIndex].SectionIndex) {
                    funcName := this.symbolsMap[symbolIndex].Name
                    if (funcName ~= "^__imp_") {
                        funcName := SubStr(funcName, 7)
                        this.imports.Push({func: funcName, type: reloc.Type, sectionIndex: item.OriginalIndex, patchOffset: item.NewOffset + reloc.VirtualAddress})
                        this.dbgLogInfo .= "`t[Import] Found DLL symbol: '" funcName "' (patched at offset 0x" Format("{:X}", item.NewOffset + reloc.VirtualAddress) ")`n"
                    } else {
                        this.unresolvedSymbols.Push({func: funcName, type: reloc.Type, sectionIndex: item.OriginalIndex, patchOffset: item.NewOffset + reloc.VirtualAddress})
                        this.dbgLogInfo .= "`t[Static] Found unresolved symbol: '" funcName "' (requires static linking)`n"
                    }
                    continue
                }

                if (targetSectionNewOffset == -1) {
                    throw Error("targetSectionNewOffset == -1`n This error most likely occurs because you're ignoring a specific section. Remove all sections from [ignoreSections | Ignore Sections:] and try building Mcode again.")
                }

                targetAddress := targetSectionNewOffset + symbol.Value               ; реальный адрес, куда указывает символ в новом буфере.
                patchAddress  := item.NewOffset + reloc.VirtualAddress               ; адрес самой инструкции, которую нужно пропатчить
                this.ApplyRelocation(mcode, targetAddress, patchAddress, reloc.Type) ; патчинг релокаций внутренних символов
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

        ; Вспомогательная функция для поиска и добавления в IAT
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


        if (this.imports.Length) { ; 1. Обработка обычных импортов (__imp_)
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

        if (this.unresolvedSymbols.Length) { ; 2. Обработка неразрешенных символов в зависимости от dynamicLinking
            this.dbgLogInfo .= "`n[IAT] Processing unresolved symbols (static):`n"
            if (this.dynamicLinking == true) {
                this.dbgLogInfo .= "`tdynamicLinking = true. Attempting to link all unresolved symbols dynamically.`n"
                for exp in this.unresolvedSymbols {
                    if !(ResolveAndAdd(exp)) {
                        unresolvedSymbolsNew.Push(exp)
                    }
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
            this.unresolvedSymbols := unresolvedSymbolsNew ; Просто перезаписываем массив на будущие, когда я начну делать статическую линковку (её поддержку)

            if (this.unresolvedSymbols.Length) {
                shortDbgInfo .= "Unresolved symbols not found (static)`n"
                for exp in this.unresolvedSymbols {
                    shortDbgInfo .= "`tsymbol: '" exp.func "' -> offset: " Format("0x{:X}", exp.patchOffset) " -> reloc type " Format("0x{:X}", exp.type) . (ResolveAndAdd(exp, false) ? " // It can be made dynamic`n" : " // This cannot be made dynamic.`n")
                }
            }
        }

        ; VA-релокации (если они есть) размещаются в тот же IAT-хвост, но с префиксом "VA"
        if (this.VAreloc.Length) {
            this.dbgLogInfo .= "`n[IAT] Adding VA relocations:`n"
            for va in this.VAreloc {
                IAT .= "VA:" va.size ":" va.offset "|"
                this.dbgLogInfo .= "`tAdded VA relocation (size: " va.size ", offset: 0x" Format("{:X}", va.offset) ")`n"
            }
        }

        ;============================================ таблица символов ============================================
        ; this.dbgLogInfo .= "`n[Table] Формирование таблицы экспортируемых символов:`n"
        for i, symbol in this.symbolsMap {
            if (symbol.SectionIndex > 0 && (symbol.StorageClass == 2) || this.fullOffsetTable) {
                secOffset := -1
                for item in layout {
                    if (item.OriginalIndex == symbol.SectionIndex) {
                        secOffset := item.NewOffset
                        break
                    }
                }
                
                if (secOffset != -1) {
                    this.exportedSymbols[i] := {symbol: symbol.Name, offset: Format("0x{:X}", secOffset + symbol.Value), opt: symbol.StorageClass != 2 ? " [dispensable]" : ""}
                }
            }
        }

        ;============================================ конечный Mcode + таблица ============================================
        exportedSymbolsStr := "offset := Map()`n"
        for value, symbol in this.exportedSymbols {
            exportedSymbolsStr .= "offset[" Chr(34) symbol.symbol Chr(34) "] := " symbol.offset " `; " value symbol.opt "`n"
        }
        
        this.dbgLogInfo .= "`n[Linker] Linking process completed " . (shortDbgInfo == "" ? "successfully, most likely no errors!`n" : "with errors. Check main GUI for potential issues...`n")
        ; this.dbgLogInfo .= "[Linker] Возможные проблемы:`n`n" . shortDbgInfo

        return {
            hex:      Binary.BinaryToStrin(mcode, mcode.Size, 12)           . RTrim(IAT, "|"),
            base64:   Binary.BinaryToStrin(mcode, mcode.Size, 1)            . RTrim(IAT, "|"),
            compress: Binary.BinaryToCompressedBase64(mcode, mcode.Size, 2) . RTrim(IAT, "|"),
            table:    RTrim(exportedSymbolsStr, "`n"),
            dbg:      {ALL: this.dbgLogInfo, short: shortDbgInfo}
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
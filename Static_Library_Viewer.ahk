#Requires AutoHotkey v2.0
#SingleInstance Force

class StaticLibraryParser {
    static IMAGE_ARCHIVE_START := "!<arch>`n"
    static THIN_ARCHIVE_START  := "!<thin>`n" ; Thin archives — это фича экосистемы GNU (GCC, ar) и LLVM (Clang).
    static SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER := 60

    MAGIC => StrGet(this.ptr.Ptr, 8, "UTF-8")

    __New(lib) {
        this.firsrOrsecondSymbolMap := MultiMap() ; Имя символа -> смещение
        this.Members                := []         ; [{Name: "file.o", DataOffset: ..., Size: ...}, ...]
        this.MembersByOffset        := Map()      ; Смещение заголовка -> Данные obj файла
        this.ResolvedSymbols        := MultiMap() ; Итоговый результат
        this.ThinMembers            := []         ; [{Name, Path, HeaderOffset, Size}, ...]
        this.longnamesOffset        := 0

        if (lib is String) {
            if (FileExist(lib)) {
                if InStr(FileExist(lib), "D")
                    throw Error("Path is a directory, not a file: " lib)
                this.file := FileOpen(lib, "r")
                this.size := this.file.Length
                this.ptr  := Buffer(this.size)
                this.file.RawRead(this.ptr)
                this.file.Close()
                SplitPath(lib, , &dir)
                this.ArchiveDir := dir
            } else throw Error("Invalid Path: " lib)
        } else if (HasProp(lib, "Ptr") && HasProp(lib, "Size")) {
            this.size := lib.Size
            this.ptr  := {Ptr: lib.Ptr, Size: lib.Size}
            this.ArchiveDir := (HasProp(lib, "ArchiveDir")) ? lib.ArchiveDir : ""
        } else throw Error("Invalid library input type.")

        if (this.MAGIC != StaticLibraryParser.IMAGE_ARCHIVE_START && this.MAGIC != StaticLibraryParser.THIN_ARCHIVE_START)
            throw Error("This is not a valid static library archive.")

        this.IsThin := (this.MAGIC == StaticLibraryParser.THIN_ARCHIVE_START)
        this.ParseAllMembers()
        this.FinalResolvedSymbols()
    }


    IMAGE_ARCHIVE_MEMBER_HEADER(offset) {
        sizeStr := Trim(StrGet(this.ptr.Ptr + offset + 48, 10, "CP0"), " `n`r")
        return {
            Name:        Trim(StrGet(this.ptr.Ptr + offset + 0,  16, "CP0"), " `n`r"),
            Date:        Trim(StrGet(this.ptr.Ptr + offset + 16, 12, "CP0"), " `n`r"),
            UserID:      Trim(StrGet(this.ptr.Ptr + offset + 28, 6,  "CP0"), " `n`r"),
            GroupID:     Trim(StrGet(this.ptr.Ptr + offset + 34, 6,  "CP0"), " `n`r"),
            Mode:        Trim(StrGet(this.ptr.Ptr + offset + 40, 8,  "CP0"), " `n`r"),
            Size:        (sizeStr == "") ? 0 : Integer(sizeStr),
            EndOfHeader: Trim(StrGet(this.ptr.Ptr + offset + 58, 2,  "CP0"), " `n`r")
        }
    }


    ResolveThinPath(name) {
        if (this.ArchiveDir == "" || RegExMatch(name, "^([A-Za-z]:[\\/]|[\\/])"))
            return StrReplace(name, "/", "\")
        
        fullPath := this.ArchiveDir "\" name
        return StrReplace(fullPath, "/", "\")
    }


    ParseFirstLinkerMember(offset) {
        NumberOfSymbols     := this.SwapEndian(NumGet(this.ptr.Ptr, offset, "UInt"))
        currentStringOffset := offset + 4 + (NumberOfSymbols * 4)

        Loop NumberOfSymbols {
            Offsets := this.SwapEndian(NumGet(this.ptr.Ptr, offset + 4 + ((A_Index - 1) * 4), "UInt"))
            StringTable := StrGet(this.ptr.Ptr + currentStringOffset, "CP0")
            this.firsrOrsecondSymbolMap[StringTable] := Offsets
            currentStringOffset += StrLen(StringTable) + 1
        }
    }


    ParseSecondLinkerMember(offset) {
        offsetsArray := []
        indicesArray := []

        NumberOfMembers := NumGet(this.ptr.Ptr, offset, "UInt")
        offset += 4
        Loop NumberOfMembers {
            offsetsArray.Push(NumGet(this.ptr.Ptr, offset, "UInt"))
            offset += 4
        }

        NumberOfSymbols := NumGet(this.ptr.Ptr, offset, "UInt")
        offset += 4
        Loop NumberOfSymbols {
            indicesArray.Push(NumGet(this.ptr.Ptr, offset, "UShort"))
            offset += 2
        }

        Loop NumberOfSymbols {
            symName := StrGet(this.ptr.Ptr + offset, "CP0")
            objOffset := offsetsArray[indicesArray[A_Index]]
            this.firsrOrsecondSymbolMap[symName] := objOffset
            offset += StrLen(symName) + 1
        }
    }

    ; Парсинг 64-битной таблицы символов GNU (/SYM64/)
    ParseSym64LinkerMember(offset) {
        offsetsArray := []
        indicesArray := []

        NumberOfMembers := NumGet(this.ptr.Ptr, offset, "UInt64")
        offset += 8
        Loop NumberOfMembers {
            offsetsArray.Push(NumGet(this.ptr.Ptr, offset, "UInt64"))
            offset += 8
        }

        NumberOfSymbols := NumGet(this.ptr.Ptr, offset, "UInt64")
        offset += 8
        Loop NumberOfSymbols {
            indicesArray.Push(NumGet(this.ptr.Ptr, offset, "UShort"))
            offset += 2
        }

        Loop NumberOfSymbols {
            symName := StrGet(this.ptr.Ptr + offset, "CP0")
            objOffset := offsetsArray[indicesArray[A_Index]]
            this.firsrOrsecondSymbolMap[symName] := objOffset
            offset += StrLen(symName) + 1
        }
    }


    ParseLongnamesMember(offset) {
        this.longnamesOffset := offset
    }


    ResolveName(rawName) {
        if (rawName == "" || rawName == "/" || rawName == "//" || rawName == "/SYM64/")
            return rawName

        ; Обработка длинных имен GNU (начинаются с / и цифр)
        if (SubStr(rawName, 1, 1) == "/") {
            numPart := SubStr(rawName, 2)
            if !IsInteger(numPart)
                return rawName ; Если после слэша не цифры

            nameOffset := Integer(numPart)
            absOffset  := this.longnamesOffset + nameOffset
            
            ; Ищем фактическую длину строки до символа '/' или '\n'
            endOffset := absOffset
            while (endOffset < this.size) {
                char := NumGet(this.ptr.Ptr, endOffset, "UChar")
                if (char == 10 || char == 47) ; 10 - `n, 47 - /
                    break
                endOffset++
            }
            
            nameLen := endOffset - absOffset
            if (nameLen <= 0)
                return ""
                
            realName := StrGet(this.ptr.Ptr + absOffset, nameLen, "CP0")
            return Trim(realName)

        ; Обработка коротких имен GNU (заканчиваются на /)
        } else if (SubStr(rawName, -1) == "/") {
            return SubStr(rawName, 1, StrLen(rawName) - 1)
        } else {
            return Trim(rawName)
        }
    }


    ParseAllMembers() {
        hasSecond         := this.HasSecondLinkerMember()
        offset            := 8
        linkerMemberCount := 0

        while (offset < this.size) {
            hdr        := this.IMAGE_ARCHIVE_MEMBER_HEADER(offset)
            dataOffset := offset + StaticLibraryParser.SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER

            if (hdr.Name == "/" || hdr.Name == "/SYM64/") {
                linkerMemberCount++
                
                if (hdr.Name == "/") {
                    if (linkerMemberCount == 1 && !hasSecond)
                        this.ParseFirstLinkerMember(dataOffset)
                    else if (linkerMemberCount == 2 && hasSecond)
                        this.ParseSecondLinkerMember(dataOffset)
                } else if (hdr.Name == "/SYM64/") {
                    this.ParseSym64LinkerMember(dataOffset)
                }
                
                offset := dataOffset + hdr.Size + (hdr.Size & 1)

            } else if (hdr.Name == "//") {
                this.ParseLongnamesMember(dataOffset)
                offset := dataOffset + hdr.Size + (hdr.Size & 1)

            } else if (this.IsThin) {
                resolvedName := this.ResolveName(hdr.Name)
                thinInfo := {Name: resolvedName, Path: this.ResolveThinPath(resolvedName), HeaderOffset: offset, Size: hdr.Size}
                this.ThinMembers.Push(thinInfo)
                this.MembersByOffset[offset] := {Name: resolvedName, Path: thinInfo.Path, Size: hdr.Size, IsThin: true}
                offset := dataOffset ; В Thin-архивах данных нет, сразу переходим к следующему заголовку

            } else {
                nestedParser := "", magic := ""
                if (hdr.Size >= 8)
                    magic := StrGet(this.ptr.Ptr + dataOffset, 8, "UTF-8")

                if (magic == StaticLibraryParser.IMAGE_ARCHIVE_START || magic == StaticLibraryParser.THIN_ARCHIVE_START) {
                    nestedParser := StaticLibraryParser({Ptr: this.ptr.Ptr + dataOffset, Size: hdr.Size, ArchiveDir: this.ArchiveDir})
                }

                memberInfo := {Name: this.ResolveName(hdr.Name), DataOffset: dataOffset, Size: hdr.Size, NestedParser: nestedParser}
                this.Members.Push(memberInfo)
                this.MembersByOffset[offset] := memberInfo

                offset := dataOffset + hdr.Size + (hdr.Size & 1)
            }
        }
        this.LinkSymbolsToObjects()
    }


    LinkSymbolsToObjects() {
        for symName, headerOffset in this.firsrOrsecondSymbolMap {
            if (this.MembersByOffset.Has(headerOffset)) {
                objInfo := this.MembersByOffset[headerOffset]
                this.ResolvedSymbols[symName] := {
                    ObjFile:    objInfo.Name,
                    DataOffset: objInfo.HasProp("DataOffset") ? objInfo.DataOffset : 0,
                    Size:       objInfo.Size,
                    IsThin:     objInfo.HasProp("IsThin") ? objInfo.IsThin : false,
                    Path:       objInfo.HasProp("Path") ? objInfo.Path : ""
                }
            } else {
                this.ResolvedSymbols[symName] := {ObjFile: "UNKNOWN", DataOffset: 0, Size: 0, IsThin: false, Path: ""}
            }
        }
    }


    FinalResolvedSymbols() {
        outMembers := [], outThin := [], outSymbols := MultiMap()
        this._CollectNested(this, outMembers, outThin, outSymbols)

        for m in outMembers
            this.Members.Push(m)
        for t in outThin
            this.ThinMembers.Push(t)
        for symName, objInfo in outSymbols
            this.ResolvedSymbols[symName] := objInfo
    }


    _CollectNested(parser, outMembers, outThin, outSymbols) {
        for mem in parser.Members {
            if (mem.NestedParser) {
                nested := mem.NestedParser
                for memberInfo in nested.Members
                    outMembers.Push(memberInfo)
                for tm in nested.ThinMembers
                    outThin.Push(tm)
                for symName, objInfo in nested.ResolvedSymbols
                    outSymbols[symName] := objInfo
                this._CollectNested(nested, outMembers, outThin, outSymbols)
            }
        }
    }


    HasSecondLinkerMember() {
        offset := 8
        linkerMemberCount := 0
        while (offset < this.size) {
            hdr := this.IMAGE_ARCHIVE_MEMBER_HEADER(offset)
            if (hdr.Name == "/" || hdr.Name == "/SYM64/") {
                linkerMemberCount++
                if (linkerMemberCount == 2) {
                    return true
                }
            }
            ; Тонкие архивы не имеют данных, кроме спец-членов (/ и //)
            if (this.IsThin && hdr.Name != "/" && hdr.Name != "//" && hdr.Name != "/SYM64/") {
                offset += StaticLibraryParser.SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER
            } else {
                offset += StaticLibraryParser.SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER + hdr.Size + (hdr.Size & 1)
            }
        }
        return false
    }


    ExtractMemberToFile(objName, outPath) {
        result := this._FindMember(objName)
        if !result
            throw Error("Object not found: " objName)

        if (result.IsThin) {
            try {
                FileCopy(result.Member.Path, outPath, true)
                return GetFullPathName(outPath)
            } catch as er {
                throw Error("Failed to copy thin member (" result.Member.Path "): " er.Message)
            }
        }

        try {
            destBuf := Buffer(result.Member.Size)
            DllCall("RtlMoveMemory", "Ptr", destBuf, "Ptr", result.Owner.ptr.Ptr + result.Member.DataOffset, "UPtr", result.Member.Size)
            f := FileOpen(outPath, "w")
            f.RawWrite(destBuf)
            f.Close()
            return outPath
        } catch as er {
            throw Error("Failed to create (.o /.obj) file... " er.Message)
        }

        GetFullPathName(path) {
            size := DllCall("GetFullPathName", "Str", path, "UInt", 0, "Ptr", 0, "Ptr", 0)
            buf  := Buffer(size * 2)
            DllCall("GetFullPathName", "Str", path, "UInt", size, "Ptr", buf, "Ptr", 0)
            return StrGet(buf)
        }
    }


    _FindMember(objName) {
        for member in this.Members {
            if (member.Name = objName)
                return {Member: member, Owner: this, IsThin: false}
            if (member.NestedParser) {
                res := member.NestedParser._FindMember(objName)
                if (res)
                    return res
            }
        }
        for tm in this.ThinMembers {
            if (tm.Name = objName)
                return {Member: tm, Owner: this, IsThin: true}
        }
        return ""
    }

    SwapEndian(n) => ((n & 0xFF) << 24) | ((n & 0xFF00) << 8) | ((n >> 8) & 0xFF00) | ((n >> 24) & 0xFF)
}


class MultiMap extends Map {
    __Item[name] {
        set {
            if !super.Has(name)
                super.__Item[name] := []
            super.__Item[name].Push(value)
        }
        get => super.Has(name) ? super.__Item[name] : []
    }

    Set(name, value) {
        this.__Item[name] := value
        return this
    }

    __Enum(numberOfVars) {
        baseEnum := super.__Enum(2)
        currentKey := "", currentArray := "", arrayIdx := 0

        EnumMulti(&k, &v := "") {
            while true {
                if (currentArray == "" || arrayIdx > currentArray.Length) {
                    if !baseEnum(&currentKey, &currentArray)
                        return false
                    arrayIdx := 1
                }
                
                if (arrayIdx <= currentArray.Length) {
                    k := currentKey
                    if (numberOfVars == 2)
                        v := currentArray[arrayIdx]
                    arrayIdx++
                    return true
                }
            }
        }
        return EnumMulti
    }
}

; dirPath := "D:\GCC_tdm64-gcc-9.2.0\x86_64-w64-mingw32\lib"

; Loop Files, dirPath "\*.a" {
;     SLP := StaticLibraryParser(A_LoopFileFullPath)

;     for symName, info in SLP.ResolvedSymbols {
;         if (symName == "__mingw_raise_matherr") {
;             dbg symName "`n" info.ObjFile "`n" info.DataOffset "`n" info.Size "`n" info.IsThin "`n" A_LoopFileFullPath
;             return
;         }
;     }
; }


/*
class StaticLibraryParser {
    static IMAGE_ARCHIVE_START := "!<arch>`n"
    static SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER := 60

    MAGIC => StrGet(this.ptr.Ptr, 8, "UTF-8")

    __New(libPath) {
        this.firsrOrsecondSymbolMap := Map()   ; Имя символа -> смещение (выбираеться First или Second в зависимоти от метода HasSecondLinkerMember)
        this.Members                := []      ; [{Name: "file.o", DataOffset: ..., Size: ...}, ...]
        this.MembersByOffset        := Map()   ; Смещение заголовка -> Данные obj файла
        this.ResolvedSymbols        := Map()   ; Итоговый результат: Имя символа -> {ObjName, DataOffset, Size}

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
            this.firsrOrsecondSymbolMap[StringTable] := Offsets
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
            this.firsrOrsecondSymbolMap[symName] := objOffset
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
        hasSecond         := this.HasSecondLinkerMember()
        offset            := 8 ; данные идут сразу за сигнатурой "!<arch>`n"
        linkerMemberCount := 0
        while (offset < this.size) { ; ДОДЕЛАТЬ: У архивов ar есть подархивы (вложенные) - по хорошему, их тоже нужно достовать рекурсивно, хотя я без понятия зачем нужен архив в архиве, мда.
            hdr             := this.IMAGE_ARCHIVE_MEMBER_HEADER(offset)
            dataOffset      := offset + StaticLibraryParser.SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER
            isNestedArchive := false

            if (hdr.Name == "/") {
                linkerMemberCount++
                if (linkerMemberCount == 1 && !hasSecond) {
                    this.ParseFirstLinkerMember(dataOffset)
                } else if (linkerMemberCount == 2 && hasSecond) {
                    this.ParseSecondLinkerMember(dataOffset)
                }
            } else if (hdr.Name == "//") {
                this.ParseLongnamesMember(dataOffset)
            } else {
                if (hdr.Size >= 8 && StrGet(this.ptr.Ptr + dataOffset, 8, "UTF-8") == StaticLibraryParser.IMAGE_ARCHIVE_START) { ; Проверяем, не является ли этот файл вложенным архивом (сверяем первые 8 байт данных)
                    isNestedArchive := true
                }
                this.Members.Push({Name: this.ResolveName(hdr.Name), DataOffset: dataOffset, Size: hdr.Size, IsArchive: isNestedArchive})
                this.MembersByOffset[offset] := {Name: this.ResolveName(hdr.Name), DataOffset: dataOffset, Size: hdr.Size, IsArchive: isNestedArchive}
            }

            offset := dataOffset + hdr.Size + (hdr.Size & 1) ; смещение следующего файла с учетом выравнивания. Если размер нечетный, добавляется 1 байт
        }
        this.LinkSymbolsToObjects()
    }


    LinkSymbolsToObjects() {
        for symName, headerOffset in this.firsrOrsecondSymbolMap {
            if (this.MembersByOffset.Has(headerOffset)) { ; headerOffset указывает точно на начало IMAGE_ARCHIVE_MEMBER_HEADER нужного файла
                objInfo := this.MembersByOffset[headerOffset]
                this.ResolvedSymbols[symName] := {ObjFile: objInfo.Name, DataOffset: objInfo.DataOffset, Size: objInfo.Size}
            } else {
                this.ResolvedSymbols[symName] := {ObjFile: "UNKNOWN", DataOffset: 0, Size: 0} ; На случай поврежденного архива, где смещение указывает в никуда
            }
        }
    }


    ; В контексте ar архивов First Linker Member и Second Linker Member - это одно и тоже. Но только Second Linker Member более современный вариант, и он парсится быстрее.
    ; Данный метод находит более предпачтительный варинт линкер-члена, поскольку Second Linker Member не всегда есть (в .a я вообще не нашел Second, так есть только First).
    HasSecondLinkerMember() {
        offset := 8
        linkerMemberCount := 0
        while (offset < this.size) {
            hdr := this.IMAGE_ARCHIVE_MEMBER_HEADER(offset)
            if (hdr.Name == "/") {
                linkerMemberCount++
                if (linkerMemberCount == 2) {
                    return true
                }
            }
            offset += StaticLibraryParser.SIZEOF_IMAGE_ARCHIVE_MEMBER_HEADER + hdr.Size + (hdr.Size & 1)
        }
        return false
    }

    SwapEndian(n) => ((n & 0xFF) << 24) | ((n & 0xFF00) << 8) | ((n >> 8) & 0xFF00) | ((n >> 24) & 0xFF) ; Big-Endian -> Little-Endian
}


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
*/


; Не используется...
/*
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
*/

/**
 * - Я без понятия как получать именна dll, кроме как собрать exe с пустой main и прочитать все импорты...
 * - Вроде бы это работает неплохо, но нужно тестить...
 * |user32:MessageBoxA:2
 * UPD:: Идея нуждается в доработке. Возможно этот код будет удален как и PEImports
 */
/*
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
*/

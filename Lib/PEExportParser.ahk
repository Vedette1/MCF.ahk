#Requires AutoHotkey v2.0
#SingleInstance Force

; Часть кода была заимствована у "thqby". Отдельная благодарность за функцию SearchDllPath!
; https://github.com/thqby/ahk2_lib/blob/06aed7a1c42f754dfcb67962d055311a480d0848/MCode/COFFReader.ahk#L582

class PEExportParser {
    static IMAGE_DOS_SIGNATURE           := 0x5A4D     ; 'MZ'
    static IMAGE_NT_SIGNATURE            := 0x00004550 ; 'PE\0\0'
    static IMAGE_FILE_MACHINE_I386       := 0x014C
    static IMAGE_FILE_MACHINE_AMD64      := 0x8664
    static IMAGE_FILE_EXECUTABLE_IMAGE   := 0x0002
    static IMAGE_FILE_DLL                := 0x2000
    static IMAGE_NT_OPTIONAL_HDR32_MAGIC := 0x010B
    static IMAGE_NT_OPTIONAL_HDR64_MAGIC := 0x020B

    static SIZEOF_FILE_HEADER      := 20
    static SIZEOF_SECTION_HEADER   := 40
    static SIZEOF_EXPORT_DIRECTORY := 40

    __New(dllPath, is64Bit := true, autoSearch := true, ignoreArch := false) {
        this.Exports    := Map()
        this.Is64Bit    := is64Bit
        this.ignoreArch := ignoreArch
        if autoSearch {
            is32bit := (is64Bit = "") ? false : !is64Bit
            this.DllPath := this.SearchDllPath(dllPath, is32bit)
        } else {
            this.DllPath := dllPath ; путь передан как есть, никакой подмены
        }
        SplitPath(this.DllPath, &fileName)
        this.DllName := fileName
        this.GetExportTable()
    }


    GetExportTable() {
        if (!FileExist(this.DllPath)) {
            throw Error("DLL not found: '" this.DllPath "'. Specify the absolute path to the DLL.`n64-bit DLLs are located in C:\Windows\System32.`n32-bit DLLs are located in C:\Windows\SysWOW64.")
        }
        
        this.File := FileOpen(this.DllPath, "r")
        if !(this.File) {
            throw Error("Failed to open file: " this.DllPath)
        }

        try {
            this.File.Pos := 0
            if (this.File.ReadUShort() != PEExportParser.IMAGE_DOS_SIGNATURE)
                throw Error("Invalid DOS signature (not MZ)")
            
            this.File.Pos := 0x3C
            e_lfanew := this.File.ReadUInt()

            this.File.Pos := e_lfanew
            if (this.File.ReadUInt() != PEExportParser.IMAGE_NT_SIGNATURE) {
                throw Error("Invalid NT Signature (not PE)")
            }

            fileHdrOffset := e_lfanew + 4
            fileHdr := this.IMAGE_FILE_HEADER(fileHdrOffset)

            if (fileHdr.Machine != PEExportParser.IMAGE_FILE_MACHINE_I386 && fileHdr.Machine != PEExportParser.IMAGE_FILE_MACHINE_AMD64) {
                throw Error("Unsupported processor architecture")
            }

            this.Arch := (fileHdr.Machine == PEExportParser.IMAGE_FILE_MACHINE_AMD64) ? "x64" : "x86"
            if (this.Is64Bit == "")
                this.Is64Bit := (this.Arch == "x64")

            if !(fileHdr.Characteristics & PEExportParser.IMAGE_FILE_EXECUTABLE_IMAGE) {
                throw Error("The file is not executable.")
            }

            optHdrOffset := fileHdrOffset + PEExportParser.SIZEOF_FILE_HEADER
            optHdr := this.IMAGE_OPTIONAL_HEADER(optHdrOffset, this.Is64Bit)

            if (optHdr.Magic != (this.Is64Bit ? PEExportParser.IMAGE_NT_OPTIONAL_HDR64_MAGIC : PEExportParser.IMAGE_NT_OPTIONAL_HDR32_MAGIC) && !this.ignoreArch) {
                throw Error("The file's bitness does not match the expected value. This most likely means that PEparser could not find the DLL with the required bitness: " this.DllPath ". Please specify the absolute path to the DLL [" this.DllName "].`n64-bit DLLs are located in C:\Windows\System32.`n32-bit DLLs are located in C:\Windows\SysWOW64.`n")
            }
            if (optHdr.ExportDirRVA == 0 || optHdr.ExportDirSize == 0) { ; Если таблица экспорта отсутствует
                return this.Exports
            }

            sectHdrOffset := optHdrOffset + fileHdr.SizeOfOptionalHeader
            this.Sections := this.ReadSectionHeaders(sectHdrOffset, fileHdr.NumberOfSections)
            exportFileOffset := this.RvaToFileOffset(optHdr.ExportDirRVA)
            exportDir := this.IMAGE_EXPORT_DIRECTORY(exportFileOffset)

            if (exportDir.NumberOfNames == 0) {
                return this.Exports
            }

            ; Загружаем массивы функций, имен и ординалов (читаем блоками для скорости)
            funcTblOffset  := this.RvaToFileOffset(exportDir.AddressOfFunctions)
            nameTblOffset  := this.RvaToFileOffset(exportDir.AddressOfNames)
            ordTblOffset   := this.RvaToFileOffset(exportDir.AddressOfNameOrdinals)
            funcBuf        := this.ReadBuffer(funcTblOffset, exportDir.NumberOfFunctions * 4)
            nameBuf        := this.ReadBuffer(nameTblOffset, exportDir.NumberOfNames * 4)
            ordBuf         := this.ReadBuffer(ordTblOffset,  exportDir.NumberOfNames * 2)
            endOfExportDir := optHdr.ExportDirRVA + optHdr.ExportDirSize

            loop exportDir.NumberOfNames {
                nameRVA       := NumGet(nameBuf, (A_Index - 1) * 4, "UInt")
                ordinal       := NumGet(ordBuf, (A_Index - 1) * 2, "UShort")
                funcRVA       := NumGet(funcBuf, ordinal * 4, "UInt")
                nameStr       := this.ReadString(this.RvaToFileOffset(nameRVA))
                actualOrdinal := ordinal + exportDir._Base ; настоящий ординал экспорта

                ; Является ли экспорт форвардом
                isForwarder := false
                forwarderTarget := "NO"
                if (funcRVA >= optHdr.ExportDirRVA && funcRVA < endOfExportDir) {
                    isForwarder := true
                    forwarderTarget := this.ReadString(this.RvaToFileOffset(funcRVA))
                }

                this.Exports[nameStr] := {
                    RVA: funcRVA,
                    Ordinal: actualOrdinal,
                    Name: nameStr,
                    ForwarderTarget: forwarderTarget,
                }
            }
        } finally {
            this.File.Close()
        }
    }


    IMAGE_FILE_HEADER(offset) {
        buf := this.ReadBuffer(offset, PEExportParser.SIZEOF_FILE_HEADER)
        return {
            Machine:              NumGet(buf, 0, "UShort"),
            NumberOfSections:     NumGet(buf, 2, "UShort"),
            SizeOfOptionalHeader: NumGet(buf, 16, "UShort"),
            Characteristics:      NumGet(buf, 18, "UShort")
        }
    }


    IMAGE_OPTIONAL_HEADER(offset, is64Bit) {
        buf := this.ReadBuffer(offset, 128) ; Читаем достаточно большой кусок, чтобы захватить DataDirectories
        dataDirOffset := is64Bit ? 112 : 96 ; Смещение DataDirectory[0] (Export Table) зависит от архитектуры PE/PE+
        return {
            Magic:               NumGet(buf, 0, "UShort"),
            NumberOfRvaAndSizes: NumGet(buf, dataDirOffset - 4, "UInt"),
            ExportDirRVA:        NumGet(buf, dataDirOffset + 0, "UInt"),
            ExportDirSize:       NumGet(buf, dataDirOffset + 4, "UInt")
        }
    }


    ReadSectionHeaders(offset, count) {
        sections := []
        buf := this.ReadBuffer(offset, count * PEExportParser.SIZEOF_SECTION_HEADER)
        
        currentOffset := 0
        loop count {
            sections.Push({
                VirtualSize:      NumGet(buf, currentOffset + 8,  "UInt"),
                VirtualAddress:   NumGet(buf, currentOffset + 12, "UInt"),
                SizeOfRawData:    NumGet(buf, currentOffset + 16, "UInt"),
                PointerToRawData: NumGet(buf, currentOffset + 20, "UInt")
            })
            currentOffset += PEExportParser.SIZEOF_SECTION_HEADER
        }
        return sections
    }


    IMAGE_EXPORT_DIRECTORY(offset) {
        buf := this.ReadBuffer(offset, PEExportParser.SIZEOF_EXPORT_DIRECTORY)
        return {
            _Base:                 NumGet(buf, 16, "UInt"), ; Не получится писать просто "Base", ибо это зарезервированное свойство Any
            NumberOfFunctions:     NumGet(buf, 20, "UInt"),
            NumberOfNames:         NumGet(buf, 24, "UInt"),
            AddressOfFunctions:    NumGet(buf, 28, "UInt"),
            AddressOfNames:        NumGet(buf, 32, "UInt"),
            AddressOfNameOrdinals: NumGet(buf, 36, "UInt")
        }
    }


    SearchDllPath(path, is32bit := false) {
        SplitPath(StrReplace(path, '/', '\'), , &dir, &ext, &name)
        ext := "." (ext || "dll"), dir && dir .= "\"
        if (DllCall("SearchPath", "Ptr", 0, "Str", dir name ext, "Ptr", 0, "UInt", 2048, "Ptr", b := Buffer(4096), "Ptr", 0)) {
            path1 := StrGet(b), path := dir name ext
            if (is32bit && A_Is64bitOS && path = SubStr(path2 := StrReplace(path1, A_WinDir '\System32\', A_WinDir '\SysWOW64\'), -StrLen(path))) {
                return path2
            }
            return path1
        }
        if (FileExist(path1 := dir RegExReplace(name, '(32|64)$', is32bit ? '32' : '64') ext)) {
            return path1
        }
        if (dir) {
            if (FileExist(path1 := RegExReplace(dir, 'i)(?<=(^|\\))x(86|64)(?=\\)', is32bit ? 'x86' : 'x64') name ext)) {
                return path1
            }
            if (FileExist(path1 := RegExReplace(dir, 'i)(?<=(^|\\))(32|64)(?=bit\\)', is32bit ? '32' : '64') name ext)) {
                return path1
            }
        }
        return path
    }


    ; Преобразует виртуальный адрес (RVA) в физическое смещение в файле
    RvaToFileOffset(rva) {
        for section in this.Sections {
            if (rva >= section.VirtualAddress && rva < section.VirtualAddress + section.VirtualSize) { ; Если RVA попадает в диапазон этой секции
                return rva - section.VirtualAddress + section.PointerToRawData
            }
        }
        return rva ; Fallback (по сути не должен отрабатывать для валидных RVA)
    }


    ReadBuffer(offset, size) {
        buf := Buffer(size, 0)
        this.File.Pos := offset
        this.File.RawRead(buf)
        return buf
    }


    ReadString(offset) {
        return StrGet(this.ReadBuffer(offset, 256), "cp0")
    }
}


FindExportSymbolsDlls(symbols, paths, findAll := false, recurse := false) {
    GetAbsPath(path) {
        buf := Buffer(4096)
        len := DllCall("GetFullPathNameW", "str", path, "uint", 2048, "ptr", buf, "ptr", 0)
        return len ? StrGet(buf, len) : path
    }

    if (symbols.Length == 0) {
        throw Error("No search symbols specified.")
    }

    if (paths.Length == 0) {
        throw Error("No search paths specified. Specify paths to DLLs or directories.")
    }

    symSet := Map()
    for sym in symbols {
        symSet[sym] := true
    }

    remaining := symSet.Clone()
    dlls := Map()
    for raw in paths {
        p := StrReplace(raw, '/', '\')
        attr := FileExist(p)
        if InStr(attr, "D") { ; директория
            loop files, RTrim(p, '\') "\*.dll", recurse ? "FR" : "F"
                dlls[GetAbsPath(A_LoopFileFullPath)] := true
        } else if (attr) { ; существующий файл
            dlls[GetAbsPath(p)] := true
        } else if (DllCall("SearchPath", "ptr", 0, "str", p, "ptr", 0, "uint", 1024, "ptr", buf := Buffer(2048), "ptr", 0)) {
            dlls[StrGet(buf)] := true ; просто имя вида "user32.dll"
        }
    }

    result := []
    for dllPath in dlls {
        try parser := PEExportParser(dllPath, "", false)
        catch
            continue

        for sym in symSet {
            if parser.Exports.Has(sym) {
                e := parser.Exports[sym]
                result.Push({
                    DllPath:         parser.DllPath,
                    Name:            e.Name,
                    RVA:             e.RVA,
                    Ordinal:         e.Ordinal,
                    ForwarderTarget: e.ForwarderTarget,
                    Arch:            parser.Arch
                })
                remaining.Delete(sym)
            }
        }
        if (!findAll && remaining.Count == 0)
            break
    }

    if (result.Length == 0) {
        throw Error("Search completed! Unfortunately, no symbols were found...")
    }

    return result
}
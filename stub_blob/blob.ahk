#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ../MCF.ahk


class ShellCode {
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


    __New(mcodeStr, arch := "x64", shellCodeBuild := true, offsetTable := "", entryPoint := "", formatC := false) {
        this.VA_size          := arch == "x64" ? 8 : 4
        this.shellCodeBuild   := shellCodeBuild
        this.offsetTable      := offsetTable
        this.entryPoint       := entryPoint
        this.formatC          := formatC

        this.mcodeArr         := StrSplit(RegExReplace(mcodeStr, "\s+"), "|")
        this.stubBuffer       := Binary.StringToBinary(RegExReplace(arch == "x64" ? ShellCode.stub_x64 : ShellCode.stub_x86, "\s+"), 12)
        this.mcodeBuffer      := Binary.StringToBinary(this.mcodeArr[1], 12)

        this.GetData()
        this.importCount      := this.data.IMP.Length
        this.VACount          := this.data.VA.Length
        this.IATSize          := this.importCount * (arch == "x64" ? 16 : 4)
        this.imp_RVA          := this.stubBuffer.size + this.mcodeBuffer.size
        this.VA_RVA           := this.imp_RVA + (this.importCount * ShellCode.SIZEOF_IMP_REC)
        this.pool_RVA         := this.VA_RVA + (this.VACount * ShellCode.SIZEOF_VA_REC)
        this.IAT_RVA          := this.pool_RVA + this.stringPoolSize
        this.totalSize        := this.IAT_RVA + this.IATSize

        this.Payload_RVA := this.stubBuffer.size ; DllCall(Ptr + Payload_RVA + offset)
    }


    Build() {
        Table     := this.ParseOffsets()
        FinalBlob := Buffer(this.totalSize, 0)

        RtlMoveMemory(FinalBlob.Ptr, this.stubBuffer.Ptr, this.stubBuffer.size)
        NumPut("UInt", 0x3153434D,            ; MAGIC (MCS1)
               "UInt", 0,                     ; flags (0)
               "UInt", this.importCount,      ; n_imports
               "UInt", this.VACount,          ; n_va
               "UInt", this.stubBuffer.size,  ; payload_rva
               "UInt", this.mcodeBuffer.size, ; payload_size
               "UInt", this.imp_RVA,          ; imp_rva
               "UInt", this.VA_RVA,           ; va_rva
               "UInt", this.pool_RVA,         ; pool_rva
               "UInt", this.IAT_RVA,          ; iat_rva
               "UInt", Table.entryPoint == "" ? 0 : Table.entryPoint, ; entry_rva (0 для MCode, иначе смещение внутри Payload)
               FinalBlob)

        RtlMoveMemory(FinalBlob.Ptr + this.stubBuffer.size, this.mcodeBuffer.Ptr, this.mcodeBuffer.size)

        current_pool_offset := 0
        for i, imp_data in this.data.IMP {
            o := this.imp_RVA + ((i - 1) * ShellCode.SIZEOF_IMP_REC)

            NumPut("UInt", current_pool_offset, FinalBlob.Ptr + 0 + o)
            written_bytes := StrPut(imp_data.Dll, FinalBlob.Ptr + this.pool_RVA + current_pool_offset, "CP0")
            current_pool_offset += written_bytes

            if (imp_data.IsOrd) {
                NumPut("UInt", imp_data.Fn, FinalBlob.Ptr + 4 + o)
            } else {
                NumPut("UInt", current_pool_offset, FinalBlob.Ptr + 4 + o)
                written_bytes := StrPut(imp_data.Fn, FinalBlob.Ptr + this.pool_RVA + current_pool_offset, "CP0")
                current_pool_offset += written_bytes
            }

            NumPut("UInt",  imp_data.PatchOffset, FinalBlob.Ptr + 8  + o)
            NumPut("UInt",  imp_data.Disp,        FinalBlob.Ptr + 12 + o)
            NumPut("UChar", imp_data.IsOrd,       FinalBlob.Ptr + 16 + o)
        }

        for i, va_data in this.data.VA {
            o := this.VA_RVA + ((i - 1) * ShellCode.SIZEOF_VA_REC)
            NumPut("UInt",  va_data.RelocOffset, FinalBlob.Ptr + 0 + o)
            NumPut("UChar", va_data.Size,        FinalBlob.Ptr + 4 + o)
        }

        return {
            hex:      Binary.BinaryToStrin(FinalBlob, FinalBlob.Size, 12),
            base64:   Binary.BinaryToStrin(FinalBlob, FinalBlob.Size, 1),
            compress: Binary.BinaryToCompressedBase64(FinalBlob, FinalBlob.Size, 2),
            newTable: Table.table,
            log:      Table.log
        }
    }


    GetData() {
        this.data := {IMP: [], VA: []}
        this.stringPoolSize := 0

        loop (this.mcodeArr.Length - 1) {
            item := StrSplit(this.mcodeArr[A_Index + 1], ":")
            if (item[1] == "VA") {
                this.data.VA.Push({Size: item[2], RelocOffset: item[3]})
            } else {
                dll_name := item[1]
                fn_name  := item[2]
                this.stringPoolSize += StrPut(dll_name, "CP0")

                is_ordinal := IsInteger(fn_name)
                if (!is_ordinal) {
                    this.stringPoolSize += StrPut(fn_name, "CP0")
                }

                this.data.IMP.Push({
                    Dll: dll_name,
                    Fn: fn_name,
                    PatchOffset: item[3],
                    Disp: item[4],
                    IsOrd: is_ordinal
                })
            }
        }
    }


    ParseOffsets() {
        ret               := {table: "", entryPoint: 0, log: ""}
        parsedTable       := ""
        validOffsetsCount := 0
        
        if (this.entryPoint != "") {
            if (!this.shellCodeBuild) {
                ret.log := "Mcode cannot have a specific entry point, it is chosen arbitrarily. If you want to build a Shellcode, change the build method in this window."
            } else {
                if IsNumber(this.entryPoint) {
                    ret.entryPoint := Format("0x{:X}", this.entryPoint + this.Payload_RVA)
                    ret.log := "Entry point set -> " . ret.entryPoint
                } else {
                    escapedKey := RegExReplace(this.entryPoint, "([\\.*+?^${}()|\[\]])", "\$1")
                    if RegExMatch(this.offsetTable, 'i)offset\["' . escapedKey . '"\] := ptr \+ (0x[0-9a-fA-F]+|\d+)', &m) {
                        ret.entryPoint := Format("0x{:X}", m[1] + this.Payload_RVA)
                        ret.log := "Entry point set -> '" . this.entryPoint . "' -> " . ret.entryPoint
                    } else {
                        ret.log := "Symbol not found, set the offset manually."
                    }
                }
            }
        }

        ; форматирование таблицы
        Loop Parse, this.offsetTable, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line = "")
                continue

            line := RegExReplace(line, "[ \t]+", " ")
            if RegExMatch(line, 'i)^(offset\["(.*?)"\] := ptr \+ )(0x[0-9a-fA-F]+|\d+)(.*)$', &m) {
                basePart    := m[1]
                keyName     := m[2]
                numPart     := m[3]
                commentPart := Trim(m[4])
                
                ; Комменты
                if (commentPart = ";") {
                    commentPart := ""
                } else if (commentPart != "") {
                    if (this.formatC && SubStr(commentPart, 1, 1) = ";") {
                        commentPart := " //" . SubStr(commentPart, 2)
                    } else {
                        commentPart := " " . commentPart
                    }
                }
                
                ; Форматирование под C/C++ или AHK
                if (this.formatC) {
                    line := "#define " . keyName . " " . Format("0x{:X}", numPart + this.Payload_RVA) . commentPart
                } else {
                    line := basePart . Format("0x{:X}", numPart + this.Payload_RVA) . commentPart
                }
                
                parsedTable .= line . "`n"
                validOffsetsCount++
                
            }
            ; "offset := Map()", только если это не C-формат
            else if (!this.formatC && RegExMatch(line, "i)^offset := Map\(\)$")) {
                parsedTable .= line . "`n"
            }
        }
        
        ; Проверка на валидность таблицы
        if (validOffsetsCount == 0) {
            ret.table := "Failed to read the offset table. Recompile Mcode and try again."
        } else {
            ret.table := Trim(parsedTable, "`n")
        }
        
        return ret
    }


    GetKeysFromText(text) {
        keys := []
        Loop Parse, text, "`n", "`r" {
            if RegExMatch(A_LoopField, 'i)offset\["(.*?)"\]', &m)
                keys.Push(m[1])
        }
        return keys
    }


    MultilineStr(str, is64 := true) {
        s := is64 ? 'x64 := "`n(`n' : 'x86 := "`n(`n'
        s .= RegExReplace(str, "(.{" Integer(176) "})", "$1`n") . '`n)"`n'
        s .= "ptr := GetMcodePtr(" (is64 ? 'x64' : ', x86') ")"
        return s
    }
}
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include const.ahk

class Compiler {
    class Settings {
        src               := ""
        srcFileMode       := "cpp"
        flagsObjdump      := "-D -C -M intel"
        flagsObj          := "-m64 -O2"
        flagsExe          := "-m64 -O2 -s"
        flagsDll          := "-m64 -O2 -s"

        optimizeSizeMcode := false
        removeDbgSection  := false

        Use               := "GCC"
        GCCPath           := ""
        MSVCPath          := ""
        disassemblerPath  := ""
    }


    static tempCpp := GLOBAL_WORKING_DIR "\temp.cpp"
    static tempC   := GLOBAL_WORKING_DIR "\temp.c"
    static tempAsm := GLOBAL_WORKING_DIR "\temp.asm"
    static tempO   := GLOBAL_WORKING_DIR "\temp.o"
    static logErr  := GLOBAL_WORKING_DIR "\logErr.log"


    __New(settingsObj := Compiler.Settings()) {
        this.o            := settingsObj
        this.GCC          := this.o.GCCPath == "" ? "gcc" : Chr(34) this.o.GCCPath Chr(34)
        this.MSVC         := Chr(34) this.o.MSVCPath Chr(34)
        this.disassembler := this.o.disassemblerPath == "" ? "objdump" : this.o.disassemblerPath

        if (this.o.removeDbgSection) {
            if (this.o.Use == "GCC") {
                this.o.flagsObj .= " -fno-ident"
            } else if (this.o.Use == "MSVC") {
                this.o.flagsObj .= " /Zl /GR-" ; Я не нашел нужные флаги... Потом поискать...
            }
        }

        if (this.o.optimizeSizeMcode) {
            if (this.o.Use == "GCC") {
                this.o.flagsObj .= " -falign-functions=1 -falign-jumps=1 -falign-loops=1 -falign-labels=1"
            } else if (this.o.Use == "MSVC") {
                this.o.flagsObj .= " /Os" ; Аналогично... Я не нашел нужные флаги... Потом поискать...
            }
        }

        this.CreateTempSrcFile()
    }


    ; Если src это код, то создасться временный c / cpp файл (в зависимости от настроек в GUI "this.o.srcFileMode")
    CreateTempSrcFile() { ; C / Cpp / Def
        try FileDelete(Compiler.tempC)
        try FileDelete(Compiler.tempCpp)
        if !(FileExist(this.o.src)) {
            switch (this.o.srcFileMode), false {
                case "c"   : FileAppend(this.o.src, this.o.src := Compiler.tempC,   "UTF-8")
                case "cpp" : FileAppend(this.o.src, this.o.src := Compiler.tempCpp, "UTF-8")
            }
        }
    }


    RunCompiler(err := "ERROR", args*) {
        command := "", log := ""
        for arg in args {
            SplitPath(arg,,, &ext)
            if (StrLower(ext) == 'log"')
                log := arg
            command .= arg " "
        }
        command := "cmd /c " Chr(34) RTrim(command, A_Space) Chr(34)
        result  := RunWait(command, GLOBAL_WORKING_DIR, "Hide")
        if (result != 0) {
            log := StrReplace(log, Chr(34))
            errMsg := FileExist(log) ? FileRead(log, "CP866") : "Unknown error"
            return Error(err ":`n`n" errMsg)
        }
    }


    ObjGCC() {
        if (this.o.Use == "GCC") { ; .exe
            return this.RunCompiler("Error compiling obj file (GCC)", this.GCC, "-c", Chr(34) this.o.src Chr(34), "-o", Chr(34) Compiler.tempO Chr(34), this.o.flagsObj, ">", Chr(34) Compiler.logErr Chr(34), "2>&1")
        } else if (this.o.Use == "MSVC") { ; .bat
            return this.RunCompiler("Error compiling obj file (MSVC)", this.MSVC, "&& cl /c", Chr(34) this.o.src Chr(34), "/Fo" Chr(34) Compiler.tempO Chr(34), this.o.flagsObj, ">", Chr(34) Compiler.logErr Chr(34), "2>&1")
        } else {
            return Error("The compiler is not defined:`n This mistake shouldn't happen...")
        }
    }

    DllGCC(newDllF) => this.RunCompiler("Error compiling dll file", this.GCC, "-shared",          Chr(34) this.o.src Chr(34), "-o", Chr(34) newDllF Chr(34), this.o.flagsDll, "2>", Chr(34) Compiler.logErr Chr(34))
    ExeGCC(newExeF) => this.RunCompiler("Error compiling exe file", this.GCC,                     Chr(34) this.o.src Chr(34), "-o", Chr(34) newExeF Chr(34), this.o.flagsExe, "2>", Chr(34) Compiler.logErr Chr(34))
    ObjdumpGCC(pathObj)    => this.RunCompiler("Objdump failed", this.disassembler, this.o.flagsObjdump, Chr(34) pathObj Chr(34), ">",  Chr(34) Compiler.tempAsm Chr(34), "2>", Chr(34) Compiler.logErr Chr(34))
}
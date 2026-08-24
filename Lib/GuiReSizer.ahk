#Requires AutoHotkey v2.0

Class GuiReSizer {
    Static Call(GuiObj, WindowMinMax, GuiW, GuiH) {
        ; Initial display of Gui use redraw to cleanup first positioning
        Try
            (GuiObj.Init)
        Catch
            GuiObj.Init := 3 ; Redraw twice and initialize abbreviations on Initial Call (called on initial Show)
        ; Window minimize and maximize
        If WindowMinMax = -1 ; Do nothing if window minimized
            Return
        If WindowMinMax = 1 ; Repeat if maximized
            Repeat := true
        ; Loop through all Controls of Gui
        Loop 2 { ; Loop twice by default to calculate Anchor controls
            For Hwnd, CtrlObj in GuiObj {
                ;{ Initializations on First Call
                If GuiObj.Init = 3 {
                    Try CtrlObj.OriginX := CtrlObj.OX
                    Try CtrlObj.OriginXP := CtrlObj.OXP
                    Try CtrlObj.OriginY := CtrlObj.OY
                    Try CtrlObj.OriginYP := CtrlObj.OYP
                    Try CtrlObj.Width := CtrlObj.W
                    Try CtrlObj.WidthP := CtrlObj.WP
                    Try CtrlObj.Height := CtrlObj.H
                    Try CtrlObj.HeightP := CtrlObj.HP
                    Try CtrlObj.MinWidth := CtrlObj.MinW
                    Try CtrlObj.MaxWidth := CtrlObj.MaxW
                    Try CtrlObj.MinHeight := CtrlObj.MinH
                    Try CtrlObj.MaxHeight := CtrlObj.MaxH
                    Try CtrlObj.Function := CtrlObj.F
                    Try CtrlObj.Cleanup := CtrlObj.C
                    Try CtrlObj.Anchor := CtrlObj.A
                    Try CtrlObj.AnchorIn := CtrlObj.AI
                    If !CtrlObj.HasProp("AnchorIn")
                        CtrlObj.AnchorIn := true
                }
                ; Initialize Current Positions and Sizes
                CtrlObj.GetPos(&CtrlX, &CtrlY, &CtrlW, &CtrlH)
                LimitX := AnchorW := GuiW, LimitY := AnchorH := GuiH, OffsetX := OffsetY := 0
                ; Check for Anchor
                If CtrlObj.HasProp("Anchor") {
                    Repeat := true
                    CtrlObj.Anchor.GetPos(&AnchorX, &AnchorY, &AnchorW, &AnchorH)
                    If CtrlObj.HasProp("X") or CtrlObj.HasProp("XP")
                        OffsetX := AnchorX
                    If CtrlObj.HasProp("Y") or CtrlObj.HasProp("YP")
                        OffsetY := AnchorY
                    If CtrlObj.AnchorIn
                        LimitX := AnchorW, LimitY := AnchorH
                }
                ; OriginX
                If CtrlObj.HasProp("OriginX") and CtrlObj.HasProp("OriginXP")
                    OriginX := CtrlObj.OriginX + (CtrlW * CtrlObj.OriginXP)
                Else If CtrlObj.HasProp("OriginX") and !CtrlObj.HasProp("OriginXP")
                    OriginX := CtrlObj.OriginX
                Else If !CtrlObj.HasProp("OriginX") and CtrlObj.HasProp("OriginXP")
                    OriginX := CtrlW * CtrlObj.OriginXP
                Else
                    OriginX := 0
                ; OriginY
                If CtrlObj.HasProp("OriginY") and CtrlObj.HasProp("OriginYP")
                    OriginY := CtrlObj.OriginY + (CtrlH * CtrlObj.OriginYP)
                Else If CtrlObj.HasProp("OriginY") and !CtrlObj.HasProp("OriginYP")
                    OriginY := CtrlObj.OriginY
                Else If !CtrlObj.HasProp("OriginY") and CtrlObj.HasProp("OriginYP")
                    OriginY := CtrlH * CtrlObj.OriginYP
                Else
                    OriginY := 0
                ; X
                If CtrlObj.HasProp("X") and CtrlObj.HasProp("XP")
                    CtrlX := Mod(LimitX + CtrlObj.X + (AnchorW * CtrlObj.XP) - OriginX, LimitX)
                Else If CtrlObj.HasProp("X") and !CtrlObj.HasProp("XP")
                    CtrlX := Mod(LimitX + CtrlObj.X - OriginX, LimitX)
                Else If !CtrlObj.HasProp("X") and CtrlObj.HasProp("XP")
                    CtrlX := Mod(LimitX + (AnchorW * CtrlObj.XP) - OriginX, LimitX)
                ; Y
                If CtrlObj.HasProp("Y") and CtrlObj.HasProp("YP")
                    CtrlY := Mod(LimitY + CtrlObj.Y + (AnchorH * CtrlObj.YP) - OriginY, LimitY)
                Else If CtrlObj.HasProp("Y") and !CtrlObj.HasProp("YP")
                    CtrlY := Mod(LimitY + CtrlObj.Y - OriginY, LimitY)
                Else If !CtrlObj.HasProp("Y") and CtrlObj.HasProp("YP")
                    CtrlY := Mod(LimitY + AnchorH * CtrlObj.YP - OriginY, LimitY)
                ; Width
                If CtrlObj.HasProp("Width") and CtrlObj.HasProp("WidthP")
                    (CtrlObj.Width > 0 and CtrlObj.WidthP > 0 ? CtrlW := CtrlObj.Width + AnchorW * CtrlObj.WidthP : CtrlW := CtrlObj.Width + AnchorW + AnchorW * CtrlObj.WidthP - CtrlX)
                Else If CtrlObj.HasProp("Width") and !CtrlObj.HasProp("WidthP")
                    (CtrlObj.Width > 0 ? CtrlW := CtrlObj.Width : CtrlW := AnchorW + CtrlObj.Width - CtrlX)
                Else If !CtrlObj.HasProp("Width") and CtrlObj.HasProp("WidthP")
                    (CtrlObj.WidthP > 0 ? CtrlW := AnchorW * CtrlObj.WidthP : CtrlW := AnchorW + AnchorW * CtrlObj.WidthP - CtrlX)
                ; Height
                If CtrlObj.HasProp("Height") and CtrlObj.HasProp("HeightP")
                    (CtrlObj.Height > 0 and CtrlObj.HeightP > 0 ? CtrlH := CtrlObj.Height + AnchorH * CtrlObj.HeightP : CtrlH := CtrlObj.Height + AnchorH + AnchorH * CtrlObj.HeightP - CtrlY)
                Else If CtrlObj.HasProp("Height") and !CtrlObj.HasProp("HeightP")
                    (CtrlObj.Height > 0 ? CtrlH := CtrlObj.Height : CtrlH := AnchorH + CtrlObj.Height - CtrlY)
                Else If !CtrlObj.HasProp("Height") and CtrlObj.HasProp("HeightP")
                    (CtrlObj.HeightP > 0 ? CtrlH := AnchorH * CtrlObj.HeightP : CtrlH := AnchorH + AnchorH * CtrlObj.HeightP - CtrlY)
                ; Min Max
                (CtrlObj.HasProp("MinX") ? MinX := CtrlObj.MinX : MinX := -999999)
                (CtrlObj.HasProp("MaxX") ? MaxX := CtrlObj.MaxX : MaxX := 999999)
                (CtrlObj.HasProp("MinY") ? MinY := CtrlObj.MinY : MinY := -999999)
                (CtrlObj.HasProp("MaxY") ? MaxY := CtrlObj.MaxY : MaxY := 999999)
                (CtrlObj.HasProp("MinWidth") ? MinW := CtrlObj.MinWidth : MinW := 0)
                (CtrlObj.HasProp("MaxWidth") ? MaxW := CtrlObj.MaxWidth : MaxW := 999999)
                (CtrlObj.HasProp("MinHeight") ? MinH := CtrlObj.MinHeight : MinH := 0)
                (CtrlObj.HasProp("MaxHeight") ? MaxH := CtrlObj.MaxHeight : MaxH := 999999)
                CtrlX := MinMax(CtrlX, MinX, MaxX)
                CtrlY := MinMax(CtrlY, MinY, MaxY)
                CtrlW := MinMax(CtrlW, MinW, MaxW)
                CtrlH := MinMax(CtrlH, MinH, MaxH)

                CtrlObj.Move(CtrlX + OffsetX, CtrlY + OffsetY, CtrlW, CtrlH)
                If GuiObj.Init or (CtrlObj.HasProp("Cleanup") and CtrlObj.Cleanup = true)
                    CtrlObj.Redraw()
                If CtrlObj.HasProp("Function")
                    CtrlObj.Function(GuiObj) ; CtrlObj is hidden 'this' first parameter
            }
            If !IsSet(Repeat) ; Break loop if no Repeat is needed because of Anchor or Maximize
                Break
        }

        If (GuiObj.Init := GuiObj.Init - 1 > 0) {
            GuiObj.GetClientPos(, , &AnchorW, &AnchorH)
            GuiReSizer(GuiObj, WindowMinMax, AnchorW, AnchorH)
        }
        If WindowMinMax = 1 ; maximized
            GuiObj.Init := 2 ; redraw twice on next call after a maximize
        MinMax(Num, MinNum, MaxNum) => Min(Max(Num, MinNum), MaxNum)
    }

    Static Opt(CtrlObj, Options) => GuiReSizer.Options(CtrlObj, Options)
    Static Options(CtrlObj, Options) {
        For Option in StrSplit(Options, " ") {
            For Abbr, Cmd in Map(
                "xp", "XP", "yp", "YP", "x", "X", "y", "Y",
                "wp", "WidthP", "hp", "HeightP", "w", "Width", "h", "Height",
                "minx", "MinX", "maxx", "MaxX", "miny", "MinY", "maxy", "MaxY",
                "minw", "MinWidth", "maxw", "MaxWidth", "minh", "MinHeight", "maxh", "MaxHeight",
                "oxp", "OriginXP", "oyp", "OriginYP", "ox", "OriginX", "oy", "OriginY")
                If RegExMatch(Option, "i)^" Abbr "([\d.-]*$)", &Match) {
                    CtrlObj.%Cmd% := Match.1
                    Break
                }

            If SubStr(Option, 1, 1) = "o" {
                Flags := SubStr(Option, 2)
                If Flags ~= "i)l"           ; left
                    CtrlObj.OriginXP := 0
                If Flags ~= "i)c"           ; center (left to right)
                    CtrlObj.OriginXP := 0.5
                If Flags ~= "i)r"           ; right
                    CtrlObj.OriginXP := 1
                If Flags ~= "i)t"           ; top
                    CtrlObj.OriginYP := 0
                If Flags ~= "i)m"           ; middle (top to bottom)
                    CtrlObj.OriginYP := 0.5
                If Flags ~= "i)b"           ; bottom
                    CtrlObj.OriginYP := 1
            }
        }
    }

    Static Now(GuiObj, Redraw := true, Init := 2) {
        If Redraw
            GuiObj.Init := Init
        GuiObj.GetClientPos(, , &Width, &Height)
        GuiReSizer(GuiObj, WindowMinMax := 1, Width, Height)
    }
}
; #SingleInstance, force
; SetBatchLines, -1
; #Include Accv2.ahk
; ; Example
; q::
; hwnd := "ahk_exe Code.exe"
; tabBarPath := AccMatchTextAll(hwnd,{name: "Editor actions", role:22})
; tabBarPath := 
; children := Acc_Children(Acc_Get("Object",tabBarPath,,hwnd))
;  ; Get the current value rather than the cached value
; MsgBox, % tabBarPath "`n" children[1].accName(0) "`n" children[1].accRole(0)

; ; 2.1.2.2.1.2.1.1.2.1.1.1.1.1.2.1.1.1.1
; ; 4.1.1.2.1.1.2.1.1.1.1.2.2.1.2.1.1.1
; ; hwnd := "ahk_exe chrome.exe"
; ; menuPath := AccMatchTextAll(hwnd,{name:"Chrome",roletext:"menu button"})
; ; backPath := AccMatchTextAll(hwnd,{name:"Back",role:43})
; ; addressPath := AccMatchTextAll(hwnd,{name:"address and search"})
; ; addressRole := AccMatchTextAll(hwnd,{path:addressPath},"roletext")
; ; addressValue := Acc_Get("Value",addressPath,,hwnd) ; Get the current value rather than the cached value
; ; Msgbox, % Format("Menu path: {}`r`nBack button path: {}`r`nAddress bar path: {}`r`nAddress bar role: {}`r`nURL: {}",menuPath,backPath,addressPath,addressRole,addressValue)
; Return
; Acceptable values for matchlist & get:
; name,value,role,roletext,state
; matchlist is formatted as an array, i.e. AccMatchTextAll("Google Chrome",{name:"Chrome",roletext:"menu button"})
AccMatchTextAll(hwnd, matchList, get := "path", regex := 0, reload := 0) {
  static
  if !IsObject(foundPaths)
      foundPaths := Object()
  nWindow := WinExist(hwnd)
  , matchStr := ""
  , idx := 0
  if (!IsObject(%nWindow%) || reload = 1)
      %nWindow% := JEE_AccGetTextAll(nWindow, , ,"o")
  for k, v in matchList {
      idx++
      matchStr .= k . ":" . StrReplace(v,A_Space) . (idx<matchList.Count()?",":"")
  }
  if !IsObject(foundPaths[nWindow] || reload = 1)
      foundPaths[nWindow] := Object()
  else if foundPaths[nWindow].HasKey(matchStr)
      return foundPaths[nWindow,matchStr,get]
  for i, e in %nWindow% {
      found := 0
      for k, v in e {
          if (v <> "" && matchList.HasKey(k))
              if (regex = 0 && InStr(v,matchlist[k])
              || (regex = 1 && RegExMatch(v, matchList[k])))
                  found++
      }
      if (found = matchList.Count()) {
          foundPaths[nWindow,matchStr] := e
          return e[get]
      }
  }
  return 0
} 

;Helper funcs for Acc.ahk, namely listing and focusing Firefox tabs
;https://autohotkey.com/boards/viewtopic.php?f=6&t=40615
JEE_FirefoxGetTabNames(hWnd:="", vSep:="`n") {
    local
    if (hWnd = "")
      hWnd := WinExist("A")
    oAcc := Acc_Get("Object", "4", 0, "ahk_id " hWnd)
    vRet := 0
    for _, oChild in Acc_Children(oAcc) {
      if (oChild.accName(0) == "Browser tabs") {
        for _, oChild in Acc_Children(oChild) {
          if (oChild.accRole(0) == 60) {
            oAcc := oChild, vRet := 1
            break
          }
        }
      }
    }
    if !vRet {
      oAcc := oChild := ""
      return
    }
  
    vHasSep := !(vSep = "")
    if vHasSep
      vOutput := ""
    else
      oOutput := []
    for _, oChild in Acc_Children(oAcc) {
      ;ROLE_SYSTEM_PUSHBUTTON := 0x2B
      if (oChild.accRole(0) = 0x2B)
        continue
      try vTabText := oChild.accName(0)
      catch
        vTabText := ""
      if vHasSep
        vOutput .= vTabText vSep
      else
        oOutput.Push(vTabText)
    }
    oAcc := oChild := ""
    return vHasSep ? SubStr(vOutput, 1, -StrLen(vSep)) : oOutput
  }
  
  ;==================================================
  
  JEE_FirefoxFocusTabByNum(hWnd:="", vNum:="", title:="")
  {
    local
    if (hWnd = "")
      hWnd := WinExist("A")
    if !vNum
      return
    oAcc := Acc_Get("Object", "4", 0, "ahk_id " hWnd)
    vRet := 0
    for _, oChild in Acc_Children(oAcc)
    {
      if (oChild.accName(0) == "Browser tabs")
      {
        oAcc := Acc_Children(oChild).1, vRet := 1
        break
      }
    }
    if !vRet || !Acc_Children(oAcc)[vNum]
      vNum := ""
    else {
      Acc_Children(oAcc)[vNum].accDoDefaultAction(0)
      WinWait, % title, , 2
      WinActivate
      ControlFocus, ahk_class MozillaWindowClass
    }
    oAcc := oChild := ""
  return vNum
  }

  JEE_AccGetTextAll(hWnd:=0, vSep:="`n", vIndent:="`t", vOpt:="")
  {
    vLimN := 20, vLimV := 20, retObj := 0, oOutput := []
    Loop, Parse, vOpt, % " "
    {
      vTemp := A_LoopField
      if (SubStr(vTemp, 1, 1) = "n")
        vLimN := SubStr(vTemp, 2)
      else if (SubStr(vTemp, 1, 1) = "v")
        vLimV := SubStr(vTemp, 2)
      else if (SubStr(vTemp, 1, 1) = "o")
              retObj := 1, vLimN := vLimV := 255
    }
  
    oMem := {}, oPos := {}
    ;OBJID_WINDOW := 0x0
    oMem[1, 1] := Acc_ObjectFromWindow(hWnd, 0x0)
    oPos[1] := 1, vLevel := 1
    VarSetCapacity(vOutput, 1000000*2)
  
    Loop
    {
      if !vLevel
        break
      if !oMem[vLevel].HasKey(oPos[vLevel])
      {
        oMem.Delete(vLevel)
        oPos.Delete(vLevel)
        vLevelLast := vLevel, vLevel -= 1
        oPos[vLevel]++
        continue
      }
      oKey := oMem[vLevel, oPos[vLevel]]
  
      vName := "", vValue := ""
      if IsObject(oKey)
      {
              vRole := oKey.accRole(0)
        vRoleText := Acc_GetRoleText(vRole)
              vState := Acc_State(oKey)
        try vName := oKey.accName(0)
        try vValue := oKey.accValue(0)
      }
      else
      {
        oParent := oMem[vLevel-1,oPos[vLevel-1]]
        vChildId := IsObject(oKey) ? 0 : oPos[vLevel]
              vRole := oParent.accRole(vChildID)
        vRoleText := Acc_GetRoleText(vRole)
              vState := Acc_State(oParent)
        try vName := oParent.accName(vChildID)
        try vValue := oParent.accValue(vChildID)
      }
      if (StrLen(vName) > vLimN)
        vName := SubStr(vName, 1, vLimN) "..."
      if (StrLen(vValue) > vLimV)
        vValue := SubStr(vValue, 1, vLimV) "..."
      vName := RegExReplace(vName, "[`r`n]", " ")
      vValue := RegExReplace(vValue, "[`r`n]", " ")
  
      vAccPath := ""
      if IsObject(oKey)
      {
        Loop, % oPos.Length() - 1
          vAccPath .= (A_Index=1?"":".") oPos[A_Index+1]
      }
      else
      {
        Loop, % oPos.Length() - 2
          vAccPath .= (A_Index=1?"":".") oPos[A_Index+1]
        vAccPath .= " c" oPos[oPos.Length()]
      }
      vOutput .= vAccPath "`t" JEE_StrRept(vIndent, vLevel-1) vRoleText " [" vName "][" vValue "]" vSep
          oOutput.Push({path:vAccPath,name:vName,value:vValue,roletext:vRoleText,role:vRole,state:vState})
  
      oChildren := Acc_Children(oKey)
      if !oChildren.Length()
        oPos[vLevel]++
      else
      {
        vLevelLast := vLevel, vLevel += 1
        oMem[vLevel] := oChildren
        oPos[vLevel] := 1
      }
    }
  
    return retObj = 1 ? oOutput : SubStr(vOutput, 1, -StrLen(vSep))
  }
  
  JEE_StrRept(vText, vNum)
  {
    if (vNum <= 0)
      return
    return StrReplace(Format("{:" vNum "}", ""), " ", vText)
    ;return StrReplace(Format("{:0" vNum "}", 0), 0, vText)
  } 
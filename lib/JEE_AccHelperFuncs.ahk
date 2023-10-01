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
  
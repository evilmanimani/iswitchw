#NoEnv
#SingleInstance, Force
SendMode, Input
SetBatchLines, -1
SetWorkingDir, %A_ScriptDir%

#Import "lib\Accv2.ahk"
WinGet, hwnd, ID, "ahk_exe Code.exe"
test(hwnd)
delve(oAcc, targetrole = 60) {
    for _, oChild in Acc_Children(oAcc) {
        if (oChild.accRole(0) = targetrole)
            return oChild
        
        try vTabText := oChild.accName(0)
        catch
        vTabText := ""
        MsgBox % vTabText
    }
}

test(hWnd:="", vSep:="`n") {
    local
    if (hWnd = "")
      hWnd := WinExist("A")
    oAcc := Acc_Get("Object", , 0, "ahk_id " hWnd)
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
;----------------------------------------------------------------------
; ENSURE YOU'RE RUNNING WITH THE x64 VERSION OF AHK
; FOR PROPER BROWSER TAB SUPPORT
;
; Vivaldi support is presently broken
;
;

/* 
class Options {

  static defaults := {"compact":}

  __New() {

  }
}
 */
;----------------------------------------------------------------------
;
; User configuration
;

; Use small icons in the listview
Global compact := true

; A bit of a hack, but this 'hides' the scorlls bars, rather the listview is    
; sized out of bounds, you'll still be able to use the scroll wheel or arrows
; but when resizing the window you can't use the left edge of the window, just
; the top and bottom right.
Global hideScrollBars := true

; Uses tcmatch.dll included with QuickSearch eXtended by Samuel Plentz
; https://www.ghisler.ch/board/viewtopic.php?t=22592
; Supports Regex, Simularity, Srch & PinYin
; Included in lib folder, no license info that I could find
; see readme in lib folder for details, use the included tcmatch.ahk to change settings
; By default, for different search modes, start the string with:
;   ? - for regex
;   * - for srch    
;   < - for simularity
; recommended '*' for fast fuzzy searching; you can set one of the other search modes as default here instead if destired
DefaultTCSearch := "" 

; Activate the window if it's the only match
activateOnlyMatch := false

; Hides the UI when focus is lost!
hideWhenFocusLost := false

; Window titles containing any of the listed substrings are filtered out from results
; useful for things like  hiding improperly configured tool windows or screen
; capture software during demos.
filters := []
; "NVIDIA GeForce Overlay","HPSystemEventUtilityHost"

; Add folders containing files or shortcuts you'd like to show in the list.
; Enter new paths as an array
; todo: show file extensions/path in the list, etc.
; shortcutFolders := []
shortcutFolders := ["C:\Users\dmcleod\OneDrive - Shaw Communications Inc\Desktop"
,"C:\Users\dmcleod\OneDrive - Shaw Communications Inc\Documents"]

; Set this to true to update the list of windows every time the search is
; updated. This is usually not necessary and creates additional overhead, so
; it is disabled by default. 
refreshEveryKeystroke := false

;----------------------------------------------------------------------
;
; Global variables
;
;     allwindows  - windows on desktop
;     windows     - windows in listbox
;     search      - the current search string
;     lastSearch  - previous search string
;     switcher_id - the window ID of the switcher window
;     compact     - true when compact listview is enabled (small icons)
;
;----------------------------------------------------------------------
global vivaldiTabObj, chromeTabObj, switcher_id, hlv

#SingleInstance force
#WinActivateForce
#NoEnv
#MaxHotkeysPerInterval, 9999
; #NoTrayIcon
SendMode Input
SetWorkingDir %A_ScriptDir%
SetBatchLines -1
SaveTimer := Func("SaveTimer")
OnExit("Quit")

; Load saved position from settings.ini
IniRead, gui_pos, settings.ini, position, gui_pos, 0

OnMessage(0x20, "WM_SETCURSOR")
OnMessage(0x200, "WM_MOUSEMOVE")
OnMessage(0x201, "WM_LBUTTONDOWN")

fileList := []
if IsObject(shortcutFolders) {
  for i, e in shortcutFolders
    Loop, Files, % e "\*"	
    fileList.Push({"fileName":RegExReplace(A_LoopFileName,"\.\w{3}$"),"path":A_LoopFileFullPath})
}

Menu, Context, Add, Options, MenuHandler
Menu, Context, Add, Exit, MenuHandler

; Gui, +Hwndgui_id -Caption -MaximizeBox -Resize -DpiScale +E0x02000000 +E0x00080000 
Gui, +LastFound +AlwaysOnTop -Caption -Resize -DPIScale +Hwndswitcher_id
Gui, Color, black, 191919
WinSet, Transparent, 225
Gui, Margin, 8, 10
Gui, Font, s14 cEEE8D5, Segoe MDL2 Assets
Gui, Add, Text, xm+5 ym+3, % Chr(0xE721)
Gui, Font, s10 cEEE8D5, Segoe UI
Gui, Add, Edit, w420 h25 x+10 ym gSearchChange vsearch -E0x200,
Gui, Add, ListView, % (hideScrollbars ? "x0" : "x9") " y+8 w490 h500 -VScroll -HScroll -Hdr -Multi Count10 AltSubmit vlist hwndhLV gListViewClick 0x2000 +LV0x10000 -E0x200", index|title|proc|tab
Gui, Show, , Window Switcher
WinWaitActive, ahk_id %switcher_id%, , 1
if gui_pos
  SetWindowPosition(switcher_id, StrSplit(gui_pos, A_Space)*)
LV_ModifyCol(4,0)
Resize()
WinHide, ahk_id %switcher_id%

; Add hotkeys for number row and pad, to focus corresponding item number in the list 
numkey := [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, "Numpad1", "Numpad2", "Numpad3", "Numpad4", "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9", "Numpad0"]
for i, e in numkey {
  num := StrReplace(e, "Numpad")
  KeyFunc := Func("ActivateWindow").Bind(num = 0 ? 10 : num)
  Hotkey, IfWinActive, % "ahk_id" switcher_id
    Hotkey, % "#" e, % KeyFunc
}

; Define hotstrings for selecting rows, by typing the number with a space after
Loop 300 {
  KeyFunc := Func("ActivateWindow").Bind(A_Index)
  Hotkey, IfWinActive, % "ahk_id" switcher_id
    Hotstring(":X:" A_Index , KeyFunc)
}

chromeTabObj := Object(), vivaldiTabObj := Object()
Gosub, RefreshTimer
SetTimer, RefreshTimer, 3000
Settimer, CheckIfVisible, 20

Return

#Include lib\Accv2.ahk

GuiContextMenu() {
  global
  Menu, Context, Show
}

MenuHandler() {
  Switch A_ThisMenuItem {
    Case "Options"  : return
    Case "Exit"     : ExitApp 
  }
}

CheckIfVisible:
  DetectHiddenWindows, Off
  pauseRefresh := WinExist("ahk_id" switcher_id) != "0x0" ? 1 : 0
return

;----------------------------------------------------------------------
;
; Win+space to activate.
;
; #space::  
CapsLock:: ; Use Shift+Capslock to toggle while in use by the hotkey
  If WinActive("ahk_class Windows.UI.Core.CoreWindow") ; clear the search/start menu if it's open, otherwise it keeps stealing focus
    Send, {esc}
  search := lastSearch := ""
  allwindows := Object()
  ; SetTimer, Refresh, -1
  GuiControl, , Edit1
  FadeShow()
  WinActivate, ahk_id %switcher_id%
  WinGetPos, , , w, h, ahk_id %switcher_id%
  WinSet, Region , 0-0 w%w% h%h% R15-15, ahk_id %switcher_id%
  WinSet, AlwaysOnTop, On, ahk_id %switcher_id%
  ControlFocus, Edit1, ahk_id %switcher_id%
  If hideWhenFocusLost
    SetTimer, HideTimer, 10

Return

tooltipOff:
  ToolTip
Return

#If WinActive("ahk_id" switcher_id)
Enter::       ; Activate window
Escape::      ; Close window
^[::          ; ''
^q::          ; ''
^Backspace::  ; Clear text
^w::          ; ''
^h::          ; Backspace
Down::        ; Next row
Tab::         ; ''
^k::          ; ''
Up::          ; Previous row
+Tab::        ; ''
^j::          ; ''
PgUp::        ; Jump up 4 rows
^u::          ; ''
PgDn::        ; Jump down 4 rows
^d::          ; ''
^Home::       ; Jump to top
^End::        ; Jump to bottom
!F4::         ; Quit
~Delete::
~Backspace::
  SetKeyDelay, -1
  Switch A_ThisHotkey {
    Case "Enter": ActivateWindow()
    Case "Escape", "^[", "^q": FadeHide() ;WinHide, ahk_id %switcher_id%
    Case "^Home": LV_ScrollTop()
    Case "^End": LV_ScrollBottom()
    Case "!F4": ExitApp 
    Case "^h": ControlSend, Edit1, {Backspace}, ahk_id %switcher_id%
  Case "~Delete", "~Backspace", "^Backspace", "^w":
    If (SubStr(search, 1, 1) != "?"
        && DefaultTCSearch != "?"
    && ((windows.MaxIndex() < 1 && LV_GetCount() > 1) || LV_GetCount() = 1))
    GuiControl, , Edit1,
    Else If (A_ThisHotkey = "^Backspace" || A_ThisHotkey = "^w")
      ControlSend, Edit1, ^+{left}{Backspace}, ahk_id %switcher_id%
  Case "Tab", "+Tab", "Up", "Down", "PgUp", "PgDn", "^k", "^j", "^u", "^d":
    page := A_ThisHotkey ~= "^(Pg|\^[ud])"
    row := LV_GetNext()
    jump := page ? 4 : 1
    If (row = 0)
      row := 1
    row := GetKeyState("Shift") || A_ThisHotkey ~= "Up|\^[ku]" 
      ? row - jump 
      : row + jump 
    If (row > LV_GetCount()) 
      row := page ? LV_GetCount() : 1 
    Else If (row < 1)
      row := page ? 1 : LV_GetCount()
    LV_Modify(row, "Select Focus Vis")
    if (row > LV_VisibleRows().2) {
      LV_ScrollBottom(row)
    } else if (row <= LV_VisibleRows().1) {
      LV_ScrollTop(row)
    }
  }
  Return

#If WinActive("ahk_id" switcher_id)
WheelDown::
LV_ScrollDown() {
  if (LV_VisibleRows().2 < LV_GetCount())
    sendmessage, 0x115, 1, 0,, ahk_id %hlv%
}
return

WheelUp::
LV_ScrollUp() {
  if (LV_VisibleRows().1 > 0)
    sendmessage, 0x115, 0, 0,, ahk_id %hlv%
}
return  
#if

LV_ScrollBottom(row := "") {
  totalRows := LV_GetCount()
  if !row
    row := totalRows
  loop {
    lastVisibleRow := LV_VisibleRows().2
    if (lastVisibleRow >= row || A_Index > totalRows)
      break
    sendmessage, 0x115, 1, 0,, ahk_id %hlv%
  } ;Until (lastVisibleRow >= row || lastVisibleRow >= totalRows)
  LV_Modify(row, "Select Focus")
}

LV_ScrollTop(row := "") {
  totalRows := LV_GetCount()
  if !row
    row := 1
  loop {
    firstVisibleRow := LV_VisibleRows().1
    if (firstVisibleRow <= row - 1 || A_Index > totalRows)
      break
    sendmessage, 0x115, 0, 0,, ahk_id %hlv%
  } ;Until (firstVisibleRow <= row - 1 || firstVisibleRow <= 0)
  LV_Modify(row, "Select Focus")
}

LV_VisibleRows() {
  global hlv
  static LVM_GETTOPINDEX = 4135		; gets the first visible row
  , LVM_GETCOUNTPERPAGE = 4136	; gets number of visible rows
    SendMessage, LVM_GETCOUNTPERPAGE, 0, 0, , ahk_id %hLV%
    LV_NumOfRows := ErrorLevel	; get number of visible rows
    SendMessage, LVM_GETTOPINDEX, 0, 0, , ahk_id %hLV%
    LV_topIndex := ErrorLevel	; get first visible row
  return [LV_topIndex, LV_topIndex + LV_NumOfRows, LV_NumOfRows] ; [Top row, last row, total visible]
}

SaveTimer() {
  global switcher_id, gui_pos
  CoordMode, Pixel, Screen
  WinGetPos, x, y, w, h, % "ahk_id" switcher_id
  IniWrite, % Format("{} {} {} {}",x,y,w,h) , settings.ini, position, gui_pos
}

; Hides the UI if it loses focus
HideTimer:
  If !WinActive("ahk_id" switcher_id) {
    FadeHide()
    SetTimer, HideTimer, Off
  }
Return

Quit() {
  WinShow, ahk_id %switcher_id%
  SaveTimer()
}

;----------------------------------------------------------------------
;
; Runs whenever Edit control is updated
SearchChange() {
  global
  Gui, Submit, NoHide
  if ((search ~= "^\d+") || (StrLen(search) = 1 && SubStr(search, 1, 1) ~= "[?*<]"))
    return 
  Settimer, Refresh, -1
}

Refresh:
  if (LV_GetCount() = 1) {
    Gui, Font, c90ee90fj
    GuiControl, Font, Edit1
  }
  StartTime := A_TickCount
  RefreshWindowList()
  ElapsedTime := A_TickCount - StartTime
  If (LV_GetCount() > 1) {
    Gui, Font, % LV_GetCount() > 1 && windows.MaxIndex() < 1 ? "cff2626" : "cEEE8D5"
    GuiControl, Font, Edit1
  } Else if (LV_GetCount() = 1) {
    Gui, Font, c90ee90fj
    GuiControl, Font, Edit1
  }
  ; For i, e in windows {
  ;   str .= Format("{:-4} {:-15} {:-55}`n",A_Index ":",SubStr(e.procName,1,14),StrLen(e.title) > 50 ? SubStr(e.title,1,50) "..." : e.title)
  ; }
  ; if search
  ; OutputDebug, % "lvcount: " LV_GetCount() " - windows: " windows.MaxIndex()
  ; . "`n------------------------------------------------------------------------------------------------" 
  ; . Format("`nNew filter: {} | Result count: {:-4} | Time: {:-4} | Search string: {} ",toggleMethod ? "On " : "Off",LV_GetCount(),ElapsedTime,search)
  ; . "`n------------------------------------------------------------------------------------------------`n" . str
  ; str := ""
return

;----------------------------------------------------------------------
;
; Handle mouse click events on the listview
;
ListViewClick:
  if (A_GuiControlEvent = "Normal") {
    ActivateWindow()
  }
return

IncludedIn(needle,haystack) {
  for i, e in needle {
    if InStr(haystack,e)
      return i
  }
  return -1
}

GetAllWindows() {
  allWindowObj := []
  top := DllCall("GetTopWindow", "Ptr","")
  Loop {
    next :=	DllCall("GetWindow", "Ptr", (A_Index = 1 ? top : next),"uint",2)
    allWindowObj.Push(next)
  } Until (!next)
  return allWindowObj
}
;----------------------------------------------------------------------
;
; Fetch info on all active windows
;
ParseAllWindows() {
  global switcher_id, filters, vivaldiTabObj, chromeTabObj
  windows := Object()
  top := DllCall("GetTopWindow", "Ptr","")
  vivaldiTabsPushed := false
  Loop {
    next :=	DllCall("GetWindow", "Ptr", (A_Index = 1 ? top : next),"uint",2)
    ; for _, next in allwindowObj {
    WinGetTitle, title, % "ahk_id" next
    if IncludedIn(filters, title) > -1
      continue
    if title {
      procName := GetProcessName(next)
      if (procName = "chrome") {
        for i, e in chromeTabObj[next] {
          if (!e || e ~= "i)group.*and \d+ other tabs") ; remove blank titles that appears when there are grouped tabs
            continue
          if RegExMatch(e, "i)(.*) - Part of.*group\s?(.*)", match) ; appends group name to grouped tabs
            e := (match2 ? match2 : "Group") . " " . Chr(0x2022) . " " . match1
          windows.Push({"id":next, "title": e, "procName": "Chrome tab", "num": i,"hwnd":next})
        }
      } else if (procName = "firefox") {
        tabs := StrSplit(JEE_FirefoxGetTabNames(next),"`n")
        for i, e in tabs
          windows.Push({"id":next, "title": e, "procName": "Firefox tab", "num": i})
      } else if (!vivaldiTabsPushed && procName = "vivaldi" && vivaldiTabObj.Length() > 0) {
        vivaldiTabsPushed := true
        for _, o in vivaldiTabObj
          windows.Push({"id":o.id, "title": o.title, "procName": "Vivaldi tab"})
      } Else {
        windows.Push({ "id": next, "title": title, "procName": procName })
      }
    }
  } Until (!next)

return windows
}

RefreshWindowList() {
  global allwindows, windows, scoreMatches, fileList
  global search, lastSearch, refreshEveryKeystroke
  windows := []
  toRemove := ""
  If (DefaultTCSearch = "?" || SubStr(search, 1, 1) = "?" || !search || refreshEveryKeystroke || StrLen(search) < StrLen(lastSearch)) {
    allwindows := ParseAllWindows()
    for _, e in fileList {
      path := e.path 
      SplitPath, path, OutFileName, OutDir, OutExt, OutNameNoExt, OutDrive
      RegExMatch(OutDir, "\\(\w+)$", folder)
      allwindows.Push({"procname":folder1,"title":e.fileName . (!RegExMatch(OutExt,"txt|lnk") ? "." OutExt : "" ),"path":e.path})
    }
  }
  lastSearch := search
  for i, e in allwindows {
    str := e.procName " " e.title
    if !search || TCMatch(str,search) {
      windows.Push(e)
    } else {
      toRemove .= i ","
    }
  }
  ; OutputDebug, % "Allwindows count: " allwindows.MaxIndex() " | windows count: " windows.MaxIndex() "`n"
  DrawListView(windows)
  for i, e in StrSplit(toRemove,",")
    allwindows.Delete(e)
}

ActivateWindow(rowNum := "") {
  global windows, ChromeInst
  If !rowNum 
    rowNum:= LV_GetNext("F")
  If (rowNum > LV_GetCount())
    return
  LV_GetText(procName, rowNum, 2)
  LV_GetText(title, rowNum, 3)
  LV_GetText(wid, rowNum, 4)
  Gui Submit
  window := windows[rowNum]
  num := window.num
  path := window.path
  If window.HasKey("path") {
    Run, % """" path """" 
  } Else {
    ; If (procName = "Chrome tab")
    ;   JEE_ChromeFocusTabByNum(wid,num)
    ; Else If (procName = "Firefox tab")
    ;   JEE_FirefoxFocusTabByNum(wid,num)
    If (procName = "Vivaldi tab")
     VivaldiFocusTab(window.id)
    Else If WinActive("ahk_id" wid) {
      WinGet, state, MinMax, ahk_id %wid%
      if (state = -1) {
        WinRestore, ahk_id %wid%
      }
    } else {
      WinActivate, ahk_id %wid%
    }
  }
}

;------------------------------------------------------------5----------
;
; Add window list to listview
;
DrawListView(windows, startFrom := 0) {
  Global switcher_id, fileList, hlv
  static IconArray
  , WS_EX_TOOLWINDOW = 0x80
  , WS_EX_APPWINDOW = 0x40000
  , GW_OWNER = 4
  , WM_GETICON := 0x7F
  ; http://msdn.microsoft.com/en-us/library/windows/desktop/ms632625(v=vs.85).aspx
  , ICON_BIG := 1
  , ICON_SMALL2 := 2
  , ICON_SMALL := 0
  if !WinExist("ahk_id" switcher_id)
    return
  imageListID := IL_Create(windowCount, 1, compact ? 0 : 1)
  If !IsObject(IconArray)
    IconArray := {}
  windowCount := windows.MaxIndex()
  If !windowCount
    return
  iconCount = 0
  removedRows := Array()
  allRows := []

  LV_SetImageList(imageListID, 1)
  LV_GetText(selectedRow, LV_GetNext(),3)
  GuiControl, -Redraw, list
  LV_Delete()
  For idx, window in windows {
    
    wid := window.id
    title := window.title
    procName := window.procName
    tab := window.num
    removed := false
    if (wid = Format("{:d}", switcher_id)) {
      removed := true
    }
    WinGet, style, ExStyle, ahk_id %wid%
    isAppWindow := (style & WS_EX_APPWINDOW)
    isToolWindow := (style & WS_EX_TOOLWINDOW)

    ownerHwnd := DllCall("GetWindow", "uint", wid, "uint", GW_OWNER)
    iconNumber := ""
    if window.HasKey("path") {
      FileName := window.path
      ; Calculate buffer size required for SHFILEINFO structure.
      sfi_size := A_PtrSize + 8 + (A_IsUnicode ? 680 : 340)
      VarSetCapacity(sfi, sfi_size)
      SplitPath, FileName,,, FileExt ; Get the file's extension.
      for i, e in fileList {
        if (e.path = window.path) {
          fileObj := fileList[i]
          iconHandle := fileObj.icon
          Break
        }
      }
      If !iconHandle {
        if !DllCall("Shell32\SHGetFileInfo" . (A_IsUnicode ? "W":"A"), "Str", FileName
        , "UInt", 0, "Ptr", &sfi, "UInt", sfi_size, "UInt", 0x101) { ; 0x101 is SHGFI_ICON+SHGFI_SMALLICON
          IconNumber := 9999999 ; Set it out of bounds to display a blank icon.
        } else {
          iconHandle := NumGet(sfi, 0)
          fileObj.icon := iconHandle
        }
      }
      if (iconHandle <> 0)
        iconNumber := DllCall("ImageList_ReplaceIcon", UInt, imageListID, Int, -1, UInt, iconHandle) + 1
    } else if (procName ~= "(Chrome|Firefox|Vivaldi) tab" || isAppWindow || ( !ownerHwnd and !isToolWindow )) {
      if !(iconHandle := window.icon) {
        if (procName = "Chrome tab") ; Apply the Chrome icon to found Chrome tabs
          wid := WinExist("ahk_exe chrome.exe")
        else if (procName = "Firefox tab")
          wid := WinExist("ahk_exe firefox.exe")
        else if (procName = "Vivaldi tab")
          wid := WinExist("ahk_exe vivaldi.exe")
        ; http://www.autohotkey.com/docs/misc/SendMessageList.htm

        SendMessage, WM_GETICON, ICON_BIG, 0, , ahk_id %wid%
        iconHandle := ErrorLevel
        if (iconHandle = 0) {
          SendMessage, WM_GETICON, ICON_SMALL2, 0, , ahk_id %wid%
          iconHandle := ErrorLevel
          if (iconHandle = 0) {
            SendMessage, WM_GETICON, ICON_SMALL, 0, , ahk_id %wid%
            iconHandle := ErrorLevel
            if (iconHandle = 0) {
              ; http://msdn.microsoft.com/en-us/library/windows/desktop/ms633581(v=vs.85).aspx
              ; To write code that is compatible with both 32-bit and 64-bit
              ; versions of Windows, use GetClassLongPtr. When compiling for 32-bit
              ; Windows, GetClassLongPtr is defined as a call to the GetClassLong
              ; function.
              iconHandle := DllCall("GetClassLongPtr", "uint", wid, "int", -14) ; GCL_HICON is -14

              if (iconHandle = 0) {
                iconHandle := DllCall("GetClassLongPtr", "uint", wid, "int", -34) ; GCL_HICONSM is -34
                if (iconHandle = 0) {
                  iconHandle := DllCall("LoadIcon", "uint", 0, "uint", 32512) ; IDI_APPLICATION is 32512
                }
              }
            }
          }
        }
      }
      if (iconHandle <> 0) {
        iconNumber := DllCall("ImageList_ReplaceIcon", UInt, imageListID, Int, -1, UInt, iconHandle) + 1
        window.icon := iconHandle
      }
    } else {
      WinGetClass, Win_Class, ahk_id %wid%
      if Win_Class = #32770 ; fix for displaying control panel related windows (dialog class) that aren't on taskbar
        iconNumber := IL_Add(imageListID, "C:\WINDOWS\system32\shell32.dll", 217) ; generic control panel icon
    }
    if (removed || iconNumber < 1) {
      removedRows.Push(idx)
      ; windows.RemoveAt(idx)
    } else {
      iconCount+=1
      allRows.Push(["Icon" . iconNumber, iconCount, window.procName, title, wid])
      ; LV_Add("Icon" . iconNumber, iconCount, window.procName, title, tab)
    }
  }
  GuiControl, +Redraw, list
  for i, e in allRows { 
    if (i < startFrom)
      continue
      LV_Add(e*)
  }
  for _, e in removedRows {
    windows.RemoveAt(e)
  }
  loop % LV_GetCount() {
    LV_GetText(r,A_Index,3)
    if (r = selectedRow) {
      LV_Modify(A_Index,"Select Focus Vis")
      break
    }
  }
  ; Don't draw rows without icons.
  windowCount-=removedRows.MaxIndex()

  LV_Modify(1, "Select Focus")

  LV_ModifyCol(1,compact ? 50 : 70)
  LV_ModifyCol(2,110)
  GuiControl, +Redraw, list
  If (windows.Count() = 1 && activateOnlyMatch)
    ActivateWindow(1)
}

RefreshTimer:
  if (!pauseRefresh) {
  ; || WinExist("ahk_exe vivaldi.exe") 
  ; || WinExist("ahk_exe chrome.exe")) {
    for _, next in GetAllWindows()  {
      procName := GetProcessName(next)
      if ( procname = "vivaldi") {
        vivaldiTabObj := VivaldiGetTabNames()
      }
      ; if (procname = "chrome" && (!IsObject(chromeTabObj[next]) || WinActive("ahk_id" next))) {
      ;   chromeTabObj[next] := StrSplit(JEE_ChromeGetTabNames(next),"`n")
    }
    RefreshWindowList()
  }
return

VivaldiGetTabNames() {
  whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
  whr.Open("GET", "http://127.0.0.1:" 5000 "/json/list")
  whr.Send()
  v := whr.ResponseText
  obj := JSON.Load(v)
  filtered := []
  for _, o in obj {
      if (o.type = "page") {
         filtered.Push(o) 
      }
  }
  return filtered
}

RepStr( Str, Count ) { ; By SKAN / CD: 01-July-2017 | goo.gl/U84K7J
Return StrReplace( Format( "{:0" Count "}", "" ), 0, Str )
}

GetAccPath(Acc, byref hwnd="") {
  hwnd := Acc_WindowFromObject(Acc)
  WinObj := Acc_ObjectFromWindow(hwnd)
  WinObjPos := Acc_Location(WinObj).pos
  while Acc_WindowFromObject(Parent:=Acc_Parent(Acc)) = hwnd {
    t2 := GetEnumIndex(Acc) "." t2
    if Acc_Location(Parent).pos = WinObjPos
      return {AccObj:Parent, Path:SubStr(t2,1,-1)}
    Acc := Parent
  }
  while Acc_WindowFromObject(Parent:=Acc_Parent(WinObj)) = hwnd
    t1.="P.", WinObj:=Parent
return {AccObj:Acc, Path:t1 SubStr(t2,1,-1)}
}

GetEnumIndex(Acc, ChildId := 0) {
  if !ChildId {
    ChildPos := Acc_Location(Acc).pos
    try children := Acc_Children(Acc_Parent(Acc))
    For Each, child in children {
      if (IsObject(child) && Acc_Location(child).pos = ChildPos)
        return A_Index
    }
  } else {
    ChildPos := Acc_Location(Acc,ChildId).pos
    try children := Acc_Children(Acc)
    For Each, child in children {
      if !(IsObject(child) && Acc_Location(Acc,child).pos = ChildPos)
        return A_Index
    }
  }
}

VivaldiFocusTab(id) {
  whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
  whr.Open("GET", "http://127.0.0.1:" 5000 "/json/activate/" id)
  whr.Send()
}

;https://autohotkey.com/boards/viewtopic.php?f=6&t=40615

Chromium_API_Request() {
    whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    whr.Open("GET", "http://127.0.0.1:" 5000 "/json/list")
    whr.Send()
    JSON.Parse(whr.ResponseText)
}


JEE_FirefoxGetTabNames(hWnd:="", vSep:="`n")
{
  local
  if (hWnd = "")
    hWnd := WinExist("A")
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
  if !vRet
  {
    oAcc := oChild := ""
    return
  }

  vHasSep := !(vSep = "")
  if vHasSep
    vOutput := ""
  else
    oOutput := []
  for _, oChild in Acc_Children(oAcc)
  {
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

JEE_FirefoxFocusTabByNum(hWnd:="", vNum:="")
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
  else
    Acc_Children(oAcc)[vNum].accDoDefaultAction(0)
  oAcc := oChild := ""
return vNum
}

;==================================================

JEE_FirefoxFocusTabByName(hWnd:="", vTitle:="", vNum:="")
{
  local
  if (hWnd = "")
    hWnd := WinExist("A")
  if (vNum = "")
    vNum := 1
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
  if !vRet
  {
    oAcc := oChild := ""
    return
  }

  vCount := 0, vRet := 0
  for _, oChild in Acc_Children(oAcc)
  {
    vTabText := oChild.accName(0)
    if (vTabText = vTitle)
      vCount++
    if (vCount = vNum)
    {
      oChild.accDoDefaultAction(0), vRet := A_Index
      break
    }
  }
  oAcc := oChild := ""
return vRet
}

;==================================================

TCMatch(aHaystack, aNeedle) {
  global DefaultTCSearch
  static tcMatch := DllCall("GetProcAddress", "Ptr", DllCall("LoadLibrary", "WStr", "lib\TCMatch" . (A_PtrSize == 8 ? "64" : ""), "Ptr"), "AStr", "MatchFileW","Ptr")
  if (SubStr(aNeedle, 1, 1) != "?" && DefaultTCSearch != "?" ) {
    for i, e in StrSplit("/\[^$.|?*+(){}")
      aHaystack := StrReplace(aHaystack, e, A_Space)
  }
  If ( aNeedle ~= "^[^\?<*]" && DefaultTCSearch )
    aNeedle := DefaultTCSearch . aNeedle
return DllCall(tcMatch, "WStr", aNeedle, "WStr", aHaystack)
}

FadeShow() {
  DllCall("AnimateWindow",UInt,switcher_id,UInt,75,UInt,0xa0000)
}

FadeHide() {
  DllCall("AnimateWindow",UInt,switcher_id,UInt,75,UInt,0x90000)
}

AccMatchTextAll(nWindow, matchList, get := "path", regex := 0, reload := 0, depthLimit := 0, ByRef Obj := "") {
  static
  start := A_TickCount
  if !IsObject(foundPaths)
    foundPaths := Object()
  , matchStr := ""
  , idx := 0
  ; nWindow := WinExist(title)
  ; getObj := (get ~= "^(object|obj|o|all)$")
  if (!IsObject(%nWindow%) || reload = 1)
    %nWindow% := JEE_AccGetTextAll(nWindow, , ,"gpath o" . (depthLimit > 0 ? " l" depthLimit : "") )
  count := matchList.Count()
  obj := %nWindow%
  for k, v in matchList {
    if !v {
      count--
      continue
    }
    idx++
    matchStr .= k . ":" . StrReplace(v,A_Space) ","
  }
  matchStr := RTrim(matchStr,",")
  if (!IsObject(foundPaths[nWindow]) || reload = 1)
    foundPaths[nWindow] := Object()
  else if foundPaths[nWindow].HasKey(matchStr) {
    return getObj ? foundPaths[nWindow,matchStr] : foundPaths[nWindow,matchStr,get]
  }
  for i, e in %nWindow% {
    found := 0
    for k, v in e {
      if (v != "" && matchlist[k] != "" && (getObj || e[get] != "" ))
        if ((regex = 0 && InStr(v,matchlist[k]))
        || (regex = 1 && RegExMatch(v, matchList[k])))
      found++
    }
    if (found = count) {
      foundPaths[nWindow,matchStr] := e
      e.time := A_TickCount - start
      return getObj ? e : e[get]
    }
  }
return
}

JEE_AccGetTextAll(hWnd:=0, vSep:="`n", vIndent:="`t", vOpt:="")
{
  vLimN := 20, vLimV := 20, retObj := 0, vLimL := 0, oOutput := []
  Loop, Parse, vOpt, % " "
  {
    vTemp := A_LoopField
    if (SubStr(vTemp, 1, 1) = "n")
      vLimN := SubStr(vTemp, 2)
    else if (SubStr(vTemp, 1, 1) = "v")
      vLimV := SubStr(vTemp, 2)
    else if (SubStr(vTemp, 1, 1) = "o")
      retObj := 1
    else if (SubStr(vTemp, 1, 1) = "l")
      vLimL := SubStr(vTemp, 2)
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
    if (!oMem[vLevel].HasKey(oPos[vLevel]) || (vLimL > 0 && vLevel > vLimL))
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
      try vRole := oKey.accRole(0)
      try vRoleText := Acc_GetRoleText(vRole)
      ; vState := Acc_State(oKey)
      ; vState := Acc_GetStateTextEx2(oKey.accState(0))
      try vName := oKey.accName(0)
      try vValue := oKey.accValue(0)
    }
    else
    {
      oParent := oMem[vLevel-1,oPos[vLevel-1]]
      vChildId := IsObject(oKey) ? 0 : oPos[vLevel]
      try vRole := oParent.accRole(vChildID)
      try vRoleText := Acc_GetRoleText(vRole)
      ; vState := Acc_State(oParent)
      ; vState := Acc_GetStateTextEx2(oParent.accState(0))
      try vName := oParent.accName(vChildID)
      try vValue := oParent.accValue(vChildID)
    }

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

    if retObj {
      oOutput.Push({path:vAccPath,name:vName,value:vValue,roletext:vRoleText,role:vRole,state:vState,depth:vLevel})
    } else {
      if (StrLen(vName) > vLimN)
        vName := SubStr(vName, 1, vLimN) "..."
      if (StrLen(vValue) > vLimV)
        vValue := SubStr(vValue, 1, vLimV) "..."
      vName := RegExReplace(vName, "[`r`n]", " ")
      vValue := RegExReplace(vValue, "[`r`n]", " ")
      vOutput .= vAccPath "`t" JEE_StrRept(vIndent, vLevel-1) vRoleText " [" vName "][" vValue "]" vSep
    }

    Try oChildren := Acc_Children(oKey)
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
}

~LButton Up::
  critical
  If isResizing {
    Resize()
    SetTimer, % SaveTimer, -500 
    ; Tooltip
    isResizing := 0
    DllCall("ReleaseCapture")
  }
return

WM_LBUTTONDOWN() {

  global isResizing, resizeBorder, Windows
  static topBorder := 29

  if !A_Gui
    return

  ; Capture mouse if cursor is over the resize area
  If (!isResizing && resizeBorder) {
    isResizing := 1
    DllCall("SetCapture", "UInt", switcher_id)
    return
  }

  MouseGetPos, , mouseY,, ctrl
  If ( A_Gui && mouseY < topBorder )
    PostMessage, 0xA1, 2 ; 0xA1 = WM_NCLBUTTONDOWN
  ; If (ctrl = "SysListView321")
  ;   ControlFocus, % ctrl, % "ahk_id" switcher_id

}

WM_SETCURSOR() {

  global resizeBorder
  static borderSize := 6
  , cornerMargin := 12
  , IDC_SIZENS := 32645
  , IDC_SIZEWE := 32644
  , IDC_SIZENWSE := 32642
  , IDC_SIZENESW := 32643
  , IDC_HAND := 32649
  , SPI_SETCURSORS := 0x57
  , borderOffset := 0
  , LastCursor, CursorHandle

  if !A_Gui
    return

  WinGetPos, winX, winY, winWidth, winHeight, % "ahk_id" switcher_id
  borderW := winX + borderOffset
  , borderN := winY + borderOffset
  , borderE := winX + winWidth - borderOffset
  , borderS := winY + winHeight - borderOffset

  CoordMode, Mouse, Screen
  MouseGetPos, mouseX, mouseY, varWin, varControl
  GuiControlGet, ctrlText,, % varControl
  GuiControlGet, ctrlName, Name, % varControl

  Switch
  {
    Case (InRange(mouseX, borderW, cornerMargin ) && InRange(mouseY, borderN, cornerMargin )) : corner := "NW"
    Case (InRange(mouseX, borderE - cornerMargin, cornerMargin ) && InRange(mouseY, borderN, cornerMargin )) : corner := "NE"
    Case (InRange(mouseX, borderW, cornerMargin ) && InRange(mouseY, borderS - cornerMargin, cornerMargin )) : corner := "SW"
    Case (InRange(mouseX, borderE - cornerMargin, cornerMargin ) && InRange(mouseY, borderS - cornerMargin, cornerMargin )) : corner := "SE"
    default: corner := ""
  }

  Switch
  {
    Case InRange(mouseY, borderN, borderSize) : resizeBorder := "N"
    Case InRange(mouseY, borderS - borderSize, borderSize) : resizeBorder := "S"
    Case InRange(mouseX, borderE - borderSize, borderSize) : resizeBorder := "E"
    Case InRange(mouseX, borderW, borderSize) : resizeBorder := "W"
    default: resizeBorder := ""
  }

  resizeBorder := corner ? corner : resizeBorder

  Switch resizeBorder {
    Case "N", "S" : cursor := IDC_SIZENS
    Case "W", "E" : cursor := IDC_SIZEWE
    Case "SE", "NW" : cursor := IDC_SIZENWSE
    Case "SW", "NE" : cursor := IDC_SIZENESW
    default: cursor := ""
  }

  If (cursor) {
    CursorHandle := DllCall("LoadCursor", "ptr", 0, "ptr", Cursor, "ptr")
    LastCursor := DllCall("SetCursor", "uint", CursorHandle)
    Return true
  } ;else return

}

InRange(val, start, count) {
  return val >= start && val <= start + count
}

WM_MOUSEMOVE() {

  global resizeBorder, isResizing, borderOffset
  static minWidth := 200
  , minHeight := 150

  if !A_Gui
    return
  ListLines, On
  WinGetPos, winX, winY, winWidth, winHeight, % "ahk_id" switcher_id
  CoordMode, Mouse, Screen
  MouseGetPos, mouseX, mouseY

  If isResizing {

    winSYPos := winY + winHeight
    winEXPos := winX + winWidth

    If InStr(resizeBorder, "W") {
      newWidth := winEXPos - mouseX
      If (newWidth > minWidth && mouseX > 0)
        winX := mouseX
      Else
        newWidth := winWidth
    } Else If InStr(resizeBorder, "E") {
      newWidth := mouseX - winX
      newWidth := newWidth > minWidth ? newWidth : winWidth 
    } Else {
      newWidth := winWidth
    }

    If InStr(resizeBorder, "N") {
      newHeight := winSYPos - mouseY
      If (newHeight > minHeight && mouseY > 0)
        winY := mouseY
      else
        newHeight := winHeight
    } Else If InStr(resizeBorder, "S") {
      newHeight := mouseY - winY
      newHeight := newHeight > minHeight ? newHeight : winH
    } Else {
      newHeight := winHeight
    }
    if (newWidth <= 220 || newHeight <= 127)
      return  
    SetWindowPosition(switcher_id,winX,winY,newWidth,newHeight)
    Resize(newWidth,newHeight)
  }
}

Resize(width := "", height := "") {
  critical
  global hLV
  if (LV_VisibleRows().2 = LV_GetCount())
    LV_ScrollDown()
    ; sendmessage, 0x115, 0, 0,, ahk_id %hlv%  
  if (!width || !height)
    WinGetPos,,, width, height, % "ahk_id" switcher_id
  WinSet, Region , 0-0 w%width% h%height% R15-15, ahk_id %switcher_id%
  GuiControl, Move, list, % "w" (hideScrollBars ? width + 20 : width - 20) " h" height - 50
  GuiControl, Move, search, % "w" width - 52
  LV_ModifyCol(3
    , width - ( hideScrollBars
      ? (compact ? 170 : 190) ; Resizes column 3 to match gui width
    : (compact ? 200 : 220)))
  }

  SetWindowPosition(hwnd, x := "", y := "", w := "", h := "") {
    global hLV
    DllCall("SetWindowPos","uint",hwnd,"uint",0
      ,"int",x,"int",y,"int",w,"int",h
    ,"uint",0x40)
  }

GetProcessName(wid) {
  WinGet, name, ProcessName, ahk_id %wid%
  return StrSplit(name, ".").1
}

;
; cJson.ahk 0.6.0-git-built
; Copyright (c) 2021 Philip Taylor (known also as GeekDude, G33kDude)
; https://github.com/G33kDude/cJson.ahk
;
; MIT License
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
;

class JSON
{
	static version := "0.6.0-git-built"

	BoolsAsInts[]
	{
		get
		{
			this._init()
			return NumGet(this.lib.bBoolsAsInts, "Int")
		}

		set
		{
			this._init()
			NumPut(value, this.lib.bBoolsAsInts, "Int")
			return value
		}
	}

	NullsAsStrings[]
	{
		get
		{
			this._init()
			return NumGet(this.lib.bNullsAsStrings, "Int")
		}

		set
		{
			this._init()
			NumPut(value, this.lib.bNullsAsStrings, "Int")
			return value
		}
	}

	EmptyObjectsAsArrays[]
	{
		get
		{
			this._init()
			return NumGet(this.lib.bEmptyObjectsAsArrays, "Int")
		}

		set
		{
			this._init()
			NumPut(value, this.lib.bEmptyObjectsAsArrays, "Int")
			return value
		}
	}

	EscapeUnicode[]
	{
		get
		{
			this._init()
			return NumGet(this.lib.bEscapeUnicode, "Int")
		}

		set
		{
			this._init()
			NumPut(value, this.lib.bEscapeUnicode, "Int")
			return value
		}
	}

	_init()
	{
		if (this.lib)
			return
		this.lib := this._LoadLib()

		; Populate globals
		NumPut(&this.True, this.lib.objTrue, "UPtr")
		NumPut(&this.False, this.lib.objFalse, "UPtr")
		NumPut(&this.Null, this.lib.objNull, "UPtr")

		this.fnGetObj := Func("Object")
		NumPut(&this.fnGetObj, this.lib.fnGetObj, "UPtr")

		this.fnCastString := Func("Format").Bind("{}")
		NumPut(&this.fnCastString, this.lib.fnCastString, "UPtr")
	}

	_LoadLib32Bit() {
		static CodeBase64 := ""
		. "3bocAQADAAFwATBXVlMAg+wgixV8DAAAAIt0JDCLXCQANIt8JDiLRCQAPIsKOQ4PhIpBAJSF2w+EqgAci0gDunQADLlfAAiJAHQkGMH+H2aJAFAc"
		. "jVAgxwAiAABVAMdABG4AQmsADAhuAG8ADAwIdwBuAAwQXwBPIQAMFGIAagAMGGUAAGMAiRNmiUgAHo1EJBiJfCQACIlcJASJBCQhAFIc6OIZAWeN"
		. "UCACiRO7IgBnZokAGIPEIDHAW14AX8NmkItUJEAgD7bAifkBLvCJAlQAN9ro7w0AAIkGI422Ad+DBxAFXPDHRCQEARIDYIFZgjOieoAzgwcBhhuQ"
		. "AgABBI8AjUwkBIPkCPC6FIAF/3H8VYSJ5YCUUYHsqIGCAEEEizlmiRCJPEWUgHSBFoB0AQOLBwAPtwiNUfdmgyD6Fw+Hy4GU7P8Af/8Po9EPgkMi"
		. "AgAqWAK+AQiNdkAAD7cLidgGFZ4BABUPo9aNWwJzAOaJB2aD+VsPyISkBYAJjh0AG4AHMG4PhBiAB4AEdA8IhbADACVQAmaDAHgCcokXD4XokQDk"
		. "jVAEgAcEdYEHStiCBwaABwZlgQfIQYAHg8AIgD2CbIkgBw+E/gYAK0WUdr8AEsBXOEAxwYJEMeuAAt3YMcDpl0ERhLQmAkN2AIkfwB4Aew+FYP//"
		. "/4MAwAJmD+/AjU1CmEIziQehJMAKDwARRbyLEIlMJFAYjU28wFwgAkZERCQcAh1MJBTAAhB5ghlEJMIZwAEDT8dn/wBSGItdoIsHg3DsJOmPAR7H"
		. "H0FFOggPhfzBdsACiQchgC+JPCSJwA7oUAD+//+FwA+F4AeBYIAFwBWLRbCJHElDB6IKC2Z3IkBaD8yCjgFRwWFIAsATRWIMhmyABcIaLA+FawuB"
		. "CEMgkMIcD7cQjWpKAAr5AAp7AAeADH0ID4REQQKF0g+EAjuDBCJ1Wo1FqEkFJ7P9ASd1R8uGLzOAUYAhcjDFF8whhwwBAwhz54kH6wvdANjrB93Y"
		. "jXQmCACQuMAF/41l8IJZgKxdjWH8w0AjQC10Dw+OGwCKg0TpMIADCXfaQEG+EUGuZokwT6gYZoNA+y0PhBMHoAJFgpAhMtnox0WEwQMhIAMwD4TY"
		. "oEONUwLPABEId4SLdZQAi1YIi04MiVUQiIlNjOgha02MEAqJB7jAKwD3ZQCIAcoPv8uJywDB+x8ByBHag4DA0InDiUWIABEAg9L/iVWMiVgQCIlQ"
		. "DMIPjXPQQGaD/gl2vKANLogPhOCgDYPj34ABSEUPhYKMXZSiLWbAgzsUD4SSYEPgLkuAEWAWcIABMdtgASuAdQuNSAIPt6CEIA+JyI1KIAr5CYgP"
		. "h9cgQYl9iMAHBDHJ5IDqMI0MiQSJxkACD7/SjQwiSmAG/o164AX/CQB24ot9iIk3hRDJD4RNgCEx0rgDgSHjBo0EgIPCAUABwDnKdfTgGNuhQhnd"
		. "QAiEIKGQIBYQ3vHdWKBMlA+3FYAm+OAU5sJz+AUPIIW+/P//IAPcSFYIQAQAaU6AEpDgE2ZYD4U+QAEkd2Ehcy5r4gEid2zhAR7iASJ3c1XhAQ7i"
		. "AQjgAQgief7RgEmDwAooeUlgToAN2rsjeRirPYAP0SAGAUcd4A8iQBOgAcArjXACArrhBIk3iXMIZoCJE4sXD7cKIgQEhMQgLIPABOsfgwQ9oLT+"
		. "icaJ2gAEW8F+YgSvQR2hJm+BC1oCAmKDXHXUD7dKBSQE02JJ+S8PhG4RYAWD6VyAARkPhwI/4AUPt8n/JI3OCCC24llhcYN3ICbhPWA4fQ+FG0Ic"
		. "A3y/7gnjk4BHQBkGoQ2kEuAGkM4Pg2fgBunqgADbZCqin9riAWcqyuIBYio94gG64AGioUIkYCiF1kvAPqAiuKMNA6Fh4YkMQwiAmSGSBDHAg1Ds"
		. "BOmIwAa54dGDEMIEicbCIhfp5qvgM6ehu6uhqKWhqKSfByqiv6GioUWgx0WIY+EEQKKJRYQBaGeQ2MNHpGBiXQ+E7yEBQZEm3EShhJAu+SOkvvsB"
		. "4WOQMfaLTYhmGIl15EJCc0XNzMwAzIPuAffhicgAweoDjTySAf8AKfiDwDBmiUQAdbyJyInRg/iICXfZMAWLfZARVkaNYQGwBYtFhKAK6AY8cB7J"
		. "CXcgD6PL+A+CTQAHcx6gOvFN0wGEdjjhHvosdTcwAb6DAA66VdJRATsRBDawAE0wUOB0DjABc7PCA10QD4Xv+nICi12ERrmxGzIjZokI4yLXs8AB"
		. "UB2hhOAV0y5DYAEp0C7pvZMBvjEDoYDB4AFmiTPpC6AcQAGJggSheEIBC+n2ISdNc0a7QRjBRumOMA3fGGsIuhAPQAIT3VugCIsH6VmBDkqQITCJ"
		. "DzHJ0SHAMASNAllwRvsJdh2NWUK/gAAFD4a+UYBZEp/CAIcwcAiNWakAweMEjUoGiQ8IZolYUQMGZoldYoiUAw+GaAID1ANzJdkD8jAdD7egAkwL"
		. "gKnB4QSNWghwOFaJcR3CBwgmBBopBCNVKQSvLQQKKgQKJgTMK7GAJQQCKQRsKASDwmoMdDHO0BC7kRTEMli1QQG5QAG5cD8aNKSRAqvRGZkCj0EB"
		. "XEwBekEBu8FmSQFlMQXxMzkFUFEuAPAxyYlI/IPCIgIxHwYxwHABxfhjglkccReNQgAeUEwHDOlrwAygRNnoD7cMWAKwcbF2iRfZ4EyJ0PBxwQDp"
		. "2yAE3SLYcCKLdZCQL4tLAAwPr0MID6/OgAHBifD3YwgwJigByrjDWANAB1MMVOlPUQdNIW27ESOJiAffaTBXGd1ZYCNV0XBTMBb6sGu4wAG6QQJo"
		. "FJKD6zDwAgFi0qEg30WIoHcAaInAB9753EEIhgNkdMjQ6b4QBt7JwGYCDDS5L+wQQeEusEDxixBACCnBMksPt02giAHZ6UunAP2iWY2iAK+iACId"
		. "yenlyQBCleEwWcnpSkkBBpMxUPR7hECgCOn/QADw2ejpy2AAQ7V4tQUAADAxMjM0NTY3ADg5QUJDREVGQTEBSB4AACAwAPgAHQAA8R8AAND9cACo"
		. "tAA/AD8APwA/ADEAalgwBamQJMBwGj0AlK18AdN/AjoAvvwBf/QACmpwAFwQMGYAYQB4bABz0tGh0XHRQdFfxABWkgF1AGXyEHLYIlDQ12CNVNDX"
		. "dCSqaIBgOAIqA1DOFFAB1mRwAMHMEGRiDORj42IAHCT/UBSLA4PU7BigAkBgAURiAaADVSDTOPAATPIAdLIBSPukAx1pGJVpMQWdacLWYQYwGA+3"
		. "BuBo0I4JdAJXUAADdBGDxFADstf2uot+DIt2CAUQ2vpBL4CD0gCDUPoAdtgw2TyDuQgVEOZkwmlxoBKFwHQCvCHniTCJeATr6rFw3kb1dwjQd+QF"
		. "1iQwkJBXjZDdANr/dwGz2Yn+U4nTgewCjAETP4t2BIlNKLSLUBDasJDifahAiXWkiE2jgHGFIgzASw+2BfENiEUKrHHtdKCfgH2sAQAZyYPhIIPB"
		. "WwCLM4B9qACNRgACiQNmiQ4PhSYSAAyQA47qkpawMRD/i3AM8AIAdXyB0AA5eBgPjoDQBIWRBOCwBYsLjUGQAwq4k+sBYAyJRdjBAPgfiUXci0W0"
		. "U3LuwXNF2EFz96HJEzFShWaJCnBIwEe5OofxEhAIEfIID4TU0VagUATGRawQAboBGwUQ9wLwEQyD+AEPwoTy0PgGD4TxaeGn5IQiEZz4AqChgQtg"
		. "CUJRgQsDixWQsFdmNrsAD28FeA0AAIkAUBiNUB4PEQAg8w9+BYgAgGYPANZAEIkTul8AAQAsiVAci0W0iQBcJASJRCQIiQA0JOhNCgAAiwgDuSIA"
		. "dIPHAYkAwoPAAokDZokACotNsDl5EA8Ijn0CAKb+weYEAANxDInCjUgCAIB9owCJC4nIAGbHAiwAD4V1QAQAAIB9rAASQwD///+LVbA5egAYD4/R"
		. "/v//OWB6HA+PyABXCHGLAEYIiQQk6DgMBQJ0OgAcjVACiRMEZokAGQyD+AEPBIUJAEWNdCYAkIkFNTQkATjopQkBSAKwAKM7eBAPjToCAwWWcAyF"
		. "2w+EIQGmiwPpWoEetCYBgCsAO1AYD4Q/AAUAAMZFrAC5RnuACIAThfj9AFJFgLSDAAGAfagAWoJuABCF0g+O3oAnAQAvMf+LcAzp/VMAEoQiZpCB"
		. "LlKCLroKdAAIuYGjxwAiAAJPgaYMjVAQx0AABGIAagDHQAgQZQBjAAFmSA7pCt0BIbaBIIsGOwVCgIB3D4QKBoBKBYp4ggU+gAWLFXyABSA50A+E"
		. "2IETMjmwMA+EZgCngThzgQ8EE76BOI1KIMcCACIAVQDHQgRuhABrAAMIbgBvAAOQDHcAbgADEF+ARUjHQhQCIUIYASFmIIlyHIkLgipmiQBKHolF"
		. "2MH4H4iJRdxIYo1F2EBiBOn8xylFtIsAi4BNtIPAAYkBwWk5BQ2JTECKQA1DDOgcAgjACk20iwGJRWaswAqCUYQXgFHCDgJkiQHBW+k2xhVBM4tx"
		. "gQcDvmzBTwEBQHHHCcAudQDBmwhmiXCS/MGcSgYEnY+LB2AikAEYdEq+QLIAiWDBjVAEvwCsQDUwIIt1pInQQVt5AsAxyYX2ficABAGOCInQv4CK"
		. "AIPBAQCDwgJmiTg5zhh17L5BBMEKMIsDBQCrAYCxGdKJC4MA4iCDwl1miRAAjWX0W15fXY0QZ/hfw0GHxwGDxAAPQUnHRCQAZMAOuUDKIwcCSYCO"
		. "AIo5AKEcjqEIoUA/QcaLEY1iQsBPD4XNwAbDxSsu/ICcATbAxZzBxXkcyA+Ov8GbRghADcNZnIMBAFyCWoUc6YzACqCNdgA5eIDRd4OtbYzR8YBi"
		. "gVf+AAwAv5hw+///ZuVmgXkhBQYlAQXIYTZFsCFnjMarwBGDNuKkM3RjZ5njDQq4IS25gyxGAo1G0gZBM04EgWR3IATACBiLVaTiZEACiMz6AUEC"
		. "pIl9nDHSjUBIAYsDic8EN4kQwYPCAQBCZscBQAkAOfp176Ehi6B9nIkDuKExZoEkhhAgFuISGA+MnCAJsjtgHYyT4SVuHQVBGDgD6bSgBONK6RRC"
		. "AhyNQuAUABGgSASFwMgPiWgAgekvgAXhdzyFeKJ7QTcpPeMIjUVAyPIPEA65QFQAFMdF4ZUAQDKhIAEBAQtNyI1NuIsQiMdFzOECx0XcwwAK5MMA"
		. "4GAEAPIPEYRN0AA3GI1N2GA3IiBCA0QkHAIJTCT6FGABEOEE4ACgfeIAQBkD4gBDSwQk/1IYiwBVwIPsJA+3ArJmoBeEE+AiITMJAAdRQCuLE7lA"
		. "NADjFYkI1onHIlsGi0XAQA+3BAiDwYEGdeDnifiJE+ArAgPhpI1CVIXGt0BUA+k6wScD4zPBZVYBiVQkBIAPtlWjiRQkYVFQ2uh9+AAnk8cEkAUB"
		. "P2ohRHAMMcDrgAmQOcIPhBKhCgLBoH/B4QQ5RA7YCHTqgX4hLWkhBearpHUSoAePoEEKfaFLAeS6gwAChdJ/cYEhjn2kixCNSsA3AAONVDoDhf9+"
		. "QgniCjnQdfdhQAgZYwnpRSJPAJSNDAAMKcriCKAEZoM8QuAAdfaLdSF2wh5hHryPaQBIpBfgWeIQlGK6ZwW84ESgLIgQ4BKBCk1ipOAKVAgB4yuj"
		. "D/khoSEB6e335yVFpACDwgOJEYXAeXjK6dXgAkAHZjjnVF2/QZ0iFeQnQ6rhI+AJH0AOoQQDhdt0d2DgdUABbL5lY6IgxwQghYKix0BA+HQAcgCB"
		. "b3JqBoKidsEo7uZf4UO43eESA0AGJQhBf3BRgCAEqgqRf/YCBAgCBDUBBFatAjsjTgQVEzfwJuma0zEWdfVIABVF3CBfYIMGEIl0iFAgDhqRMh6w"
		. "gwYiJo/6EAVs6ZbAAzAOAVEJMWW5ElshTIr2IAUD6YmDEAJhGInQD4Uz0QKqeEgIBYVJspEBTnQEm/IDASVHIQQHe4Q1wB2Z8CPpv0EGUX3pJRMC"
		. "IIsA6XD58D5VVwBWU4PsRItEJMBYi1QkXIvAj9AZGfAeji/QNGEBMf+JQNWJ+otAGIABBMlyAkAMcA3rJfMpAAF0OVAgWsvBFaADYUwEVCQQcS/t"
		. "IAE5EDN+ANqLBCQxycZEBCQPQEJMJEKLSCAIhcl5BwEBAfci2UA1ELsUgR3NzATMzPVQyInfg+sAAffmweoDjQQAkgHAKcGNQTAAidFmiURcGoVg"
		. "0nXfgHzQBCALEJB0ErgtsStf/rIBgcMAXFwaZjlF4GQOaQSSAG7QP0tmO0RaTVABU1ABUUDpEAtgAIs8JIk4g8RENrhxR+FOw3AwEAsPtwJdYDwI"
		. "D7cOZjkQyw+FHzADMcBmoIXJdStm0CjFyw7MhRPgAUAEMcATBPWQMaACD4TkYBpQLQ+3AAxGD7dcRQBmwDnZdLbpzlAB8hcgMduB7JzhE4QkIrAC"
		. "WpwkjuEArCQitGEAUASL4EOJ0wSBwdAAgIPTAIMg+wAPhwvBTse+hXETuXEThcB4a3ALAIn4g+4B9+GJAvhxExySidcB2yAp2IPAMLARdGYJcRON"
		. "VHAA7Q+EkpmhBU0AsFFyHInLkAAEicbRUYkDD7dCIv7hEeqJTdAIM4FWxNEJmw25Ahswdla4EGdmZmZABOkB9wLvwAf4H8H6AikCwpAbjQRGKfiJ"
		. "CtfwB0zxB9eD6wKDIhrBGmaNVFxm0gDJEAmFbhGxhCRROrAIEyBBckvCAqJLev4AkHXzi7TSAYkGGwkB8gtEJEiNRCRAW3IJwABUImlwOEDSJFQQ"
		. "JEyLELEnQI1MRCQw8mdMJFTgAUTVxGVYdABgdABcRGgPagsPag9qGNBpi1wkOCgPtwMSarqgHoXtYHQ/i1UAs2n2Vol200AX8WkD8CTwAgZq5jyJ"
		. "VQAO1heSDtQRixBuuEIEcQ8wJQOUg5Ap8aEUAokQ6UfRJZD0PQoEgDIcAAYYi2wkkiBAZoSNQUkKvnHMAI1ZAokaZokxCA+3CCAEdHQPtkIdAQ2I"
		. "XCQB8AlmQIP5Ig+PPuF9gyD5Bw+OdJAAjVkA+GaD+xoPh6gBUAQPt9v/JJ2cF7AQ8gjBBUCRQwq/XAHCBQRmiTmJGrsBkQZmiVkCD7dIKwAdwgqk"
		. "sQIsgQgajSBDAokCuDMCA4MsxAR3HTEC8DEPCr4p8QS/ckUFMUELeQK86670XXAC0tN8B2Z0B1TrhncCoHICu3ECvhpu8gEZ8ALxBHEC6cpbAUN2"
		. "cAJ0fL0E4cVZsQTpN3fTcAJUtQliGbwJ6Q93AtATXA+FdneQERADItUHQQDaB93pdX+DRVBbz9EA8wPgTuoB8FylJAwFIhZDBDFxA0kEgByJy4nO"
		. "g+MAD2bB7ggPtpsCiMAZg+YPD7a2A5EAgB0CictmwekADGbB6wQPt8lxgAIPtrmhAbQCEAIDI0EGwUiJ+4uQcb77/InzUAAxALAB0BBxBqAQcASN"
		. "WQhAB1EB4QAGROkd9QuNWYEwIiEID4ZOoVaD+R8PLIZEkADAD23gHnMCgIkyZokL6e731AJ9kCQIjV8BiV3OAMAhkPKgAYPD4QD6IKaL8ABSAevo"
		. "dxIKdxYx8AAE6ZcH0fAAAekWh/AABBRkoQJZ4GYSsACD+14Ph7L+/4D/6Wn///+QBgA="
		static Code := false
		if ((A_PtrSize * 8) != 32) {
			Throw Exception("_LoadLib32Bit does not support " (A_PtrSize * 8) " bit AHK, please run using 32 bit AHK")
		}
		; MCL standalone loader https://github.com/G33kDude/MCLib.ahk
		; Copyright (c) 2021 G33kDude, CloakerSmoker (CC-BY-4.0)
		; https://creativecommons.org/licenses/by/4.0/
		if (!Code) {
			CompressedSize := VarSetCapacity(DecompressionBuffer, 5678, 0)
			if !DllCall("Crypt32\CryptStringToBinary", "Str", CodeBase64, "UInt", 0, "UInt", 1, "Ptr", &DecompressionBuffer, "UInt*", CompressedSize, "Ptr", 0, "Ptr", 0, "UInt")
				throw Exception("Failed to convert MCLib b64 to binary")
			if !(pCode := DllCall("GlobalAlloc", "UInt", 0, "Ptr", 8216, "Ptr"))
				throw Exception("Failed to reserve MCLib memory")
			DecompressedSize := 0
			if (DllCall("ntdll\RtlDecompressBuffer", "UShort", 0x102, "Ptr", pCode, "UInt", 8216, "Ptr", &DecompressionBuffer, "UInt", CompressedSize, "UInt*", DecompressedSize, "UInt"))
				throw Exception("Error calling RtlDecompressBuffer",, Format("0x{:08x}", r))
			for k, Offset in [24, 509, 598, 1479, 1671, 1803, 1828, 1892, 2290, 2321, 2342, 3228, 3232, 3236, 3240, 3244, 3248, 3252, 3256, 3260, 3264, 3268, 3272, 3276, 3280, 3284, 3288, 3292, 3296, 3300, 3304, 3308, 3312, 3316, 3320, 3324, 3328, 3332, 3336, 3340, 3344, 3348, 3352, 3356, 3360, 3364, 3368, 3372, 3376, 3380, 3384, 3388, 3392, 3396, 3400, 3404, 3408, 3412, 3416, 3420, 3424, 3428, 3432, 3436, 3847, 4091, 4099, 4116, 4508, 4520, 4532, 5455, 6153, 7138, 7453, 7503, 7916, 7926, 7953, 7960] {
				Old := NumGet(pCode + 0, Offset, "Ptr")
				NumPut(Old + pCode, pCode + 0, Offset, "Ptr")
			}
			OldProtect := 0
			if !DllCall("VirtualProtect", "Ptr", pCode, "Ptr", 8216, "UInt", 0x40, "UInt*", OldProtect, "UInt")
				Throw Exception("Failed to mark MCLib memory as executable")
			Exports := {}
			for ExportName, ExportOffset in {"bBoolsAsInts": 0, "bEmptyObjectsAsArrays": 4, "bEscapeUnicode": 8, "bNullsAsStrings": 12, "dumps": 16, "fnCastString": 288, "fnGetObj": 292, "loads": 296, "objFalse": 3192, "objNull": 3196, "objTrue": 3200} {
				Exports[ExportName] := pCode + ExportOffset
			}
			Code := Exports
		}
		return Code
	}
	_LoadLib64Bit() {
		static CodeBase64 := ""
		. "NLocAQAbAA34DTxTSIMA7EBIiwXkDAAAAEiLAEiJ00ggOQEPhIUANEiFENIPhJwBEIsCQQS5XwEQiUwkOEgAuiIAVQBuAGsIAEiNARyJEEi6IG4A"
		. "bwB3ABNIiQBQCEi6XwBPAIhiAGoBDRC6dAA3AGaJUBxIjVAgQMdAGGUAYwAXEwBIidpmRIlIHsjo/BkBXwNBAFQACBiNUAIAHAAZEDHAAEiDxEBb"
		. "w4tEACRwRQ+2yYlEgCQg6K8OAAAFGAgPH4ABv0GDABAsMdIDTAFHTAAUYOiKpoAqTAAdYDHAABAaAYMYkAEAHJcAQVUAQVRVV1ZTSIEk7MgBB7sU"
		. "gV9EiQIagYyJzUjHQggBARNIiwEPtxBmQIP6IA+HzYAHSQC4/9n///7//wD/SQ+j0A+CMQICgWZIApAPtxFoSInIAxSgARQAD0gAjUkCc+ZIiUUC"
		. "AIALWw+EzQUAMAAPjhMAGYAHbg8MhDyAB4AEdA+FtgIDA4pmg3gCckjAiVUAD4XXgOAACVIEAAkEdQMJxIMEBimABAZlgwSxgQSDwIAIgD3a/f//"
		. "QFxARQAPhCkHADS6wYAUAEjHQwhBggA2YBMxwOmIwALEU0iEiU3BHnsPhWAAMwGAEAJIjVQkcGYAD+/ARTHJSIsMDcsAOYETRTHASQK8BT0PKUQk"
		. "UEjIjbwkwVdIxwBeBEmgSIlUJDBBEFBBArYoQGoAB0ACBwACOAECBcABIMEi/1AwSIsAdCR4SItFAOlijQAEDx9EwSNCSToYD4XeAQ3BI4naSCSJ"
		. "6cEF6E/AHoXAiA+FwwIblCSYAVgAidhIifHodAsngQRAPUNpdyUAXtQPzIKjQD/CFQ+3gJpAExlCZoZ+wVlDGiwPhXFBAw8fhMKDQxzGEQ8MhosA"
		. "B0ACfQ+EV4FDAiJ1R0iJ+oAkhOjAgFqFwHU4yB2ID4c/w4TUciHPHaSHHgQHc+jBGLhAAxD/SIHEAZ5bXl9AXUFcQV3DAAotIHQPD44zgIeD6oIw"
		. "gAMJd9ZBvIGlB0FxwSigOCNIi1UACEgPv+AK+C0PhAJE4ALyDxAVTgoFID64Ij2D+DAPhAIP4AKNSM9mg/kACHeRSItLCJAYSIPC4BtgB40UiYEA"
		. "aFDQSIlLCIUJAESNSNBmQYP5CAl22OAHLg+EUREgSIPg34ABRQ+FBurCI8MHZoM7FA8UhCQBWbdkEP0EAAWARMmAASt1D0iNoEoCD7dCYAVNAC1G"
		. "yuEKwAoPhwmCTMIgAkUx22biI4PoADBDjQybSYnSQcECmESNHEjgBv4RBAZ24EyADUWF24gPhBNAGUGD+2CVAv+AEvMPfgVxCQAAAESJ2jHA0QDq"
		. "Zg9vyIPAAQBmD3LxAmYP/gLBAAHwATnQdecAZg9+wmYPcNgC5QAB2A+vwkGDAOMBdAWNBIABIsBBXPIPKmAAEEuACEWEyQ+EIgALAPIPXsjyDxFL"
		. "MAgPtwNAGYAcMwYBoikFD4XC/P//QPIPWVMIMYAGEXBTCOlA4FHkaOA0ZlgPhSqBZeR3YSNzF2tDAuJ3bEMCBEMC4ndzrUMC8UBJQAIIQAIIRHoC"
		. "3kECg8AKgD0HyvpGenhgUEG4RXoBD0QxwMBBA+m1oAUPRB9AAlQPhaKgAUypwJFBuGEETIAwTMA8FQEFTGBVQYNVIg+EBjkAOGAMBEyNFYMRgB/r"
		. "HZBAt/5JiXDBSYnIoQQkVyAFL2uhIAHER0ALSUALBIdcXHXNAAUhHqEE2iMhL4gPhOQgC4PqXIABEBkPhxOBE7fSSQBjFJJMAdL/4oQPH+Gi1A+D"
		. "ZiAqweNwOH0PheyhASAOHEG5IDsCHoIbC0iJsHMI6dSAA+YGVoAB4aARdMfpuGEGJC7Eo3alQwIpLpJDAiIuRAJ/M4MNIKbY+MYrgq2LBarngBe6"
		. "ISdmIddD4D3U6VXABblh1knAJQAkIGaJSP5MYAbp1dOBOc+mlPnGpr/hcYakwEG9zczMzEepn6Z3iaYCr5JTRYAK0FN2SgzDMl3RF10PhLaQBdIa"
		. "ZreCFAFU6BIQCcFThgD7//9FMdKJ+US6E7NElCS4QSKNDpTSXPQs8B+JyEkPAK/FSMHoI0SNAAyARQHJRSnIAEGDwDBmRYkEAlLQAYnBSInQSACD"
		. "6gFBg/gJdwjOSJijWEmNFEKs6OWBJehYTONYCrAHmWFyZi71VvdydyQxAoWycuq0WV0PhdiwL4zp58It+WosdeBBF3iDxwF0AcEqQwNgVvdL4A8D"
		. "B+3UGevfMBnwRXAzuKElZokDY08BtP9QwR14QAbwAeDBNXeyJ1MnGAJWEAKTAYABi2wNlvJj+AE2EQQ0T0FmuQIfk0/pASAPYSG+ARARAPJIDypD"
		. "CChmiTPwQ0NiV+m8nZADSdAqMCWBKTHSETghIDVIBI1RMFD6CSB2HY1Rv4AABQ9EhuswYY1Rn8IAhyK+8ByNUamwOAbBDOIEchGUAwZEjVnBcVz7"
		. "CQ+GlSAD4ABWv+EAEASO4wCf4wCHUnoxBFQKQQQITAQIVUgESEsEW0sENUcECrVMBApIBPtQEUgEDUsExvBAOEIEg8AM0QOyNS55sBNSF003YIAB"
		. "QbuiDZgBRIlYowFFoQFWvME7pwFgowEqoAG61lzpBHQGEYABvqBzhwFqcIMB+MAZv5CyhwF4RYMB34ABTInIYDRQAPxFMe1JjUACJWAxKTNL6SjA"
		. "DEwPYK9DCEG7oVpSTBtyTIBE6Q6QAYFuESG/8xEhwnSJO4MhViFAdSZzxv5QAhIljQyJ0HKRA2micgHJoADJ8QNTbCrCybBrwfIPWHsEN314v+kx"
		. "0Qd0YxJEgFMP5LdAEn3pCsEBICyAgBRCAsGECRAaScfAc0KKxCym9xJwUAYABumi2RADQb0vqhZo8xECv+FPi0MIRInKECnC6ddQOEQB2rTpH3QA"
		. "0vA8cQCFcABRQB/J6XyFAP2FAK9hgQBRyekdcAAViIQyfuAH6XpQByKO6TXzkACACgVY0ADCAP++DwADDwAKADAxMjM0NQA2Nzg5QUJDRARFRjEB"
		. "BBAAANwQDwAArDAAlREA9AB8cABUtAA/AD8APwArPwAxAPzgzmDwDuz1tT8ARXwBkn8COgB5/AEqKvQAEXAA9SFJAGFgAGwAcwC13RXdX0QAVpIB"
		. "dQBlWBHw3j90ALJsOeWS04hxbVNPKdFsy0gwZajy3VQkEFRMicZibUyNhGlCATHSwGxURW1xAP8MUCgg4cECYEiJdHdBAOACYHSL0APwc0FwcNWz"
		. "X9mxAGi0A3B1datynYEAMOUFMKmBxg+3oH8Q+Al0SVAAA3QLAzC3IQtbXsOQSIuEdgjhb4BIAfCgbhggdOOBxXEKTI1EJCRYIAfomRBIhcAYdMpI"
		. "AOYAATDrwJFwdkiLTtNfEJDYBECQkEFXQVY45fgRMnu0JMByALwk0IFwAEQPKYQk4IEAMIukJGARh6Dmi1EEIERA7VxJic1NmInHRJDn4HuFLkFS"
		. "YA+2NRbw4DRRsDilugACAABBgP4BGQDJg+Egg8FbSACLA0mJwEiDwAACgHwkXABIiQADZkGJCA+FjQAFAABIhdIPjgCjAQAAZkQPbwAFE/7//2YP"
		. "bgQ1IwAOMfbzD34EPREAEkiJ90jBAOcFSQN9GEiFEPYPhSUAvkCE7QAPhaQDAABFhAD2dX9JOXUwDwiOvQQBntsPhCwCBwAIixNIjUICMEG7IgAA"
		. "DAByRIkAGkiLRxBNifgASInaSI2MJKBFAhiEAgfoCQoCMkEWuAEuACsCATxIjVAIArk6AiYTZokIKQBzdBQAEwQADrogAQEniVACDx9AAACLRxiD"
		. "+AEPhAIEAJiD+AYPhFshAgQFD4RyAEmD+FACD4TRhU14AQSLsANBul8AIAJG+QApAB5EDxEAZg/WgHgQZg9+cBgAMIMAUgBDUBzobwkDGA65AmSA"
		. "SAFGRIkISAiDxgGAeyAPj9xjgJGCrA+E6oCIAjPQQQEWiwtBuw0ABL4TAG4AHVEEgBsZSIkC0AJncQIxyUWFIOR+KWaQAAlBuAEAMwCDwQFIg8IC"
		. "AgATAEE5zHXnHrkBCgN+AUGA6UiNSAACGdJIiQuD4gAgg8JdZokQDxAotCTAABMPKLwCJIE6RA8ohCTgEcENgcT4gAFbXl8AXUFcQV1BXkFAX8Nm"
		. "Dx9EQAY7IFEwD4TmQEJFMRj2uXvBCsAshdT9QP//QYMHAcQyFkuAh4ADAoGIj93BBosAF41KAo1CA0JQjVQiA8EuD8MTiQDBg8ABOcJ19whBiQ8B"
		. "EOlo//9o/w8fQ0L3AJdBQrheLANBwU8APMA4AQKRR2PAagCRD4U2gFECko8GwwAbQAI4f1pIi8xPEEBiwGnoJ8NhRGBOuoGFQD+EfoUFQq4floRA"
		. "BYR12kB26LJAotzpUsAGwz3BI5bCI8BzEnTDcxBIQHZPAGIIAGoAA4VIiQjHIEAIZQBjwaFIDGGDe1AO6T5AJcRPi0APSDsN1vmAFYSiwMGTOw2p"
		. "AgPjApcEBawAA0g5wQ+EojPCAwBIOQCnV4WGAvABBb8iAFUAbiwAa4Eigis4gCIgSEC/bgBvAHcABkjAiXgISL9fBCZAA0QQv8Erx0AYAiaJ3Hgc"
		. "AUGBKwDBHkI7RNSJRNbpQ8AVDx+A4SFhQDUPiFP8gBLhD9YBARGLA0WNRCQBhDHS4WdIicFBQk2Ug8LgT8DhTwlE4DmE57rjTwNmiRFCNJKTYAhJ"
		. "O0A0jB0hAXFANA+PsyGEwDSDLuhKgCEu1eFRHwABRkJQAUGJBwI99gU9TZtjBwA9BkARogiOWCABs0BHwFxHEEUYIAoxQF1lJITnwVGLByBNoQmE"
		. "jjgABkAVgAvp/fvkOwRBuqFtSI1BBkGeu0Fu4BjBTWGPWQSBIGyJBABTYhDJYAYjGVM3ogfiJAMa1gAnCBqvBuXkNq3jJulmAAbkQMEC4gvCBQPp"
		. "XqAa5AjgQyWEB3KAB+nS5hODByMBA4Ea+egXw2sB6RKz5glBueEXSY1AiAZBuuIXRYlI4hcMRYmAnsFwVvr//wTppOUJ8g8QB0gAjVQkYGYP78kA"
		. "RTHJSIsNMesRoBGNhCThEEUxwAxBu6AMpqxIiwFIgIlUJDBIjZTiAQgPKYwCBUjHhCTGsCJnYQVUJCggFEAC1pBEAsAnnOYEqIQCRAZjgGnAAkQk"
		. "QGIHAAE4EYIDRCQgIQPyDxEIhCSIAAH/UDBIAItUJGgPtwJmYIXAD4S/4BiiJ7+5whITuWBD4K/kd0ngoaSJwSKhQYnAA0QBB0oEIK7BoQd14EFy"
		. "RbCJCOl5oAjhV0FBWVBED7bNoy6JoA/otJj4ICVYAgSD3MIAEiBMi0EYuAET6xQB4l6NSAFIOcIPJISEYYKJyOBgSMEA4QVJOUQI8HQ24mCjQhTp"
		. "gAiCpOmzV2AK4gZBMcsBDA5AMUEfoIGA1eEMAFJAuGaDeJD+AHXygKHp1yCBAGaQg8IDQYkXaQBQeV2CT0ygAoJPjfqKYYqQw1pCWYBI4MHBDpNh"
		. "uuBKuWzgAEG4oQCpIIQIx2CDdWB+SIHgYQAzQAbpc2EM40eLEgdAsyABobHQdfkNAQVdUArELDHS6OObUTbGBsXiDHMsdFRCcRJ1wQa7ZcYGdABy"
		. "h+EfIndwAFgG6QWxTYXwAm2xWIsV2fUAEEq5AgOJgDtQCoMCSBgI6dzQBfAtBOnTZ4MAIwhtSugQwYphMKydYQK+8iThD1ENuVtRF8Q99/IDBemK"
		. "FgKCAdUyayDCAQA1a35QA+AACALpUIEAiwfp0AEAGpBBV0FWQVUAQVRVV1ZTSIMA7EhIi2kgSYkAzEmJ0kiF7Q8MjlDRHyAkEEyLcQFgKnkYRTHb"
		. "SL4UzcwDAEjgJAjrJKFxH005XCSwSuUhKgSDw6BSxyBMOd0YD4QPAATzAd5+24HRFjHSRTH/ZpA0ADhIhcl5CUj3CNlBv5INjVwkNhhBuRTiUXFX"
		. "yEWJAM1Ig+sCQYPpgAFI9+ZIweoAbgAEkkgBwEgpwQCNQTBIidFmiQJDIXh10k1jyUUAhP90F0WNTf4EuC3xUWPJZkKJCERMENIASItcJAAISo0M"
		. "S2ZBOdACD4VbkE64UTVwKQgPtxRzXUE7VAJQ/g+FP7ABZiAF5whJiTjiMEiDxEgDf4LgMk8QQQ+3CgEwABFmOcoPhQYHRQXzATEEI2aFyXQSt+kQ"
		. "hfXRo8DrquP2PCACD4TKUAGABJMIEYAATAL+MAV0u+lasYABkAoAUho4AE1BHLoT0Qm2GJAlTCQoAEyLCUmJ00iJQONNhcl4e/ANTCCJyEyJyfgT"
		. "SYkC0SMUTInQg8EwgVASDFNJg+oBchSkSJggAkNNQSamkRx/gKoQCfEYcEfCCbAEs0cIEA+3SP7QC3XlMQzASUNHoBI4W17DI/IPghxBujAyCmdm"
		. "IwMA8whI9+5RAMH4AD9IwfoCSCnCAWEJQY0EQkQpyMHQCWaJREv+EUdxH0FACc2D6AK6URy5QaIcmGaJFERVCoXiWlAXQYsQEhzzOnFG/sJ1RlBe"
		. "oDdjCfMTYC4REAlQSoSh0BpIiwJBIrrVq0mJEVAUEA8UtwGCWIISo7Yd6QDj//9MjRU28WHxR2aD+CKwZlHBgyD4Bw+OjJAAjVAA+GaD+hoPh6gB"
		. "EAUPt9JJYxSS4EwB0v/i8A5wGPCNwUACSYsBvlwQBdCNIdIGBGaJMAEHiXih8hUPt0ECRVybQgMiIsAESYsR8VNJifIBw7+JAqAoABbwNCECkv8y"
		. "GgG6cQW7clOfU6EFcgVYAmAmkHIC18V5AmZ/AoJmLvah8QKWp/MC8wpu/grpTzKsc/J88AJ0e7YCdKO5AiOr865xAlN2AmJ/AvuSqGFRFVwPhV8A"
		. "ExEDIWdWC0EAWwvpycExEk2/q7ID85yEsCuPhQzuiQ8HAVwrBJAeSI0VSe8RcdzDg+Mgu740GkCJw2bB6wTTADxZ0gDoDBAB8C7AQwEc0hpAABQC"
		. "AgadAwZjBQ4IMQXADOMFcAbpJxF3CY1QgTAiIQ+GgmQBRoP4Hw+GsStVQQ5sUh5aUB4ZAB7ppvJxb/YYQYugAwGACvOALFEphWrgAQAu4AChIGXw"
		. "cRDTAOvwdJTwECRj9xnwAATpn/euAWHpFo/wAIISZoACjVDgkZAJXg+HUUjpaxABAflG"
		static Code := false
		if ((A_PtrSize * 8) != 64) {
			Throw Exception("_LoadLib64Bit does not support " (A_PtrSize * 8) " bit AHK, please run using 64 bit AHK")
		}
		; MCL standalone loader https://github.com/G33kDude/MCLib.ahk
		; Copyright (c) 2021 G33kDude, CloakerSmoker (CC-BY-4.0)
		; https://creativecommons.org/licenses/by/4.0/
		if (!Code) {
			CompressedSize := VarSetCapacity(DecompressionBuffer, 5343, 0)
			if !DllCall("Crypt32\CryptStringToBinary", "Str", CodeBase64, "UInt", 0, "UInt", 1, "Ptr", &DecompressionBuffer, "UInt*", CompressedSize, "Ptr", 0, "Ptr", 0, "UInt")
				throw Exception("Failed to convert MCLib b64 to binary")
			if !(pCode := DllCall("GlobalAlloc", "UInt", 0, "Ptr", 7984, "Ptr"))
				throw Exception("Failed to reserve MCLib memory")
			DecompressedSize := 0
			if (DllCall("ntdll\RtlDecompressBuffer", "UShort", 0x102, "Ptr", pCode, "UInt", 7984, "Ptr", &DecompressionBuffer, "UInt", CompressedSize, "UInt*", DecompressedSize, "UInt"))
				throw Exception("Error calling RtlDecompressBuffer",, Format("0x{:08x}", r))
			OldProtect := 0
			if !DllCall("VirtualProtect", "Ptr", pCode, "Ptr", 7984, "UInt", 0x40, "UInt*", OldProtect, "UInt")
				Throw Exception("Failed to mark MCLib memory as executable")
			Exports := {}
			for ExportName, ExportOffset in {"bBoolsAsInts": 0, "bEmptyObjectsAsArrays": 16, "bEscapeUnicode": 32, "bNullsAsStrings": 48, "dumps": 64, "fnCastString": 304, "fnGetObj": 320, "loads": 336, "objFalse": 3360, "objNull": 3376, "objTrue": 3392} {
				Exports[ExportName] := pCode + ExportOffset
			}
			Code := Exports
		}
		return Code
	}
	_LoadLib() {
		return A_PtrSize = 4 ? this._LoadLib32Bit() : this._LoadLib64Bit()
	}

	Dump(obj, pretty := 0)
	{
		this._init()
		if (!IsObject(obj))
			throw Exception("Input must be object")
		size := 0
		DllCall(this.lib.dumps, "Ptr", &obj, "Ptr", 0, "Int*", size
		, "Int", !!pretty, "Int", 0, "CDecl Ptr")
		VarSetCapacity(buf, size*2+2, 0)
		DllCall(this.lib.dumps, "Ptr", &obj, "Ptr*", &buf, "Int*", size
		, "Int", !!pretty, "Int", 0, "CDecl Ptr")
		return StrGet(&buf, size, "UTF-16")
	}

	Load(ByRef json)
	{
		this._init()

		_json := " " json ; Prefix with a space to provide room for BSTR prefixes
		VarSetCapacity(pJson, A_PtrSize)
		NumPut(&_json, &pJson, 0, "Ptr")

		VarSetCapacity(pResult, 24)

		if (r := DllCall(this.lib.loads, "Ptr", &pJson, "Ptr", &pResult , "CDecl Int")) || ErrorLevel
		{
			throw Exception("Failed to parse JSON (" r "," ErrorLevel ")", -1
			, Format("Unexpected character at position {}: '{}'"
			, (NumGet(pJson)-&_json)//2, Chr(NumGet(NumGet(pJson), "short"))))
		}

		result := ComObject(0x400C, &pResult)[]
		if (IsObject(result))
			ObjRelease(&result)
		return result
	}

	True[]
	{
		get
		{
			static _ := {"value": true, "name": "true"}
			return _
		}
	}

	False[]
	{
		get
		{
			static _ := {"value": false, "name": "false"}
			return _
		}
	}

	Null[]
	{
		get
		{
			static _ := {"value": "", "name": "null"}
			return _
		}
	}
}

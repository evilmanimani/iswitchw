;----------------------------------------------------------------------
; version 0.1 - Going to start it from here, because this fork now 
; shares basically no code with the original project.
;
; Changelog - 0.1 - 01-10-2023 :
;   - Everything is working! Got Chrome & Vivialdi tabs working,
;     You'll need to set the debug ports for each browser, see the 
;     section below for details on how to configure your browser
;     shortcut.
;   - Fixed JEE_FirefoxGetTabNames() to account for movable UI elements
;     (i.e. the FF button next to the left of the tab bar messed up the Acc path)
;   - Removed unused functions, split other functions into their own
;     files (JEE funcs, cJson)
;   - Minor changes to some functions to improve the feel of the UI
;     (list doesn't visibility flash when refreshing, select always starts
;     at the top of the list, etc.)
;
; Todo:
;   - Add a config screen
;   - Somehow allow browser tabs to appear in MRU order rather than in
;     a big chunk? Not sure how this can be done aside from manually
;     tracking in the session.
;   - AHKv2 rewrite??? 
;----------------------------------------------------------------------
;
; User configuration
;

; Use small icons in the listview
Global compact := true

; A bit of a hack, but this 'hides' the scroll bars, rather the listview is    
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
DefaultTCSearch := "*" 

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
; shortCutFolders := []
; shortcutFolders := [A_StartMenu, A_StartMenuCommon, A_Desktop, A_DesktopCommon]
shortcutFolders := [A_StartMenu, A_StartMenuCommon, A_Desktop, A_DesktopCommon]

recurse_limit := 2

; Set this to true to update the list of windows every time the search is
; updated. This is usually not necessary and creates additional overhead, so
; it is disabled by default. 
refreshEveryKeystroke := false


; To list browser tabs for Chrome or Vivaldi, you'll need to enable remote debugging
; in the browser, create a new browser shortcut with the following appended to the target:
; --remote-debugging-port=9222
; you can set the port number to whatever you with, however ensure that they're set to 
; different ports for each browser, then change the below values to reflect it.

chromeDebugPort := 9222

vivaldiDebugPort := 5000

;----------------------------------------------------------------------
;
; Global variables
;
;     windows     - windows in listbox
;     search      - the current search string
;     lastSearch  - previous search string
;     switcher_id - the window ID of the switcher window
;     compact     - true when compact listview is enabled (small icons)
;
;----------------------------------------------------------------------

global initialLoadComplete := false, browserTabObj, switcher_id, debounced := false, refresh_queued := false, debounce_interval := 100

#SingleInstance force
#WinActivateForce
#NoEnv
#MaxHotkeysPerInterval, 9999
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
recurse_limit := 2
if IsObject(shortcutFolders) {
  for i, e in shortcutFolders {
    rlimit := InStr(e, "Documents") ? 2 : recurse_limit
    StrReplace(e, "\", "\", parent_dir_count)
    Loop, Files, % e "\*", R
    {
      StrReplace(A_LoopFilePath, "\", "\", dir_count)
      if ( dir_count - parent_dir_count > rlimit
        || !(A_LoopFileName ~= "^.*\.(jpe?g|gif|png|docx?|xls|exe|txt|lnk)$"))
        continue
      fileList.Push({"fileName":A_LoopFileName,"path":A_LoopFileFullPath})
    }
  }
}
temp := []
for _, e in fileList {
  path := e.path 
  SplitPath, path, OutFileName, OutDir, OutExt, OutNameNoExt, OutDrive
  RegExMatch(OutDir, "\\(\w+)$", folder)
  temp.Push({"procname":folder1
                  ,"title": OutExt == "lnk" ? OutNameNoExt  : OutFileName
                  ,"path":e.path
                  ,"id": e.path})
}
fileList := temp

; -- still working on options
; Menu, Context, Add, Options, MenuHandler
Menu, Context, Add, Exit, MenuHandler
/* 
Gui, Settings:Margin, 4, 5
Gui, Settings: +LastFound +AlwaysOnTop -Caption +ToolWindow
Gui, Settings:Color, black,0x2e2d2d
*/
Gui, +LastFound +AlwaysOnTop +ToolWindow -Caption -Resize -DPIScale +Hwndswitcher_id
Gui, Color, black, 191919
Gui, Margin, 8, 10
Gui, Font, s14 cEEE8D5, Segoe MDL2 Assets
Gui, Add, Text, ym, % Chr(0xE721)
Gui, Font, s12 cEEE8D5, Segoe UI
Gui, Add, Text, w420 R1 x+10 vEdit1 ym-2 ;-E0x200,
Gui, Font, s10 cEEE8D5, Lucida Sans Typewriter
Gui, Add, Text, w80 Right vCurrentRow ym -E0x200,
Gui, Font, s10 cEEE8D5, Segoe UI
Gui, Add, ListView, % (hideScrollbars ? "x0" : "x9") " y+12 w490 h500 -Hdr -Multi Count10 vlist hwndHLV gListViewFunc AltSubmit +LV0x100 +LV0x10000 +LV0x20 -E0x200", index|title|proc|tab
; listview styles: LV0x100 - flat scrollbars, LV0x10000 - double-buffering, LV0x20 - full row select, -E0x200 -  WS_EX_CLIENTEDGE (disabled)
Gui, Show, , Window Switcher
WinWait, ahk_id %switcher_id%, , 1
WinSet, Transparent, 0, ahk_id %switcher_id%
; if gui_pos
;   SetWindowPosition(switcher_id, StrSplit(gui_pos, A_Space)*)
LV_ModifyCol(4,0)
Resize()
WinHide, ahk_id %switcher_id%
LVColor := new LV_Colors(HLV)
LVColor.Critical := "On"
LVColor.SelectionColors(0x3c3c3c)
; Add hotkeys for number row and pad, to focus corresponding item number in the list 
numkey := [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, "Numpad1", "Numpad2", "Numpad3", "Numpad4", "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9", "Numpad0"]
for i, e in numkey {
  num := StrReplace(e, "Numpad")
  KeyFunc := Func("ActivateWindow").Bind(num = 0 ? 10 : num)
  Hotkey, IfWinActive, % "ahk_id" switcher_id
    Hotkey, % "#" e, % KeyFunc
}

chromeTabObj := Object(), vivaldiTabObj := Object()
RefreshWindowList()
global ihook
ihook := InputHook("", "{Esc}{Enter}")
ihook.OnChar := Func("onChar")
ihook.onKeyDown := Func("onKeyDown")
ihook.VisibleNonText := false
ihook.NotifyNonText := true
ihook.OnEnd := Func("onEnd")
Return

#Include lib\Accv2.ahk
#Include lib\cJson.ahk
#Include lib\JEE_AccHelperFuncs.ahk
#Include lib\Class_LV_Colors.ahk

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

onKeyDown(ihook, vk, sc) {
  static backspace := 8 
  , ctrl_q := 81
  , ctrl_w := 87
  , del := 46
  , lctrl := 162
  , rctrl := 163
  , last_key
  search := ihook.Input
  clear := vk = backspace && (last_key = lctrl || last_key = rctrl)
    || vk = del
    || vk = ctrl_w
  correct := vk = backspace 
  if (vk = ctrl_q) {
    ihook.Stop()
    FadeHide()
  } 
  if (clear) {
    ihook.Stop()
    ihook.Start()
    search := ""
  } 
  if (correct || clear) {
    callRefresh(search)
  }
  last_key := vk
  if !WinExist("ahk_id" switcher_id)
    ihook.Stop()
  OutputDebug, % vk " - " sc "`n"
}

onChar(ihook, char) {
  search := ihook.Input
  OutputDebug, % char " - " search "`n"
  if (char && StrLen(search) > 0) {
    callRefresh(search)
  }
}

debounce() {
  debounced := false
  if (refresh_queued) {
    RefreshWindowList()
  }
  refresh_queued := false
}

callRefresh(search := "") {
  Gui, Font, s12 cEEE8D5, Segoe UI
  GuiControl, , Edit1, % search
  if !search
    debounce_interval := 100
  if (debounced) {
    if !search 
      refresh_queued := true
    return
  }
  debounced := true
  SetTimer, debounce, % -debounce_interval
  func := Func("RefreshWindowList").bind(search)
  SetTimer, % func, -1
}

onEnd(ihook) {
  GuiControl, , Edit1
  if ihook.EndReason != "EndKey"
    return
  OutputDebug, % ih.EndKey
  if ihook.EndKey == "Enter" {
    ActivateWindow()
  }
  FadeHide()
}
;----------------------------------------------------------------------
;
; Capslock to activate (feel free to change if desired)
;
; #space::
$CapsLock::
ShowSwitcher() {
  global
  if !initialLoadComplete
    return
  Thread, NoTimers
  if !WinExist("ahk_id" switcher_id) {
    Thread, NoTimers
    browserTabObj := ParseBrowserWindows()
    FadeGui("in")
    RefreshWindowList()
    ihook.Start()
    If hideWhenFocusLost
      SetTimer, HideTimer, 10
  } else {
    clearInput()
  }
}

clearInput() {
  global
  ihook.Stop()
  callRefresh()
  Sleep 50
  LV_Modify(1, "Select Vis")
  ihook.Start()
}

tooltipOff() {
  ToolTip
}
#If WinExist("ahk_id" switcher_id)
^[::            ; Close window
; ^h::          ; Backspace
*Down::        ; Next row
Tab::         ; ''
^k::          ; ''
*Up::          ; Previous row
+Tab::        ; ''
^j::          ; ''
*PgUp::        ; Jump up 4 rows
^u::          ; ''
*PgDn::        ; Jump down 4 rows
^d::          ; ''
*Home::       ; Jump to top
*End::        ; Jump to bottom
!F4::         ; Quit
KeyHandler() {
  row_count := LV_GetCount()
  SetKeyDelay, -1
  Switch A_ThisHotkey {
    Case "^[": 
      ihook.Stop()
      FadeHide()
    Case "*Home": 
      LV_Modify(1, "Select Vis")
    Case "*End":
      LV_Modify(row_count, "Select Vis")
    Case "!F4": ExitApp
    Case "Tab", "+Tab", "*Up", "*Down", "*PgUp", "*PgDn", "^k", "^j", "^u", "^d":
      page := A_ThisHotkey ~= "^(\*Pg|\^[ud])"
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
      LV_Modify(row, "Select Vis")
  }
}

~LButton Up::
LButtonUp() {
  global
  If isResizing {
    Resize()
    SetTimer, % SaveTimer, -500 
    ; Tooltip
    isResizing := 0
    DllCall("ReleaseCapture")
  }
}

#if

SaveTimer() {
  global switcher_id, gui_pos
  CoordMode, Pixel, Screen
  WinGetPos, x, y, w, h, % "ahk_id" switcher_id
  IniWrite, % Format("{} {} {} {}", x, y, w, h) , settings.ini, position, gui_pos
}

; Hides the UI if it loses focus
HideTimer() {
  If !WinActive("ahk_id" switcher_id) {
    FadeHide()
    SetTimer, HideTimer, Off
  }
}

Quit() {
  WinShow, ahk_id %switcher_id%
  SaveTimer()
}

;----------------------------------------------------------------------
;
; Handle mouse click events on the listview
;
ListViewFunc() {
  global CurrentRow, allRowCount
  Critical, 50
  if (A_GuiEvent = "A") {
   ActivateWindow()
  }
  if (A_GuiEvent = "Normal") {
    LV_Modify(cr, "-Focus")
  } else if (A_GuiEvent = "I") {
    change_type := Errorlevel
    wc := allRowCount
    rc := LV_GetCount()
    cr := A_Eventinfo
    if (InStr(change_type, "S", true)) {
      format_str := Format("{{}: {1}{}}/{{}: {1}{}}", StrLen(wc))
      WinGetPos, , , gui_w, , ahk_id %switcher_id%
      GuiControl, , CurrentRow, % Format(format_str, cr, rc)
      ControlGetPos, x, , w, , Static3
      right_edge := x + w
      if right_edge > (gui_w - 10)
        GuiControl, Move, CurrentRow, % "x" gui_w - 10 - w
    }
  }
} 

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
  global switcher_id, filters 
  windows := Object()
  vivaldi_pushed := false
  chrome_pushed := false
  top := DllCall("GetTopWindow", "Ptr","")
  for _, next in GetAllWindows() {
    WinGetTitle, title, % "ahk_id" next
    if IncludedIn(filters, title) > -1
      continue
    if title {
        procName := GetProcessName(next)
      if (procName = "vivaldi" && !vivaldi_pushed) {
        vivaldi_pushed := true
        windows.Push(browserTabObj.vivaldi*)
      } else if (procName = "chrome" && !chrome_pushed) {
        chrome_pushed := true
        windows.Push(browserTabObj.chrome*)
      } else if (procName = "firefox") {
        windows.Push(browserTabObj.firefox*)
      ; } else if (procName = "Code") {
      ;   if (obj := getVSCodeTabs(next, "get")) {
      ;     windows.Push(obj*)
      ;   } else {
      ;     getVSCodeTabs(next, "find")
      ;     func := Func("RefreshWindowList")
      ;     SetTimer, % func, -5000
      ;     windows.Push({ "id": next, "title": title " (loading tabs)", "procName": procName })
        ; }
      } else {
        windows.Push({ "id": next, "title": title, "procName": procName })
      }
    }
  }
  return windows
}

; WIP
/* 
getVSCodeTabs(hwnd, mode := "set", setObj := 0) {
  static vsCodeWindows := Object()
  var := "v" hwnd
  if (mode = "get" && vsCodeWindows.HasKey(var) && vsCodeWindows[var].Count() > 0) {
    return vsCodeWindows[var]
  } else if (mode := "set" && IsObject(setObj)) {
    vsCodeWindows[var] := setObj
  } else if (mode := "find") {
    func := Func("findVSCodeTabs").Bind(hwnd)
    SetTimer, % func, -1
  }
}

findVSCodeTabs(hwnd) {
  tabBarPath := AccMatchTextAll(hwnd,{name: "Editor actions", role:22})
  tabBarPath := RegExReplace(tabBarPath, "\d$", "1")
  WinGetTitle, title, % "ahk_id" hwnd
  tabBar := Acc_Get("Object",tabBarPath,,title)
  children := Acc_Children(tabBar)
  result := Object()
  for i, child in children {
    name := child.accName(0)
    if (name) {
      result.Push({"id": hwnd, "title": name, "procName": "VSCode tab", "accPath": Format("{}.{}", tabBarPath, i)})
    }
  }
  getVSCodeTabs(hwnd, "set", result)
}
*/

ParseBrowserWindows() {
  global chromeDebugPort, vivaldiDebugPort
  obj := Object()
  obj.chrome := []
  if WinExist("ahk_exe chrome.exe") {
    for _, o in chromiumGetTabNames(chromeDebugPort)
      obj.chrome.Push({"id":o.id, "title": o.title, "procName": "Chrome tab", "url": o.url})
  }
  obj.vivaldi := []
  if WinExist("ahk_exe vivaldi.exe") {
    for _, o in chromiumGetTabNames(vivaldiDebugPort)
      obj.vivaldi.Push({"id":o.id, "title": o.title, "procName": "Vivaldi tab", "url": o.url})
  }
  obj.firefox := []
  if WinExist("ahk_exe firefox.exe") {
    tabs := StrSplit(JEE_FirefoxGetTabNames(next),"`n")
    for i, e in tabs
      obj.firefox.Push({"id":next, "title": e, "procName": "Firefox tab", "num": i})
  }
  return obj
}

filterWindows(allwindows, search) {
  global fileList, DefaultTCSearch, debounce_interval
  static lastResultLen := 0, lastSearch := "", last_windows := []
  start := A_TickCount
  found := InStr(search, lastSearch)
  newSearch := ( !found 
    || !search 
    || lastResultLen = 0
    || refreshEveryKeystroke 
    || DefaultTCSearch = "?" 
    || SubStr(search, 1, 1) = "?")
  toFilter := newSearch ? allwindows : last_windows
 if (newSearch)
    lastResultLen = 0
  lastSearch := search
  result := []
  filterCount := toFilter.Count()
  for i, e in toFilter {
    str := Trim(e.procName " " e.title " " e.url)
    match := TCMatch(str,search) 
    if !search || (match && e.HasKey("icon")) {
      if (search && filterCount <= 100) { ; only score/sort if there's less than 100 items
        score := stringsimilarity.compareTwoStrings(str, search)
        if e.HasKey("path")
         score -= 0.4, if (score < 0) score := 0 ; penalize files
        e.score := score
      }
      result.Push(e)
    }
  }
  resultLen := result.Count()
  if search && resultLen <= 100
    result := ObjectSort(result, "score",,true)
  updateSearchStringColour(resultLen, lastResultLen)
  if (resultLen == 0) {
    result := last_windows
    resultLen := result.Count()
  }
  lastResultLen := resultLen > 0 ? resultLen : lastResultLen
  last_windows := result
  elapsed := A_TickCount - start
  debounce_interval := elapsed + 25
  OutputDebug, % "Filtering took " elapsed "ms`n"
  return [newSearch, result]
}

updateSearchStringColour(len, last_len) {
  red := "cff2626"
  green := "c90ee90fj"
  color := "cEEE8D5" ; white
  if (len == 1 || len <= 1 && last_len = 1) { 
    color := green 
  } else if (last_len > 1 && len == 0) { 
    color := red 
  }
  Gui, Font, % color
  GuiControl, Font, Edit1
}

RefreshWindowList(search := "") {
  global fileList, refreshEveryKeystroke, activateOnlyMatch, allRowCount
  static iconArray := Object(), allwindows
  allwindows := ParseAllWindows()
  allwindows.Push(fileList*)
  allRowCount := allwindows.Count()
  result := !!search ? filterWindows(allwindows, search) : [1, allwindows]
  newSearch := result.1
  windows := result.2
  windows_dict := {}
  for _, o in windows {
    windows_dict[o.id] := o
  }
  ; OutputDebug, % "Allwindows count: " allwindows.MaxIndex() " | windows count: " windows.MaxIndex() "`n"
  windowLen := windows.Count()
  if (newSearch || iconArray.Count() == 0)
    iconArray := generateIconList(windows)
  if (windowLen = 1 && activateOnlyMatch) {
    ActivateWindow(1, windows_dict)
  } else if (windowLen > 0) {
    ActivateWindow("", windows_dict) ; update function with current windows list
    func := Func("DrawListView").Bind(windows, iconArray)
    SetTimer, % func, -1
  }
  return windows
}

ActivateWindow(rowNum := "", updateWindows := false) {
  static windows
  global vivaldiDebugPort, chromeDebugPort
  if IsObject(updateWindows) {
    windows := updateWindows
    if (!rowNum)
      return
  }
  If !rowNum 
    rowNum:= LV_GetNext("F")
  If (rowNum > LV_GetCount())
    return
  updateSearchStringColour(0,0)
  LV_GetText(wid, rowNum, 4)
  FadeHide()
  window := windows[wid]
  procName := window.procName
  title := window.title
  num := window.num
  id := window.id
  If window.HasKey("path") {
    Run, % """" window.path """" 
  } Else {
    If (procName = "Vivaldi tab") {
      chromiumFocusTab(vivaldiDebugPort, title, id)
    } Else If (procName = "Chrome tab") {
      chromiumFocusTab(chromeDebugPort, title, id)
    } Else If (procName = "Firefox tab") {
      JEE_FirefoxFocusTabByNum(id,num, title)
    } Else If WinActive("ahk_id" id) {
      WinGet, state, MinMax, ahk_id %id%
      if (state = -1) {
        WinRestore, ahk_id %id%
      }
    } else {
      WinActivate, ahk_id %id%
    }
    If (procName = "VSCode tab") {
      Acc_Get("Object",window.accPath,,"ahk_id" id).accDoDefaultAction(0)
    }
  }
}

;------------------------------------------------------------5----------
;
; Add window list to listview
;
DrawListView(windows, iconArray) {
  Global switcher_id, fileList, hlv, compact, allRowCount
  static max_width := 50 ; set max width for icon/number column, will adjust itself if needed
  , LVM_GETCOLUMNWIDTH := 0x101d
  LV_GetText(selectedRow, LV_GetNext(),3)
  GuiControl, -Redraw, list
  LV_Delete()
  row_num := 1
  for i, e in windows { 
    if (i < startFrom)
      continue
    if iconArray.HasKey(Format("{:s}",e.id)) {
      icon := iconArray[e.id].icon
      arr := [icon, row_num, e.procName, e.title, e.id]
      LV_Add(arr*)
      row_num++
    }
  }
  LV_Modify(1, "Select")
  ListLines, Off
  loop % LV_GetCount() {
    LV_GetText(r,A_Index,3)
    if (r = selectedRow) {
      LV_Modify(A_Index,"Select Vis")
      break
    }
  }
  ListLines, On
  LV_ModifyCol(1, "Auto")
  ; keep the icon/number column width the same as it was at 
  ; the start of a search, while allowing it to grow if needed
  SendMessage, LVM_GETCOLUMNWIDTH, 0, 0, SysListView321, ahk_id %switcher_id%
  col_width := ErrorLevel
  OutputDebug, % col_width "`n"
  if (col_width != "FAIL") {
    if (col_width > max_width) {
      max_width := col_width
    }
    if (col_width < max_width) {
      LV_ModifyCol(1, max_width)
    }
  }

  LV_ModifyCol(2,110)
  GuiControl, +Redraw, list
  totalRows := LV_GetCount()
  LV_Modify(1, "Select Vis")
  Resize()
  initialLoadComplete := true ; set flag to enable ShowSwitcher hotkey
}

; Portions of this from the example in the AutoHotkey help-file
generateIconList(windows) {
  global compact, fileList
  static IconArray := Object(), IconHandles := Object()
  , WS_EX_TOOLWINDOW = 0x80
  , WS_EX_APPWINDOW = 0x40000
  , GW_OWNER = 4
  , WM_GETICON := 0x7F
  ; http://msdn.microsoft.com/en-us/library/windows/desktop/ms632625(v=vs.85).aspx
  , ICON_BIG := 1
  , ICON_SMALL2 := 2
  , ICON_SMALL := 0
  iconCount = 0
  imageListID := IL_Create(windows.Count(), 1, compact ? 0 : 1)
    For idx, window in windows {
      wid := window.id
      title := window.title
      procName := window.procName
      tab := window.num
      removed := false
      WinGet, style, ExStyle, ahk_id %wid%
      isAppWindow := (style & WS_EX_APPWINDOW)
      isToolWindow := (style & WS_EX_TOOLWINDOW)
      iconId := Format("{:s}", window.id)
      ownerHwnd := DllCall("GetWindow", "uint", wid, "uint", GW_OWNER)
      iconNumber := ""
      if (!IconHandles.HasKey(iconId)) {
          if window.HasKey("path") {
            FileName := window.path
            ; Calculate buffer size required for SHFILEINFO structure.
            sfi_size := A_PtrSize + 8 + (A_IsUnicode ? 680 : 340)
            VarSetCapacity(sfi, sfi_size)
            SplitPath, FileName,,, FileExt ; Get the file's extension.
            for _, hex in [0x100, 0x101] {
              found := DllCall("Shell32\SHGetFileInfo" . (A_IsUnicode ? "W":"A"), "Str", FileName
              , "UInt", 0, "Ptr", &sfi, "UInt", sfi_size, "UInt", hex)
              if found
                Break
            }  ; 0x101 is SHGFI_ICON+SHGFI_SMALLICON
            if !found {
              IconHandles[iconId] := 0
            } else {
              IconHandles[iconId] := NumGet(sfi, 0)
            }
          } else if (procName ~= "(Chrome|Firefox|Vivaldi) tab" || isAppWindow || ( !ownerHwnd and !isToolWindow )) {
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
              IconHandles[iconId] := iconHandle
          }
      }
      iconHandle := IconHandles[iconId] || 9999999
      iconNumber := DllCall("ImageList_ReplaceIcon", UInt, imageListID, Int, -1, UInt, IconHandles[iconId]) + 1
      window.icon := iconHandle
      if (removed || iconNumber < 1) {
        removedRows.Push(wid)
      } else {
        iconCount+=1
        IconArray[iconId] := {"icon":"Icon" . iconNumber, "num": iconNumber} 
      }
    }
    LV_SetImageList(imageListID, 1)
  return IconArray
}

chromiumGetTabNames(debugPort) {
  try {
    whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    whr.Open("GET", "http://127.0.0.1:" debugPort "/json/list", true)
    whr.Send()
    whr.WaitForResponse(2)
    v := whr.ResponseText
    obj := JSON.Load(v)
    filtered := []
    for _, o in obj {
        if (o.type = "page") {
           filtered.Push(o) 
        }
    }
    return filtered
  } catch e {
    OutputDebug, % e
  }
}

chromiumFocusTab(debugPort, title, id) {
  try {
    whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    whr.Open("GET", "http://127.0.0.1:" debugPort "/json/activate/" id, true)
    whr.Send()
    whr.WaitForResponse(2)
    WinWait, % title, , 2
    WinActivate
    ControlFocus, ahk_class Chrome_WidgetWin_1
  } catch e {
    OutputDebug, % e
  }
}

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

FadeHide() {
  static func := Func("FadeGui").Bind("out")
  WinSet, AlwaysOnTop, Off, ahk_id %switcher_id%
  SetTimer, % func, -1
}

FadeGui(in_or_out := "in") {
  static max_opacity := 225, step := 25, delay := 1
  ListLines, Off
  if (in_or_out = "out") {
    opacity := max_opacity
    WinSet, Transparent, % max_opacity, ahk_id %switcher_id%
    while (opacity > 0) {
      opacity -= step
      WinSet, Transparent, % opacity, ahk_id %switcher_id%
      Sleep delay
    }
    Gui, Hide
  } else {
    opacity := 0
    Gui, Show, NoActivate, Window Switcher
    WinSet, AlwaysOnTop, On, ahk_id %switcher_id%
    WinSet, Transparent, 0, ahk_id %switcher_id%
    while (opacity < max_opacity) {
      opacity += step
      WinSet, Transparent, % opacity, ahk_id %switcher_id%
      Sleep delay
    }
    WinGetPos, , , w, h, ahk_id %switcher_id%
    WinSet, Region , 0-0 w%w% h%h% R15-15, ahk_id %switcher_id% ; rounded corners
  }
}

WM_LBUTTONDOWN() {

  global isResizing, resizeBorder, Windows
  static topBorder := 29
  ListLines, Off
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
  ListLines, Off
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
  } 
}

InRange(val, start, count) {
  return val >= start && val <= start + count
}

WM_MOUSEMOVE() {
  global resizeBorder, isResizing, borderOffset
  static minWidth := 200
  , minHeight := 150
  ListLines, Off
  if !A_Gui
    return
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
    Resize(newWidth,newHeight, winWidth)
  }
}

Resize(width := "", height := "", last_width := 0) {
  if (!width || !height) {
    WinGetPos,,, width, height, % "ahk_id" switcher_id
  }
  if !last_width
    last_width := width
  w_diff := width - last_width
  ControlGetPos, CurrentRow_x, , w, , Static3
  WinSet, Region , 0-0 w%width% h%height% R15-15, ahk_id %switcher_id%
  GuiControl, Move, list, % "w" (hideScrollBars ? width + 20 : width - 20) " h" height - 50
  GuiControl, Move, Edit1, % "w" width - 160 
  if w_diff
    GuiControl, Move, CurrentRow, % "x" CurrentRow_x + w_diff
  if (c := GetColumnWidths()) {
    LV_ModifyCol(3, (width - (c.1 + c.2)) - (hideScrollBars ? 1 : 41))
  }
}

GetColumnWidths(control := "") {
  static LVM_GETCOLUMNWIDTH := 0x101D
  if !control
    control := "SysListView321"
  result := []
  loop % LV_GetCount("Column") {
    SendMessage, LVM_GETCOLUMNWIDTH, A_Index - 1, 0, % control, ahk_id %switcher_id%
    if ErrorLevel == "FAIL"
      return 0
    result.Push(ErrorLevel)
  }
  return result
}

SetWindowPosition(hwnd, x := "", y := "", w := "", h := "") {
  ; global hLV
  DllCall("SetWindowPos","uint",hwnd,"uint",0
    ,"int",x,"int",y,"int",w,"int",h
  ,"uint",0x40)
}

GetProcessName(wid) {
  WinGet, name, ProcessName, ahk_id %wid%
  return StrSplit(name, ".").1
}

; from https://github.com/Chunjee/string-similarity.ahk/

class stringsimilarity {

	; --- Static Methods ---

	compareTwoStrings(param_string1, param_string2) {
		;Sørensen-Dice coefficient
		savedBatchLines := A_BatchLines
		setBatchLines, -1

		vCount := 0
		;make default key value 0 instead of a blank string
		l_arr := {base:{__Get:func("abs").bind(0)}}
		loop, % vCount1 := strLen(param_string1) - 1 {
			l_arr["z" subStr(param_string1, A_Index, 2)]++
		}
		loop, % vCount2 := strLen(param_string2) - 1 {
			if (l_arr["z" subStr(param_string2, A_Index, 2)] > 0) {
				l_arr["z" subStr(param_string2, A_Index, 2)]--
				vCount++
			}
		}
		vSDC := round((2 * vCount) / (vCount1 + vCount2), 2)
		;round to 0 if less than 0.005
		if (!vSDC || vSDC < 0.005) {
			return 0
		}
		; return 1 if rounded to 1.00
		if (vSDC = 1) {
			return 1
		}
		setBatchLines, % savedBatchLines
		return vSDC
	}


	findBestMatch(param_string, param_array, param_key) {
		savedBatchLines := A_BatchLines
		setBatchLines, -1
		if (!isObject(param_array)) {
			setBatchLines, % savedBatchLines
			return false
		}

		l_arr := []

		; Score each option and save into a new array
		for key, value in param_array {
      if (param_key)
        value := value[param_key]
			l_arr[A_Index, "rating"] := this.compareTwoStrings(param_string, value)
			l_arr[A_Index, "target"] := value
		}

		;sort the rated array
		l_sortedArray := this._internal_Sort2DArrayFast(l_arr, "rating")
		; create the besMatch property and final object
		l_object := {bestMatch: l_sortedArray[1].clone(), ratings: l_sortedArray}
		setBatchLines, % savedBatchLines
		return l_object
	}


	simpleBestMatch(param_string, param_array) {
		if (!IsObject(param_array)) {
			return false
		}
		l_highestRating := 0

		for key, value in param_array {
			l_rating := this.compareTwoStrings(param_string, value)
			if (l_highestRating < l_rating) {
				l_highestRating := l_rating
				l_bestMatchValue := value
			}
		}
		return l_bestMatchValue
	}



	_internal_Sort2DArrayFast(param_arr, param_key)
	{
		for index, obj in param_arr {
			out .= obj[param_key] "+" index "|"
			; "+" allows for sort to work with just the value
			; out will look like:   value+index|value+index|
		}

		v := param_arr[param_arr.minIndex(), param_key]
		if v is number
			type := " N "
		out := subStr(out, 1, strLen(out) -1) ; remove trailing |
		sort, out, % "D| " type  " R"
		l_arr := []
		loop, parse, out, |
			l_arr.push(param_arr[subStr(A_LoopField, inStr(A_LoopField, "+") + 1)])
		return l_arr
	}
}

/* ObjectSort() by bichlepa
* 
* Description:
*    Reads content of an object and returns a sorted array
* 
* Parameters:
*    obj:              Object which will be sorted
*    keyName:          [optional] 
*                      Omit it if you want to sort a array of strings, numbers etc.
*                      If you have an array of objects, specify here the key by which contents the object will be sorted.
*    callBackFunction: [optional] Use it if you want to have custom sort rules.
*                      The function will be called once for each value. It must return a number or string.
*    reverse:          [optional] Pass true if the result array should be reversed
*/
objectSort(obj, keyName="", callbackFunc="", reverse=false)
{
	temp := Object()
	sorted := Object() ;Return value
	
	for oneKey, oneValue in obj
	{
		;Get the value by which it will be sorted
		if keyname
			value := oneValue[keyName]
		else
			value := oneValue
		
		;If there is a callback function, call it. The value is the key of the temporary list.
		if (callbackFunc)
			tempKey := %callbackFunc%(value)
		else
			tempKey := value
		
		;Insert the value in the temporary object.
		;It may happen that some values are equal therefore we put the values in an array.
		if not isObject(temp[tempKey])
			temp[tempKey] := []
		temp[tempKey].push(oneValue)
	}
	
	;Now loop throuth the temporary list. AutoHotkey sorts them for us.
	for oneTempKey, oneValueList in temp
	{
		for oneValueIndex, oneValue in oneValueList
		{
			;And add the values to the result list
			if (reverse)
				sorted.insertAt(1,oneValue)
			else
				sorted.push(oneValue)
		}
	}
	
	return sorted
}
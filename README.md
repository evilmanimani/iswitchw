# iswitchw 
## fast keyboard-driven window switching via AutoHotKey

When iswitchw is triggered, the titles of all visible windows are shown in a
popup. Start typing to narrow possible matches -- hit enter at any point to
activate the top match. Matches are narrowed using an approximate/'fuzzy'
filtering method similar to tools like [Ido][ido] and [CtrlP][ctrlp], filtering
is presently handled by tcmatch.dll, originally an extended search module for
TotalCommander, it supports multiple search modes, including Regex, fuzzy search,
and Pinyin. See documentation in the .ahk file for further info.

Built and tested using AutoHotkeyL v1.1.36.02 on Windows 10 (x64), confirmed working
on Windows 11 (x64) as well.

![screenshot](https://user-images.githubusercontent.com/24360832/116187876-3f996c00-a6db-11eb-888a-b2f2303d201d.png)

### Usage

* `Capslock` activates iswitchw
* `Esc` `Ctrl + [` cancels at any time
* `Tab/Shift + Tab` `Down/Up` `Ctrl + J/K` navigate next/previous row
* `Left/Right` arrow keys move the insert cursor in the search box
* `Home/End` jump to the top/bottom of list
* `PgDn/PgUp` `Ctrl + d/u` jumps down/up the list 4 rows at a time
* `Ctrl + Delete/Backspace/W` removes a word from the search, or,
  if there's no further matches or only a single match: clear the input
* `Ctrl + Left/Right` arrow keys skip forward/backward by the word
* `Win + 0-9` focuses the corresponding tab
* `1-300` hotstrings to focus any tab, enter the row number followed by
  a space.
* Click a title to activate a window with the mouse
* Any other typing should be passed through to the search
* Start a search string with `?` to search using RegEX
* Configure watched file folders or shortcuts to display in results

Chrome and Firefox tabs will appear separately in the list. To enable support for
Chrome & Vivaldi, enable the remote debugging protocol by creating a new browser shortcut
and append the following to the target field:
`--remote-debugging-port=9222`
you can set the port number to whatever you with, however ensure that they're set to 
different ports for each browser, then ensure you change the `chromeDebugPort` and/or
`vivaldiDebugPort` in iswitchw.ahk's configuration section to match.

Firefox tab support is handled by Accv2.ahk and should work out of the box, though it can
have a tendency to break after any major UI changes. I don't use it myself so please open
an issue if that occurs.

By default, iswitchw is restricted to a single instance and hides itself from
the tray. Run the script again at any time to replace the running instance. If
you want to quit the script entirely, activate iswitchw with `Win + Space` and
then press `Alt + F4`.

If you want iswitchw to run when Windows starts, make a shortcut to the
iswitchw.ahk file in the folder `%APPDATA%\Microsoft\Windows\Start
Menu\Programs\Startup`. See [here][start-on-boot] also.

### Options

User configurable options are presented at the top of the ahk script.

### Todo

* [ ] Add a config screen for options, hotkeys, etc.
* [ ] See if it's possible to have browser tabs appear in MRU order?
* [ ] Maybe AHKv2 rewrite in the future? We'll see...

### History

This fork is a significant departure from previous versions, aside from portions of the function that handles drawing the list view, this is a complete rewrite. See [[link][hist]] for previous fork history.

Original inspiration provided by the creators of the [iswitchb][iswitchb]
package for the Emacs editor.

[ido]: http://www.emacswiki.org/emacs/InteractivelyDoThings
[ctrlp]: http://kien.github.io/ctrlp.vim/
[start-on-boot]: http://windows.microsoft.com/en-us/windows-vista/run-a-program-automatically-when-windows-starts
[iswitchb]: http://www.gnu.org/software/emacs/manual/html_node/emacs/Iswitchb.html
[hist]: https://github.com/tvjg/iswitchw
[debug]: https://stackoverflow.com/questions/51563287/how-to-make-chrome-always-launch-with-remote-debugging-port-flag

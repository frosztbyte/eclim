" Author:  Kannan Rajah
"
" License: {{{
"
" Copyright (C) 2014  Eric Van Dewoestine
"
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.
"
" }}}

" Script Variables {{{
" Regex used to search for any object ID
" Use a non greedy search to match the closing parenthesis using \{-}
let s:id_search_by_regex = '(id=.\{-})'

" Pattern used to search for specific object ID
let s:id_search_by_value = '(id=<value>)'

" TODO This needs to be maintained per thread. We can use debug session id +
" thread id as key
let s:debug_step_prev_file = ''
let s:debug_step_prev_line = ''

let s:debug_line_sign = 'eclim_debug_line'
let s:breakpoint_sign_name = 'breakpoint'

let s:variable_win_name = 'Debug Variables'
let s:thread_win_name = 'Debug Threads'

let s:command_start =
  \ '-command java_debug_start -p "<project>" ' .
  \ '-h "<host>" -n "<port>" -v "<vim_servername>"'

let s:command_stop = '-command java_debug_stop'

let s:command_session_suspend = '-command java_debug_thread_suspend'
let s:command_thread_suspend = '-command java_debug_thread_suspend ' .
  \ '-t "<thread_id>"'

let s:command_session_resume = '-command java_debug_thread_resume'
let s:command_thread_resume = '-command java_debug_thread_resume ' .
  \ '-t "<thread_id>"'

let s:command_breakpoint_toggle =
  \ '-command java_debug_breakpoint_toggle ' .
  \ '-p "<project>" -f "<file>" -l "<line>"'

let s:command_breakpoint_add =
  \ '-command java_debug_breakpoint_add ' .
  \ '-p "<project>" -f "<file>" -l "<line>"'

let s:command_breakpoint_get_all = '-command java_debug_breakpoint_get'
let s:command_breakpoint_get =
  \ '-command java_debug_breakpoint_get -f "<file>"'

let s:command_breakpoint_remove_all = '-command java_debug_breakpoint_remove'
let s:command_breakpoint_remove_file =
  \ '-command java_debug_breakpoint_remove -f "<file>"'
let s:command_breakpoint_remove =
  \ '-command java_debug_breakpoint_remove -f "<file>" -l "<line>"'

let s:command_step = '-command java_debug_step -a "<action>"'
let s:command_step_thread = '-command java_debug_step -a "<action>" -t "<thread_id>"'

let s:command_status = '-command java_debug_status'

let s:command_variable_expand = '-command java_debug_variable_expand -v "<value_id>"'
" }}}

function! eclim#java#debug#DefineStatusWinCommands() " {{{
  " Defines commands that are applicable in any of the debug status windows.
  if !exists(":JavaDebugStop")
    command -nargs=0 -buffer JavaDebugStop :call eclim#java#debug#DebugStop()
  endif

  if !exists(":JavaDebugThreadSuspendAll")
    command -nargs=0 -buffer JavaDebugThreadSuspendAll
      \ :call eclim#java#debug#DebugThreadSuspendAll()
  endif

  if !exists(":JavaDebugThreadResume")
    command -nargs=0 -buffer JavaDebugThreadResume
      \ :call eclim#java#debug#DebugThreadResume()
  endif

  if !exists(":JavaDebugThreadResumeAll")
    command -nargs=0 -buffer JavaDebugThreadResumeAll
      \ :call eclim#java#debug#DebugThreadResumeAll()
  endif

  if !exists(":JavaDebugStep")
    command -nargs=+ -buffer JavaDebugStep :call eclim#java#debug#Step(<f-args>)
  endif

  if !exists(":JavaDebugStatus")
    command -nargs=0 -buffer JavaDebugStatus
      \ :call eclim#java#debug#Status()
  endif

  if !exists(":JavaDebugGoToFile")
    command -nargs=+ JavaDebugGoToFile :call eclim#java#debug#GoToFile(<f-args>)
  endif

  if !exists(":JavaDebugSessionTerminated")
    command -nargs=0 JavaDebugSessionTerminated
      \ :call eclim#java#debug#SessionTerminated()
  endif

  if !exists(":JavaDebugThreadViewUpdate")
    command -nargs=+ JavaDebugThreadViewUpdate
      \ :call eclim#java#debug#ThreadViewUpdate(<f-args>)
  endif

  if !exists(":JavaDebugVariableViewUpdate")
    command -nargs=+ JavaDebugVariableViewUpdate
      \ :call eclim#java#debug#VariableViewUpdate(<f-args>)
  endif
endfunction " }}}

function! eclim#java#debug#DefineThreadWinCommands() " {{{
  " Defines commands that are applicable only in the thread window.
  if !exists(":JavaDebugThreadSuspend")
    command -nargs=0 -buffer JavaDebugThreadSuspend
      \ :call eclim#java#debug#DebugThreadSuspend()
  endif
endfunction " }}}

function! eclim#java#debug#DefineVariableWinCommands() " {{{
  " Defines commands that are applicable only in the variable window.
  if !exists(":JavaDebugVariableExpand")
    command -nargs=0 -buffer JavaDebugVariableExpand
      \ :call eclim#java#debug#VariableExpand()

    nnoremap <buffer> <silent> <CR> :call eclim#java#debug#VariableExpand()<CR>
  endif
endfunction " }}}

function! eclim#java#debug#DefineBreakpointWinCommands() " {{{
  " Defines commands that are applicable only in the breakpoint window.
  if !exists(":JavaDebugBreakpointToggle")
    command -nargs=0 -buffer JavaDebugBreakpointToggle
      \ :call eclim#java#debug#BreakpointToggle()
  endif
endfunction " }}}

function! eclim#java#debug#DebugStart(...) " {{{
  if !eclim#project#util#IsCurrentFileInProject()
    return
  endif

  if v:servername == ''
    call eclim#util#EchoError(
      \ "Error: To debug, VIM must be running in server mode.\n" .
      \ "Example: vim --servername <name>")
    return
  endif

  if a:0 != 2
    call eclim#util#EchoError(
      \ "Please specify the host and port of the java process to connect to.\n" .
      \ "Example: JavaDebugStart locahost 1044")
    return
  endif

  let host = a:1
  let port = a:2

  if port !~ '^\d\+'
    call eclim#util#EchoError("Error: Please specify a valid port number.")
    return
  endif

  call eclim#display#signs#DefineLineHL(
    \ s:debug_line_sign, g:EclimJavaDebugLineHighlight)

  let project = eclim#project#util#GetCurrentProjectName()
  let command = s:command_start
  let command = substitute(command, '<project>', project, '')
  let command = substitute(command, '<host>', host, '')
  let command = substitute(command, '<port>', port, '')
  let command = substitute(command, '<vim_servername>', v:servername, '')
  let result = eclim#Execute(command)

  call eclim#util#Echo(result)
endfunction " }}}

function! eclim#java#debug#DebugStop() " {{{
  let command = s:command_stop
  let result = eclim#Execute(command)

  " Auto close the debug status window
  call eclim#util#DeleteBuffer(s:variable_win_name)
  call eclim#util#DeleteBuffer(s:thread_win_name)

  " Remove the sign from previous location
  if (s:debug_step_prev_line != '' && s:debug_step_prev_file != '')
    call eclim#display#signs#UnplaceFromBuffer(s:debug_step_prev_line,
      \ bufnr(s:debug_step_prev_file))
  endif

  let s:debug_step_prev_line = ''
  let s:debug_step_prev_file = ''

  call eclim#util#Echo(result)
endfunction " }}}

function! eclim#java#debug#DebugThreadSuspend() " {{{
  " Check if we are in the right window
  if (bufname("%") != s:thread_win_name)
    call eclim#util#EchoError("Thread suspend command not applicable in this window.")
    return
  endif

  " Suspends thread under cursor.
  let thread_id = eclim#java#debug#GetIdUnderCursor()
  if thread_id == ""
    call eclim#util#Echo("No valid thread found under cursor")
    return
  endif

  let command = s:command_thread_suspend
  let command = substitute(command, '<thread_id>', thread_id, '')

  call eclim#util#Echo(eclim#Execute(command))
endfunction " }}}

function! eclim#java#debug#DebugThreadSuspendAll() " {{{
  " Suspends all threads.
  let command = s:command_session_suspend
  call eclim#util#Echo(eclim#Execute(command))
endfunction " }}}

function! eclim#java#debug#DebugThreadResume() " {{{
  " Resume a single thread.
  " Even if thread_id is empty, invoke resume. If there is atleast one
  " suspended thread, then the server could resume that. If not, it will
  " re-run a message.
  " Check if we are in the right window
  if (bufname("%") == s:thread_win_name)
    let thread_id = eclim#java#debug#GetIdUnderCursor()
  else
    let thread_id = ""
  endif

  let command = s:command_thread_resume
  let command = substitute(command, '<thread_id>', thread_id, '')

  let result = eclim#Execute(command)

  " Remove the sign from previous location. This is needed here even though it
  " is done in GoToFile function. There may be a time gap until the next
  " breakpoint is hit or the program terminates. We don't want to highlight
  " the current line until then.
  if (s:debug_step_prev_line != '' && s:debug_step_prev_file != '')
    call eclim#display#signs#UnplaceFromBuffer(s:debug_step_prev_line,
      \ bufnr(s:debug_step_prev_file))
  endif

  call eclim#util#Echo(result)
endfunction " }}}

function! eclim#java#debug#DebugThreadResumeAll() " {{{
  " Resumes all threads.
  let command = s:command_session_resume
  let result = eclim#Execute(command)

  " Remove the sign from previous location. This is needed here even though it
  " is done in GoToFile function. There may be a time gap until the next
  " breakpoint is hit or the program terminates. We don't want to highlight
  " the current line until then.
  if (s:debug_step_prev_line != '' && s:debug_step_prev_file != '')
    call eclim#display#signs#UnplaceFromBuffer(s:debug_step_prev_line,
      \ bufnr(s:debug_step_prev_file))
  endif

  call eclim#util#Echo(result)
endfunction " }}}

function! eclim#java#debug#BreakpointAdd() " {{{
  " Adds breakpoint for current cursor position.
  if !eclim#project#util#IsCurrentFileInProject()
    return
  endif

  let project = eclim#project#util#GetCurrentProjectName()
  let file = eclim#lang#SilentUpdate()
  let line = line('.')

  let command = s:command_breakpoint_add
  let command = substitute(command, '<project>', project, '')
  let command = substitute(command, '<file>', file, '')
  let command = substitute(command, '<line>', line, '')

  call eclim#util#Echo(eclim#Execute(command))
endfunction " }}}

function! eclim#java#debug#BreakpointGet() " {{{
  " Displays breakpoints present in file loaded in current window.
  if !eclim#project#util#IsCurrentFileInProject()
    return
  endif

  let file = expand('%:p')

  let command = s:command_breakpoint_get
  let command = substitute(command, '<file>', file, '')

  call eclim#java#debug#DisplayPositions(eclim#Execute(command))

endfunction " }}}

function! eclim#java#debug#BreakpointGetAll() " {{{
  " Displays all breakpoints in the workspace.
  let command = s:command_breakpoint_get_all
  call eclim#java#debug#DisplayPositions(eclim#Execute(command))
endfunction " }}}

function! eclim#java#debug#BreakpointRemove() " {{{
  " Removes breakpoint defined under the cursor if present.
  if !eclim#project#util#IsCurrentFileInProject()
    return
  endif

  let file = eclim#lang#SilentUpdate()
  let line = line('.')

  let command = s:command_breakpoint_remove
  let command = substitute(command, '<file>', file, '')
  let command = substitute(command, '<line>', line, '')

  call eclim#util#Echo(eclim#Execute(command))
endfunction " }}}

function! eclim#java#debug#BreakpointRemoveFile() " {{{
  " Removes all breakpoints defined in file loaded in current
  " window.
  if !eclim#project#util#IsCurrentFileInProject()
    return
  endif

  let file = expand('%:p')

  let command = s:command_breakpoint_remove_file
  let command = substitute(command, '<file>', file, '')

  call eclim#util#Echo(eclim#Execute(command))
endfunction " }}}

function! eclim#java#debug#BreakpointRemoveAll() " {{{
  " Removes all breakpoints from workspace.
  let command = s:command_breakpoint_remove_all
  call eclim#util#Echo(eclim#Execute(command))
endfunction " }}}

function! eclim#java#debug#DisplayPositions(results) " {{{
  if (type(a:results) != g:LIST_TYPE)
    return
  endif

  if empty(a:results)
    echo "No breakpoints"
    return
  endif

  call eclim#util#SetLocationList(eclim#util#ParseLocationEntries(a:results))
  exec 'lopen ' . g:EclimLocationListHeight
endfunction " }}}

function! eclim#java#debug#BreakpointToggle() " {{{
  let project = eclim#project#util#GetCurrentProjectName()
  let file = eclim#lang#SilentUpdate()
  let line = line('.')

  let command = s:command_breakpoint_toggle
  let command = substitute(command, '<project>', project, '')
  let command = substitute(command, '<file>', file, '')
  let command = substitute(command, '<line>', line, '')

  let result = eclim#Execute(command)

  call eclim#display#signs#Define(s:breakpoint_sign_name, '*', '')

  if (result == "1")
    call eclim#display#signs#Place(s:breakpoint_sign_name, line)
    call eclim#util#Echo("Breakpoint added")
  else
    call eclim#display#signs#Unplace(line)
    call eclim#util#Echo("Breakpoint removed")
  endif

endfunction " }}}

function! eclim#java#debug#Step(action) " {{{
  if (bufname("%") == s:thread_win_name)
    let thread_id = eclim#java#debug#GetIdUnderCursor()
  else
    let thread_id = ""
  endif

  if thread_id != ""
    let command = s:command_step_thread
    let command = substitute(command, '<thread_id>', thread_id, '')
  else
    " Step through the currently stepping thread, if one exists
    let command = s:command_step
  endif

  let command = substitute(command, '<action>', a:action, '')
  let result = eclim#Execute(command)

  if type(result) == g:STRING_TYPE
    call eclim#util#Echo(result)
  endif
endfunction " }}}

function! eclim#java#debug#Status() " {{{
  let command = s:command_status
  let results = eclim#Execute(command)

  if type(results) != g:DICT_TYPE
    return
  endif

  if has_key(results, 'state')
    let state = [results.state]
  else
    let state = []
  endif

  if has_key(results, 'threads')
    let threads = results.threads
  else
    let threads = []
  endif

  if has_key(results, 'variables')
    let vars = results.variables
  else
    let vars = []
  endif

  call eclim#java#debug#CreateStatusWindow(state + threads, vars)
endfunction " }}}

function! eclim#java#debug#CreateStatusWindow(threads, vars) " {{{
  " Creates the debug status windows if they do not already exist.
  " The newly created windows are initialized with given content.

  " Store current position and restore in the end so that creation of new
  " window does not end up moving the cursor
  let cur_bufnr = bufnr('%')
  let cur_line = line('.')
  let cur_col = col('.')

  let thread_win_opts = {'orientation': 'horizontal'}
  call eclim#util#TempWindow(
    \ s:thread_win_name, a:threads,
    \ thread_win_opts)

  setlocal foldmethod=expr
  setlocal foldexpr=eclim#display#fold#GetTreeFold(v:lnum)
  setlocal foldtext=eclim#display#fold#TreeFoldText()
  " Display the stacktrace of suspended threads
  setlocal foldlevel=5
  " Avoid the ugly - symbol on folded lines
  setlocal fillchars="fold:\ "
  setlocal nonu
  call eclim#java#debug#DefineThreadWinCommands()
  call eclim#java#debug#DefineStatusWinCommands()

  let var_win_opts = {'orientation': g:EclimJavaDebugStatusWinOrientation,
    \ 'width': g:EclimJavaDebugStatusWinWidth,
    \ 'height': g:EclimJavaDebugStatusWinHeight}
  call eclim#util#TempWindow(
    \ s:variable_win_name, a:vars,
    \ var_win_opts)

  setlocal foldmethod=expr
  setlocal foldexpr=eclim#display#fold#GetTreeFold(v:lnum)
  setlocal foldtext=eclim#display#fold#TreeFoldText()
  " Avoid the ugly - symbol on folded lines
  setlocal fillchars="fold:\ "
  setlocal nonu
  call eclim#java#debug#DefineVariableWinCommands()
  call eclim#java#debug#DefineStatusWinCommands()

  " Restore position
  call eclim#util#GoToBufferWindow(cur_bufnr)
  call cursor(cur_line, cur_col)
  redraw!
endfunction " }}}

function! eclim#java#debug#VariableExpand() " {{{
  " Expands the variable value under cursor and adds the child variables under
  " it in the tree.

  " Check if we are in the right window
  if (bufname("%") != s:variable_win_name)
    call eclim#util#EchoError("Variable expand command not applicable in this window.")
    return
  endif

  " Return if the current line does not contain any fold
  if (matchstr(getline(line('.')), "▸\\|▾") == "")
    return
  endif

  " Make the buffer writable
  setlocal modifiable
  setlocal noreadonly

  let id = eclim#java#debug#GetIdUnderCursor()
  if (id != "")
    let command = s:command_variable_expand
    let command = substitute(command, '<value_id>', id, '')

    let results = eclim#Execute(command)
    if (type(results) == g:LIST_TYPE && len(results) > 0)
      call append(line('.'), results)

      " Remove the placeholder line used to get folding to work.
      " But first unfold.
      exec "normal! za"

      let cur_line = line('.')
      let cur_col = col('.')
      
      let empty_line = line('.') + len(results) + 1
      exec 'silent ' . empty_line . ',' . empty_line . 'd'

      " Restore cursor position
      call cursor(cur_line, cur_col)
    else
      exec "normal! za"
    endif
  else
    exec "normal! za"
  endif

  " Restore settings
  setlocal nomodified
  setlocal nomodifiable
  setlocal readonly

endfunction " }}}

function! eclim#java#debug#GoToFile(file, line) " {{{
  " Remove the sign from previous location
  if (s:debug_step_prev_line != '' && s:debug_step_prev_file != '')
    call eclim#display#signs#UnplaceFromBuffer(s:debug_step_prev_line,
      \ bufnr(s:debug_step_prev_file))
  endif

  " Jump out of status window so that the buffer is opened in the code window
  " If you are in variable window, first go to thread window
  if (bufname("%") == s:thread_win_name)
    call eclim#util#GoToBufferWindow(b:filename)
  endif

  " If you are in thread window, go back to code window
  if (bufname("%") == s:variable_win_name)
    call eclim#util#GoToBufferWindow(b:filename)
    call eclim#util#GoToBufferWindow(b:filename)
  endif

  let s:debug_step_prev_file = a:file
  let s:debug_step_prev_line = a:line
  call eclim#util#GoToBufferWindowOrOpen(a:file, "edit")
  call cursor(a:line, '^')

  " TODO sign id is line number. Can conflict with other signs while
  " unplacing
  call eclim#display#signs#PlaceInBuffer(s:debug_line_sign,
    \ bufnr(a:file), a:line)
endfunction " }}}

function! eclim#java#debug#GetIdUnderCursor() " {{{
  " Returns the object ID under cursor. Object ID is present in the form:
  " (id=X) where X is the ID.
  "
  " An empty string is returned if there is no valid ID.

  " Look for the substring (id=X) where X is the object ID
  let id_substr = matchstr(getline("."), s:id_search_by_regex)
  if (id_substr == "")
    return ""
  else
    let id = split(id_substr, '=')[1]
    " remove the trailing ) character
    return substitute(id, ")","","g")
  endif
endfunction " }}}

function! eclim#java#debug#ThreadViewUpdate(thread_id, kind, value) " {{{
  " Updates the thread window with new thread information.
  " Update kind can be one of the following:
  " a: Add a new thread
  " m: Modify an existing thread
  " r: Remove an existing thread
  
  " Overwrite the message containing the long list of arguments to this function
  call eclim#util#Echo("Refreshing ...")

  " Store current position and restore in the end
  let cur_bufnr = bufnr('%')
  let cur_line = line('.')
  let cur_col = col('.')

  let found = eclim#util#GoToBufferWindow(s:thread_win_name)
  if found == 0
    return
  endif

  setlocal modifiable
  setlocal noreadonly

  let lines = split(a:value, "<eol>")
  if a:kind == 'a'
    " Add to the end
    call append(line('$'), lines)
  else
    " Go to line having the thread id
    call cursor(1, 1)
    let pattern = substitute(s:id_search_by_value, '<value>', a:thread_id, '')
    " Don't wrap search.
    let match_line = search(pattern, 'W')
    if match_line != 0
      " Get the next thread entry. Don't wrap search.
      let next_match_line = search(s:id_search_by_regex, 'W')
      if next_match_line == 0
        let last_line_del = line('$')
      else
        let last_line_del = next_match_line - 1
      endif

      " Delete the desired lines
      let undolevels = &undolevels
      set undolevels=-1
      silent exec match_line . ',' . last_line_del . 'delete _'
      let &undolevels = undolevels

      " In case of modify, add the new values
      if a:kind == 'm'
        call append(match_line - 1, lines)
      endif
    endif
  endif

  setlocal nomodifiable
  setlocal readonly

  " Restore position
  call eclim#util#GoToBufferWindow(cur_bufnr)
  call cursor(cur_line, cur_col)
  call eclim#util#Echo(" ")
endfunction " }}}

function! eclim#java#debug#SessionTerminated() " {{{
  " Cleans up the debug status window.

  " Store current position and restore in the end
  let cur_bufnr = bufnr('%')
  let cur_line = line('.')
  let cur_col = col('.')

  let found = eclim#util#GoToBufferWindow(s:thread_win_name)
  if found == 0
    return
  endif

  setlocal modifiable
  setlocal noreadonly

  " Go to line having the thread id
  call cursor(1, 1)
  s/Connected/Disconnected/

  " Delete any threads that have not been cleared
  silent 2,$delete _

  setlocal nomodifiable
  setlocal readonly

  " Restore position
  call eclim#util#GoToBufferWindow(cur_bufnr)
  call cursor(cur_line, cur_col)

  call eclim#util#TempWindowClear(s:variable_win_name)
endfunction " }}}

function! eclim#java#debug#VariableViewUpdate(value) " {{{
  " Updates the variable window with new set of values.

  call eclim#util#Echo("Refreshing ...")
  call eclim#util#TempWindowClear(s:variable_win_name, split(a:value, "<eol>"))
  call eclim#util#Echo(" ")
endfunction " }}}

" vim:ft=vim:fdm=marker

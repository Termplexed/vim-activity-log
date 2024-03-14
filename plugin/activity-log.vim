" A = = = = = = = = = = = = = = = = .. = = = = = = = = = = = = = = = = = = = A
" XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
" XXw_            <<          activity_log.vim          >>                _wXX
" XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
" : : : . . =   =   =   =   =   =   ::   =   =   =   =   =   =   =   = . . : :
"
" Authors:      Andy Dawson   <andydawson76 AT gmail DOT com>
"               Sofia Cardita <sofiacardita AT gmail DOT com>
"               Termplexed
" Version:      2.0.0
" Licence:      http://www.opensource.org/licenses/mit-license.php
"               The MIT License
" URL:          https://github.com/AD7six/vim-activity-log
"               https://github.com/Termplexed/vim-activity-log
"
" ----------------------------------------------------------------------------
"
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:               D o c u m e n t a t i o n
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"
" The vim  activity log plugin  logs when  you create,  open or write  a file.
"
" This provides you with a detailed log of what you've been up to.  By default
" the activity log files are stored in the ~/activity/ directory and are named
" as follows: YYYY/MM/DD.log.
"
" You can  change the log file locations by defining 'g:activity_log_location'
" to a pattern to suit your needs.  The pattern is passed to strftime().
"
" The files are formatted in the following format:
"
" YYYY-MM-DD HH:MM:SS;<$USER>;
"                     <action>;
"                     /full/path/to/file;
"                     git-branch            (If enabled)
"
" Calling:
"     <leader>s (start_task)
"     <leader>i (interval_task)
"     <leader>c (continue_task)
"     <leader>e (end_task)
"
" appends the current line to the log file resulting in a line as:
"
" YYYY-MM-DD HH:MM:SS;<$USER>;
"                     <action>_task;
"                     /full/path/to/file;
"                     git-branch;            (If enabled)
"                     <current line text>
"
" This allows for finer-grained statistics data for time-tracking reports.
"
" The full date is included to allow concatenation and easier analysis.

" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:                  C h a n g e l o g
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"
" v 2.0.0  -  2024-03-14
" - Fork by Termplexed.
" - Made for LINUX (Due to permission shenanigans).
"                  TODO: Add OS check and ignore if not NIX.
" - Add guard for map: 'g:activity_log_add_map_timelogline'.
" - Add $USER to log.
" - Add ownership check for directory and logfile. (Linux)
" - Change writefile() to append instead of slurping it and writing all.
" - Add try / catch for write.
" - Change some variable names.
" - Fix: add missing semicolons in saving of UnsavedStack.
"

" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:                   Plugin Header
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"
" 'g:loaded_activity_log'
"  Set to 1 when initialization begins,  and 2 when it completes.
if exists('g:loaded_activity_log')
	finish
endif
let g:loaded_activity_log = 1
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:                  Setup Event Group
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"
" Log creating, opening and writing files
augroup ActivityLog
	au BufNewFile * call s:LogAction('create')
	au BufReadPost * call s:LogAction('open')
	au BufWritePost * call s:LogAction('write')
augroup END
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:                  Setup Line Log
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"
" 'g:activity_log_add_map_timelogline'
"
" Log create, interval/break, continue, end task
if get(g:, 'activity_log_add_map_timelogline') == 1
	nmap <silent> <Leader>ls :call TimeLogLine('start_task')<CR>
	nmap <silent> <Leader>le :call TimeLogLine('end_task')<CR>
	nmap <silent> <Leader>li :call TimeLogLine('interval_task')<CR>
	nmap <silent> <Leader>lc :call TimeLogLine('continue_task')<CR>
endif
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:                 Script Variables
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
"
" g:activity_log_location
"
" Where to store activity.  Setting it to '' disables the log,  effectively
" disabling the plugin.
if !exists('g:activity_log_location')
	let g:activity_log_location = '~/activity/%Y/%m/%d.log'
endif

" g:activity_log_append_git_branch
"
" Append the current git branch to log?
if !exists('g:activity_log_append_git_branch')
	if executable('git')
		let g:activity_log_append_git_branch = 1
	else
		let g:activity_log_append_git_branch = 0
	endif
endif

" Stack of unsaved log entries.
" Used to log open and create entries for delayed inserting into the log upon
" write.
let s:UnsavedStack = {}

" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:                Utility Functions
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" These functions are not/should not be directly accessible.
" ----------------------------------------------------------------------------

" ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
" Function: LogAction()
"
" If the action is not 'write' it is cached without writing to the activity
" log. If the file is closed before writing no action is taken. Otherwise,
" when the file is written the cached entry of opening/creating the file is
" also added to the activity log.
"
" If 'g:activity_log_append_git_branch' is true, the git branch at the time of
" writing is appended to the log entry.
function s:LogAction(action)
	if g:activity_log_location == ''
		return
	endif

	let l:file = fnameescape(expand('%:p'))
	if empty(l:file)
		return
	endif
	let l:time = strftime('%Y-%m-%d %H:%M:%S')

	if a:action != 'write'
		if !has_key(s:UnsavedStack, l:file)
			let s:UnsavedStack[l:file] = {}
		endif
		let s:UnsavedStack[l:file][a:action] = l:time
		return
	endif

	if len(s:UnsavedStack) && has_key(s:UnsavedStack, l:file)
		for [s_action, s_time] in items(s:UnsavedStack[l:file])
			let l:message =
				\ s_time   . ';' .
				\ $USER    . ';' .
				\ s_action . ';' .
				\ l:file
			call s:WriteLogAction(l:message)
		endfor
		let s:UnsavedStack[l:file] = {}
	endif

	let l:message =
		\ l:time   . ';' .
		\ $USER    . ';' .
		\ a:action . ';' .
		\ l:file

	if g:activity_log_append_git_branch
		let l:branch = system(
			\ 'cd ' . fnameescape(expand("%:h")) .
			\ '; git rev-parse -q --abbrev-ref HEAD 2> /dev/null'
		\ )
		let l:message =
			\ l:message . ';' .
			\ substitute(l:branch, '\v\C\n$', '', '')
	endif
	call s:WriteLogAction(l:message)
endfunction
" ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
" Function: Fix_perm()
"
" Set directory permission to 700
" Set file permissions to 600
" If $HOME is set, ensure ownership to user. Typically if invoked as root.
function! s:Fix_perm(path)
	if isdirectory($HOME)
		let l:own = trim(system(
			\ 'stat -c "%u:%g" -- ' .. shellescape($HOME))
		\ )
		silent call system(
			\ 'chown ' .. l:own .. ' -- ' .. shellescape(a:path)
		\ )
	endif
	if isdirectory(a:path)
		silent call setfperm(a:path, 'rwx------')
	else
		silent call setfperm(a:path, 'rw-------')
	endif
endfun
" ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
" Function: Mkdir()
"
" Create new directory.
" Ensure ownership.
function! s:Mkdir(dir)
	silent call mkdir(a:dir, 'p')
	if $USER == 'root'
		call s:Fix_perm(a:dir)
	endif
endfun
" ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
" Function: WriteLogAction()
"
" Simple wrapper for appending a message to the correct log file
" Also creates any missing directories as required
function s:WriteLogAction(message)
	let l:file = expand(strftime(g:activity_log_location))
	let l:dir = fnamemodify(l:file, ':p:h')
	let l:log_exist = filereadable(l:file)
	if finddir(l:dir) == ''
		call s:Mkdir(l:dir)
	endif

	try
		call writefile([a:message], l:file, "a")
		if l:log_exist == 0 && $USER == 'root'
			call s:Fix_perm(l:file)
		endif
	catch /^Vim\%((\a\+)\)\=:\(E482\|E475\)/
		echohl WarningMsg
		echomsg "activity-log: failed to write; " . l:file
		echohl ErrorMsg
		echomsg v:exception
		echohl None
	endtry
endfunction
" ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
" Function: TimeLogLine()
"
function TimeLogLine(action)
	let l:file = expand('%:p')
	let l:time = strftime('%Y-%m-%d %H:%M:%S')
	let l:task = getline('.')
	let l:task = substitute(l:task, '  ', '', 'g')
	let l:branch = ''

	if g:activity_log_append_git_branch
		let l:branch = system(
			\ 'cd ' . expand('%:h') . ';' .
			\ 'git branch --no-color 2> /dev/null | ' .
			\ "sed -e '/^[^*]/d'"
		\ )
		if (l:branch =~ "^* ")
			let l:branch = substitute(l:branch, '\* ', '', '')
			let l:branch = substitute(l:branch, '\n', '', '')
		endif
	endif

	let l:message =
		\ l:time   . ';' .
		\ $USER    . ';' .
		\ a:action . ';' .
		\ l:file   . ';' .
		\ l:branch . ';' .
		\ l:task
	call s:WriteLogAction(l:message)
endfunction
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
" Section:                  Plugin Completion
" xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
let g:loaded_activity_log=2
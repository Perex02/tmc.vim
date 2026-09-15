" test/nvim/panel_spec.vim
"
" Assertions for the floating-panel / progress / notification layer.
" Written as a plain driven script rather than a .vader file: the Vader suite
" currently hangs under headless Neovim, and these cases need real timers and a
" real background job, which Vader's synchronous blocks do not accommodate.
"
" Run with:
"   nvim --headless -u NONE -c 'set runtimepath+=.' \
"     -c 'runtime plugin/tmc.vim' -S test/nvim/panel_spec.vim -c 'qa!'
"
" Exits non-zero if anything fails.

let g:fails = []
let g:passes = 0

function! Ok(cond, label) abort
  if a:cond
    let g:passes += 1
  else
    call add(g:fails, a:label)
  endif
endfunction

function! Eq(got, want, label) abort
  call Ok(a:got ==# a:want, a:label . ' (got ' . string(a:got) . ' want ' . string(a:want) . ')')
endfunction

" Panel layout: line 1 is the top padding row, 2 the bar, 3 the current task.
" Helpers keep the assertions below independent of that offset.
function! Line(n) abort
  return get(nvim_buf_get_lines(tmc#panel#bufnr('test'), a:n - 1, a:n, v:false), 0, '')
endfunction
function! BarLine() abort
  return Line(2)
endfunction
function! TaskLine() abort
  return Line(3)
endfunction
function! Body() abort
  return join(nvim_buf_get_lines(tmc#panel#bufnr('test'), 0, -1, v:false), "\n")
endfunction

" Stub vim.notify so notifications are observable.
lua << EOF
_G.tmc_notes = {}
vim.notify = function(msg, level, opts)
  table.insert(_G.tmc_notes, { msg = msg, level = level, title = opts and opts.title })
end
EOF

" ============================================================
" 1. Panel lifecycle: hide must NOT destroy the buffer, and the job's output
"    must keep landing in it while hidden.
" ============================================================
call tmc#panel#open('test', 'Lifecycle')
let s:buf = tmc#panel#bufnr('test')
call Ok(s:buf > 0, 'panel buffer created')
call Ok(tmc#panel#is_visible('test'), 'panel visible after open')

" bufhidden must be 'hide', not 'wipe' -- this is the regression guard
call Eq(nvim_get_option_value('bufhidden', {'buf': s:buf}), 'hide', 'bufhidden is hide')

call tmc#panel#reset('test')
for i in range(100)
  call tmc#panel#append('test', 'line ' . i)
endfor
let s:before = nvim_buf_line_count(s:buf)
call Eq(s:before, 100, 'appended 100 lines')
call Eq(Line(1), '  line 0', 'no blank leading line, and padded')

" minimize
call tmc#panel#hide('test')
call Ok(!tmc#panel#is_visible('test'), 'panel hidden')
call Ok(bufloaded(s:buf) == 1, 'BUFFER SURVIVES HIDE (bufhidden=wipe regression)')
call Eq(tmc#panel#bufnr('test'), s:buf, 'same buffer after hide')

" output continues to accrue while minimized
for i in range(100)
  call tmc#panel#append('test', 'bg ' . i)
endfor
call Eq(nvim_buf_line_count(s:buf), 200, 'output accrued while hidden')

" reopen shows the accrued content
call tmc#panel#show('test')
call Ok(tmc#panel#is_visible('test'), 'panel visible after show')
call Eq(nvim_buf_line_count(s:buf), 200, 'content intact after reopen')
call Eq(Line(nvim_buf_line_count(s:buf)), '  bg 99', 'tail correct after reopen')

" toggle round-trip
call tmc#panel#toggle('test')
call Ok(!tmc#panel#is_visible('test'), 'toggle hides')
call tmc#panel#toggle('test')
call Ok(tmc#panel#is_visible('test'), 'toggle shows')

" ============================================================
" 2. Progress bar rendering
" ============================================================
call tmc#panel#reset('test')
call tmc#progress#start('test', 'Working')

" indeterminate while no percent reported
call Eq(Line(1), '', 'line 1 is the top padding row')
let s:l1 = BarLine()
call Ok(s:l1 =~# '···', 'indeterminate bar when percent unknown')
call Ok(s:l1 !~# '%', 'indeterminate bar shows no percentage')

" task text lands on line 2
call Ok(TaskLine() =~# 'Working', 'task text on the line under the bar')

for s:pair in [[0.0, 0], [0.33, 33], [0.5, 50], [0.58, 58], [1.0, 100]]
  call tmc#progress#update('test', s:pair[0], 'Step ' . s:pair[1])
  let s:bar = BarLine()
  call Ok(s:bar =~# printf('%3d%%$', s:pair[1]), printf('bar shows %d%%', s:pair[1]))
  call Ok(TaskLine() =~# 'Step ' . s:pair[1],
        \ printf('task text updated at %d%%', s:pair[1]))
endfor

" bar geometry: 24 cells, filled proportional
call tmc#progress#update('test', 0.5, 'Half')
let s:bar = BarLine()
call Eq(strchars(substitute(s:bar, '[^█]', '', 'g')), 12, 'half bar = 12 filled cells')
call Eq(strchars(substitute(s:bar, '[^░]', '', 'g')), 12, 'half bar = 12 empty cells')

" header stays 3 lines while output is appended below
call tmc#panel#append('test', ['out A', 'out B'])
call Eq(nvim_buf_line_count(s:buf), 5, 'header 3 + 2 appended')
call Ok(BarLine() =~# '%$', 'bar line untouched by appends')
call Eq(Line(4), '  out A', 'output lands below the header, padded')

" percent_of() parsing
call Eq(tmc#progress#percent_of({'percent-done': 0.42}), 0.42, 'percent_of reads percent-done')
call Eq(tmc#progress#percent_of({}), -1.0, 'percent_of -1 when absent')
call Eq(tmc#progress#percent_of({'percent-done': 'x'}), -1.0, 'percent_of -1 on bad type')

" finish freezes at 100%
call tmc#progress#finish('test', '✅ All 7 tests passed!')
call Ok(BarLine() =~# '100%$', 'finish pins bar at 100%')
call Ok(TaskLine() =~# 'All 7 tests passed', 'summary on task line')

" ============================================================
" 5. Notifications
" ============================================================
call luaeval('(function() _G.tmc_notes = {} end)()')

" visible panel -> suppressed
call tmc#panel#show('test')
call tmc#notify#result('test', 1, 'should be suppressed')
call Eq(luaeval('#_G.tmc_notes'), 0, 'no notification while panel visible')

" hidden panel -> notified
call tmc#panel#hide('test')
call tmc#notify#result('test', 1, '✅ All 7 tests passed!')
call Eq(luaeval('#_G.tmc_notes'), 1, 'notification fired for backgrounded run')
call Eq(luaeval('_G.tmc_notes[1].msg'), '✅ All 7 tests passed!', 'notification message')
call Eq(luaeval('_G.tmc_notes[1].level'), 2, 'pass notifies at INFO')
call Eq(luaeval('_G.tmc_notes[1].title'), 'TMC', 'notification title')

" failure notifies at WARN
call tmc#notify#result('test', 0, '❌ 3 of 12 tests failed')
call Eq(luaeval('_G.tmc_notes[2].level'), 3, 'failure notifies at WARN')

" g:tmc_notify_always overrides the visible-panel suppression
let g:tmc_notify_always = 1
call tmc#panel#show('test')
call tmc#notify#result('test', 1, 'forced')
call Eq(luaeval('#_G.tmc_notes'), 3, 'tmc_notify_always overrides suppression')
unlet g:tmc_notify_always

" ============================================================
" Panel keymaps and multi-kind isolation
" ============================================================
call Ok(!empty(filter(nvim_buf_get_keymap(s:buf, 'n'), 'v:val.lhs ==# "<Esc>"')), '<Esc> mapped in panel')
call Ok(!empty(filter(nvim_buf_get_keymap(s:buf, 'n'), 'v:val.lhs ==# "<C-C>"')), '<C-c> mapped in panel')
call Ok(empty(filter(nvim_buf_get_keymap(s:buf, 'n'), 'v:val.lhs ==# "q"')), 'q NOT mapped (it records macros)')

" a second kind gets its own buffer, so a test run and a submit cannot clash
call tmc#panel#open('submit', 'Submit')
call Ok(tmc#panel#bufnr('submit') != s:buf, 'submit panel has its own buffer')
call tmc#panel#append('submit', 'submit-only line')
call Ok(nvim_buf_get_lines(s:buf, 0, -1, v:false)->index('submit-only line') < 0,
      \ 'panels do not share content')

" Submit mapping is added on demand and cleared by reset
call tmc#panel#map('test', '<CR>', ':echo "x"<CR>')
call Ok(!empty(filter(nvim_buf_get_keymap(s:buf, 'n'), 'v:val.lhs ==# "<CR>"')), '<CR> mapped after offer')
call tmc#panel#reset('test')
call Ok(empty(filter(nvim_buf_get_keymap(s:buf, 'n'), 'v:val.lhs ==# "<CR>"')), 'reset clears <CR> mapping')

" ============================================================
call tmc#panel#hide('test')
call tmc#panel#hide('submit')

" ============================================================
" Background run: a minimized panel must not stop the job
" ============================================================
let g:seen = 0
let g:done = 0

" Start from a clean notification log: earlier sections above may have
" recorded some, and the counts below are absolute.
call luaeval('(function() _G.tmc_notes = {} end)()')

function! OnLine(kind, line) abort
  let g:seen += 1
  try
    let l:obj = json_decode(a:line)
  catch
    call tmc#panel#append(a:kind, 'ℹ️  ' . a:line)
    return
  endtry
  if get(l:obj, 'output-kind', '') ==# 'status-update'
    call tmc#progress#update(a:kind, tmc#progress#percent_of(l:obj), get(l:obj, 'message', ''))
    call tmc#panel#append(a:kind, '⏳ ' . get(l:obj, 'message', ''))
  endif
endfunction

function! OnExit(kind, code) abort
  let g:done = 1
  call tmc#progress#finish(a:kind, '✅ All 5 tests passed!')
  call tmc#notify#result(a:kind, 1, '✅ All 5 tests passed!')
endfunction

" A producer that emits status updates with real percent-done, slowly, and
" sneaks in ANSI escapes + CRs the way the pty-backed submit job does.
let s:prog = join([
      \ 'for i in 1 2 3 4 5 6 7 8; do',
      \ '  printf "{\"output-kind\":\"status-update\",\"percent-done\":0.$((i))5,\"message\":\"step $i\"}\r\n";',
      \ '  printf "\033[32mnoise\033[0m\r\n";',
      \ '  sleep 0.4;',
      \ 'done'], ' ')

call tmc#panel#open('test', 'Background')
call tmc#panel#reset('test')
call tmc#progress#start('test', 'Starting…')
call tmc#job#start('test', ['sh', '-c', s:prog], {
      \ 'meta': {'root': '/tmp/x', 'exercise_id': '42'},
      \ 'on_line': function('OnLine'),
      \ 'on_exit': function('OnExit'),
      \ })

call Ok(tmc#job#is_running('test'), 'job running after start')

" let a little output arrive, then MINIMIZE mid-run
sleep 700m
let s:lines_at_hide = nvim_buf_line_count(tmc#panel#bufnr('test'))
call tmc#panel#hide('test')
call Ok(!tmc#panel#is_visible('test'), 'panel minimized mid-run')
call Ok(tmc#job#is_running('test'), 'JOB STILL RUNNING AFTER MINIMIZE')

" wait for the job to finish while hidden
let s:waited = 0
while !g:done && s:waited < 100
  sleep 100m
  let s:waited += 1
endwhile

call Ok(g:done, 'job completed while minimized')
call Ok(!tmc#panel#is_visible('test'), 'panel stayed hidden')

let s:buf = tmc#panel#bufnr('test')
call Ok(bufloaded(s:buf) == 1, 'buffer survived the whole background run')
let s:lines_at_end = nvim_buf_line_count(s:buf)
call Ok(s:lines_at_end > s:lines_at_hide,
      \ printf('OUTPUT ACCRUED WHILE HIDDEN (%d -> %d)', s:lines_at_hide, s:lines_at_end))
call Ok(g:seen >= 8, printf('all status lines streamed (%d)', g:seen))

" ANSI escapes and CRs were stripped by the job layer
let s:body = join(nvim_buf_get_lines(s:buf, 0, -1, v:false), "\n")
call Ok(s:body !~# '\%x1b', 'ANSI escapes stripped from panel output')
call Ok(s:body !~# '\r', 'carriage returns stripped from panel output')
call Ok(s:body =~# 'noise', 'non-JSON output still shown')
call Ok(s:body =~# 'step 8', 'final status update present')

" notification fired because the panel was hidden
call Ok(luaeval('#_G.tmc_notes') == 1, 'notification fired for background completion')
call Ok(luaeval('_G.tmc_notes[1].msg') =~# 'All 5 tests passed', 'notification carries the summary')

" progress bar advanced from real percent-done, then pinned at 100%
call Ok(BarLine() =~# '100%$', 'bar pinned at 100% on completion')

" reopening shows everything that accrued
call tmc#panel#show('test')
call Ok(tmc#panel#is_visible('test'), 'panel reopens')
call Ok(nvim_buf_line_count(s:buf) == s:lines_at_end, 'content intact on reopen')

" cancel path on a fresh job
let g:done = 0
call tmc#panel#reset('test')
call tmc#progress#start('test', 'Starting…')
call tmc#job#start('test', ['sh', '-c', 'sleep 30'], {
      \ 'on_line': function('OnLine'), 'on_exit': function('OnExit')})
sleep 300m
call Ok(tmc#job#is_running('test'), 'long job running')
call tmc#job#cancel('test')
sleep 500m
call Ok(!tmc#job#is_running('test'), 'cancel stops the job')
call Ok(join(nvim_buf_get_lines(tmc#panel#bufnr('test'), 0, -1, v:false), "\n") =~# 'Cancelled',
      \ 'cancel noted in panel')

" ============================================================
" Focus. The panel's keys are buffer-local, so an unfocused panel can never
" receive them: 'q' and 's' went to the file being edited instead, recording a
" macro and substituting a character in the source.
" ============================================================
" Leave any panel from the sections above, so the :enew below lands in an
" ordinary window rather than inside a floating panel.
for s:k in tmc#panel#kinds()
  call tmc#panel#hide(s:k)
endfor
enew
file spec_userfile.txt
let s:userwin = win_getid()
call Ok(tmc#panel#winid('test') == -1, 'no panel window open before the focus test')

call tmc#panel#open('test', 'Focus')
call Ok(win_getid() == tmc#panel#winid('test'), 'PANEL TAKES FOCUS ON OPEN')
call Ok(win_getid() != s:userwin, 'focus left the file window')

" the panel keys are now actually reachable from the focused window
call Ok(!empty(maparg('<Esc>', 'n')), '<Esc> is reachable in the focused panel')
call Ok(!empty(maparg('<C-c>', 'n')), '<C-c> is reachable in the focused panel')

call tmc#panel#hide('test')
call Ok(win_getid() == s:userwin, 'FOCUS RETURNS TO THE PREVIOUS WINDOW ON MINIMIZE')

" ============================================================
" A focused panel must not absorb typing.
" ============================================================
call tmc#panel#open('test', 'ReadOnly')
let s:buf = tmc#panel#bufnr('test')
call Eq(nvim_get_option_value('modifiable', {'buf': s:buf}), v:false,
      \ 'panel buffer is nomodifiable')

" ...yet every writer still works, by lifting the flag around the write
call tmc#panel#reset('test')
call tmc#panel#append('test', ['a', 'b'])
call Eq(nvim_buf_line_count(s:buf), 2, 'append() writes despite nomodifiable')
call tmc#panel#set_head('test', 0, ['head'])
call Eq(Line(1), '  head', 'set_head() writes')
call tmc#progress#start('test', 'claiming')
call Ok(nvim_buf_line_count(s:buf) >= 3, 'claim_head() writes')
call tmc#progress#stop('test')
call Eq(nvim_get_option_value('modifiable', {'buf': s:buf}), v:false,
      \ 'buffer left nomodifiable after writes')

" ============================================================
" Tail-follow. Now that the panel is focused, forcing the cursor to the last
" line on every append would drag a reader away from the failure they scrolled
" back to look at.
" ============================================================
call tmc#panel#reset('test')
for s:i in range(100)
  call tmc#panel#append('test', 'line ' . s:i)
endfor
let s:win = tmc#panel#winid('test')
call Eq(nvim_win_get_cursor(s:win)[0], 100, 'cursor tails while at the end')

" scroll back, then append: the cursor must stay put
call nvim_win_set_cursor(s:win, [40, 0])
call tmc#panel#append('test', ['more', 'more'])
call Eq(nvim_win_get_cursor(s:win)[0], 40, 'SCROLLED-BACK CURSOR IS NOT DRAGGED TO THE TAIL')

" return to the end, and following resumes
call nvim_win_set_cursor(s:win, [nvim_buf_line_count(s:buf), 0])
call tmc#panel#append('test', ['tail'])
call Eq(nvim_win_get_cursor(s:win)[0], nvim_buf_line_count(s:buf), 'following resumes at the end')

" ============================================================
" Quiet body: the bar carries the task, so status chatter and raw CLI output
" stay out of the results unless g:tmc_panel_verbose is set.
" ============================================================
call tmc#panel#reset('test')
call tmc#progress#start('test', 'start')
if exists('g:tmc_panel_verbose') | unlet g:tmc_panel_verbose | endif

call tmc#panel#log('test', '⏳ Processing submission')
call tmc#panel#log('test', 'ℹ️  raw cli noise')
call tmc#progress#update('test', 0.42, 'Processing submission')
let s:body = join(nvim_buf_get_lines(s:buf, 0, -1, v:false), "\n")
call Ok(s:body !~# '⏳', 'no status chatter in the body by default')
call Ok(s:body !~# 'ℹ️', 'no raw CLI passthrough in the body by default')
call Ok(s:body =~# 'Processing submission', 'task still shown in the header')
call Ok(s:body =~# '42%', 'percentage still advancing in the header')

let g:tmc_panel_verbose = 1
call tmc#panel#log('test', '⏳ Processing submission')
call tmc#panel#log('test', 'ℹ️  raw cli noise')
let s:body = join(nvim_buf_get_lines(s:buf, 0, -1, v:false), "\n")
call Ok(s:body =~# '⏳', 'verbose restores status chatter')
call Ok(s:body =~# 'ℹ️', 'verbose restores raw CLI passthrough')
unlet g:tmc_panel_verbose
call tmc#progress#stop('test')

" ============================================================
" Minimizing a running job must be silent: completion is reported through
" vim.notify, and an echo on top of that was redundant noise.
" ============================================================
call tmc#panel#open('test', 'Silent')
call tmc#job#start('test', ['sh', '-c', 'sleep 5'], {
      \ 'on_line': {k, l -> 0}, 'on_exit': {k, c -> 0}})
call Ok(tmc#job#is_running('test'), 'job running before minimize')

redir => s:out
silent call tmc#panel#hide('test')
redir END
call Eq(trim(s:out), '', 'MINIMIZING A RUNNING JOB PRINTS NOTHING (got ' . string(trim(s:out)) . ')')
call Ok(tmc#job#is_running('test'), 'job still running after silent minimize')
call tmc#job#cancel('test')


" ============================================================
" Padding and alignment. The 2-space indent used to be applied ad hoc by each
" writer, so results sat at column 0 while the bar and button sat at 2.
" ============================================================
call tmc#panel#reset('test')
call tmc#progress#start('test', 'Compiling')
call tmc#panel#append('test', ['', '--- Results ---', '✅ test_sum', '✅ test_diff'])
call tmc#progress#finish('test', '✅ All 2 tests passed!')
call tmc#panel#append('test', ['', 'Submit (⏎)'])
call tmc#panel#pad_bottom('test')

let s:lines = nvim_buf_get_lines(s:buf, 0, -1, v:false)

" every non-empty line at exactly column 2
let s:bad = filter(copy(s:lines), '!empty(v:val) && match(v:val, ''\S'') != 2')
call Eq(s:bad, [], 'EVERY CONTENT LINE IS AT COLUMN 2')

" ...which means the bar, section header, a result and the button all agree
call Eq(match(BarLine(), '\S'), 2, 'bar at column 2 (not double-padded)')
call Ok(!empty(filter(copy(s:lines), 'v:val =~# "^  --- Results ---$"')), 'section header at column 2')
call Ok(!empty(filter(copy(s:lines), 'v:val =~# "^  ✅ test_sum$"')), 'result line at column 2')
call Ok(!empty(filter(copy(s:lines), 'v:val =~# "^  Submit (⏎)$"')), 'button at column 2 (not double-padded)')

" vertical padding, top and bottom
call Eq(s:lines[0], '', 'blank top padding row')
call Eq(s:lines[-1], '', 'blank bottom padding row')

" blank rows carry no trailing whitespace
call Eq(filter(copy(s:lines), 'v:val =~# "^\\s\\+$"'), [], 'no whitespace-only lines')

" pad_bottom is idempotent
let s:n = nvim_buf_line_count(s:buf)
call tmc#panel#pad_bottom('test')
call tmc#panel#pad_bottom('test')
call Eq(nvim_buf_line_count(s:buf), s:n, 'pad_bottom does not stack blanks')

" exactly one blank between the task line and the first body line
call Eq(Line(4), '', 'single blank separates header from body')
call Ok(!empty(Line(5)), 'body starts right after that blank')

" nested items keep their extra indent (download sub-items)
call tmc#panel#append('test', ['  ✅ nested-slug'])
call Eq(match(Line(nvim_buf_line_count(s:buf)), '\S'), 4, 'nested sub-items sit at column 4')

" ============================================================
" Syntax must still match once lines are indented: the rules were anchored at
" '^' and silently stopped highlighting anything.
" ============================================================
" synID() reads the *current* buffer, and show() focuses the panel.
call tmc#panel#show('test')
syntax enable
call nvim_set_option_value('syntax', 'tmcresult', {'buf': s:buf})

function! SynAt(pat) abort
  let l:lines = nvim_buf_get_lines(tmc#panel#bufnr('test'), 0, -1, v:false)
  for l:i in range(len(l:lines))
    if l:lines[l:i] =~# a:pat
      return synIDattr(synID(l:i + 1, match(l:lines[l:i], '\S') + 1, 1), 'name')
    endif
  endfor
  return 'NOT FOUND'
endfunction

call Eq(SynAt('✅ test_sum'), 'TmcPass', 'padded pass line still highlights')
call Eq(SynAt('--- Results ---'), 'TmcHeader', 'padded section header still highlights')
call Eq(SynAt('Submit (⏎)'), 'TmcButton', 'button still highlights')

" ============================================================
" which-key: the group label and icon. Child labels come from each mapping's
" 'desc', which is why plugin/tmc.vim sets them via nvim_set_keymap.
" ============================================================
for s:lhs in ['<leader>tt', '<leader>ts', '<leader>tw']
  call Ok(!empty(maparg(s:lhs, 'n', 0, 1)), s:lhs . ' is mapped')
  call Ok(!empty(get(maparg(s:lhs, 'n', 0, 1), 'desc', '')),
        \ s:lhs . ' carries a which-key description')
endfor

lua << EOF
local captured = nil
local prev = package.loaded["which-key"]
package.loaded["which-key"] = { add = function(spec) captured = spec end }
package.loaded["tmc.whichkey"] = nil
require("tmc.whichkey").register()
local e = captured and captured[1]
vim.g.spec_wk_lhs = e and e[1] or ""
vim.g.spec_wk_group = e and e.group or ""
vim.g.spec_wk_icon = (e and e.icon and e.icon.icon) or ""
package.loaded["which-key"] = prev

-- with no which-key at all, register() must be a silent no-op
package.loaded["which-key"] = nil
package.loaded["tmc.whichkey"] = nil
vim.g.spec_wk_noerr = pcall(function() require("tmc.whichkey").register() end)
EOF

call Eq(g:spec_wk_lhs, '<leader>t', 'which-key group registered on <leader>t')
call Eq(g:spec_wk_group, 'tmc', 'group is labelled "tmc", not "+3 keymaps"')
call Eq(char2nr(g:spec_wk_icon), 0xF0668, 'group icon is the test tube (U+F0668)')
call Ok(g:spec_wk_noerr, 'register() is a no-op without which-key')


echo "\n=== " . g:passes . " passed, " . len(g:fails) . " failed ==="
for s:f in g:fails
  echo "FAIL: " . s:f
endfor
if !empty(g:fails)
  cquit 1
endif

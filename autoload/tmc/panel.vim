scriptencoding utf-8

" autoload/tmc/panel.vim
" Floating result panels, one per kind ('test', 'submit', 'download', 'paste').
"
" The panel buffer deliberately outlives its window: 'bufhidden' is 'hide', not
" 'wipe', so closing the float only minimizes it. The job keeps writing into the
" buffer, and reopening shows everything that accumulated meanwhile.
"
" Output is appended with nvim_buf_set_lines and scrolled with
" nvim_win_set_cursor on the windows actually showing the buffer -- never with
" ':normal! G', which would scroll whatever window happens to be current and
" yank the cursor out from under the user while a job runs in the background.
"
" The panel takes focus when it opens, which is the only way its buffer-local
" keys can ever fire. Two consequences are handled here: the buffer is kept
" 'nomodifiable' so a focused panel cannot absorb typing, and s:follow() only
" tails windows whose cursor was already at the end, so scrolling back through a
" failure is not undone by the next line of output.

if exists('g:loaded_tmc_panel')
  finish
endif
let g:loaded_tmc_panel = 1

" kind -> {bufnr, winid, title, hint, header}
let s:panels = {}
let s:last_kind = ''

let s:BASE_HINT = 'Esc minimize · <C-c> cancel'

" Left padding applied to every content line, so the bar, results and action
" line all sit on one column. Writers emit unpadded text; padding lives here
" rather than being sprinkled across the four flows that feed a panel.
let s:PAD = '  '

" ===========================
" Internals
" ===========================

function! s:get(kind) abort
  return get(s:panels, a:kind, {})
endfunction

function! s:buf_valid(p) abort
  return !empty(a:p) && has_key(a:p, 'bufnr') && a:p.bufnr > 0 && nvim_buf_is_valid(a:p.bufnr)
endfunction

" A window id alone is not enough: something else may have loaded a different
" buffer into that window (an :edit while the panel was focused, say), in which
" case it is no longer our panel and a fresh float should be opened.
function! s:win_valid(p) abort
  if empty(a:p) || !has_key(a:p, 'winid') || a:p.winid <= 0
    return 0
  endif
  if !nvim_win_is_valid(a:p.winid)
    return 0
  endif
  try
    return nvim_win_get_buf(a:p.winid) == a:p.bufnr
  catch
    return 0
  endtry
endfunction

function! s:make_buf(kind) abort
  let l:buf = nvim_create_buf(v:false, v:true)
  call nvim_set_option_value('bufhidden', 'hide', {'buf': l:buf})
  call nvim_set_option_value('buftype', 'nofile', {'buf': l:buf})
  call nvim_set_option_value('swapfile', v:false, {'buf': l:buf})
  call nvim_set_option_value('buflisted', v:false, {'buf': l:buf})
  call nvim_set_option_value('syntax', 'tmcresult', {'buf': l:buf})
  " Focused panel: keep it read-only so stray keystrokes cannot edit it.
  " Every writer goes through s:writable() to lift this briefly.
  call nvim_set_option_value('modifiable', v:false, {'buf': l:buf})
  try
    call nvim_buf_set_name(l:buf, 'tmc://' . a:kind)
  catch
    " A buffer with that name may linger from an earlier session; harmless.
  endtry

  let l:opts = {'silent': v:true, 'nowait': v:true, 'noremap': v:true}
  call nvim_buf_set_keymap(l:buf, 'n', '<Esc>',
        \ printf(':call tmc#panel#hide(%s)<CR>', string(a:kind)), l:opts)
  call nvim_buf_set_keymap(l:buf, 'n', '<C-c>',
        \ printf(':call tmc#job#cancel(%s)<CR>', string(a:kind)), l:opts)
  return l:buf
endfunction

function! s:win_config(p) abort
  let l:w = max([40, float2nr(&columns * 0.8)])
  let l:h = max([8, float2nr(&lines * 0.7)])
  let l:w = min([l:w, &columns - 2])
  let l:h = min([l:h, &lines - 4])
  return {
        \ 'relative': 'editor',
        \ 'row': max([0, (&lines - l:h) / 2 - 1]),
        \ 'col': max([0, (&columns - l:w) / 2]),
        \ 'width': l:w,
        \ 'height': l:h,
        \ 'style': 'minimal',
        \ 'border': 'rounded',
        \ 'title': ' TMC · ' . a:p.title . ' ',
        \ 'title_pos': 'center',
        \ 'footer': ' ' . a:p.hint . ' ',
        \ 'footer_pos': 'center',
        \ }
endfunction

" Indent content, leaving blank lines genuinely blank: padding them would leave
" trailing whitespace on the vertical padding rows.
function! s:pad(lines) abort
  return map(copy(a:lines), 'empty(v:val) ? "" : s:PAD . v:val')
endfunction

" Panel buffers are 'nomodifiable' so a focused panel cannot absorb typing;
" nvim_buf_set_lines refuses outright on such a buffer (E5555), so every write
" lifts the flag for the duration of the call and restores it afterwards.
function! s:set_lines(buf, start, end, lines) abort
  call nvim_set_option_value('modifiable', v:true, {'buf': a:buf})
  try
    call nvim_buf_set_lines(a:buf, a:start, a:end, v:false, a:lines)
  finally
    call nvim_set_option_value('modifiable', v:false, {'buf': a:buf})
  endtry
endfunction

" Windows showing this buffer whose cursor sits on the last line, i.e. those
" currently tailing the output. Collected *before* an append so that a reader
" who has scrolled up is left where they are.
function! s:tailing_wins(buf) abort
  let l:last = nvim_buf_line_count(a:buf)
  let l:wins = []
  for l:win in nvim_list_wins()
    try
      if nvim_win_get_buf(l:win) == a:buf && nvim_win_get_cursor(l:win)[0] >= l:last
        call add(l:wins, l:win)
      endif
    catch
      " Window vanished mid-iteration.
    endtry
  endfor
  return l:wins
endfunction

" Move the given windows to the new end of the buffer.
function! s:follow(buf, wins) abort
  let l:last = nvim_buf_line_count(a:buf)
  for l:win in a:wins
    try
      call nvim_win_set_cursor(l:win, [l:last, 0])
    catch
      " Window vanished, or the line is momentarily out of range.
    endtry
  endfor
endfunction

" ===========================
" Public API
" ===========================

" Open (or reveal) the panel for a kind. Returns its buffer number.
function! tmc#panel#open(kind, title) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    let l:p = {'bufnr': s:make_buf(a:kind), 'winid': -1, 'header': 0, 'prev_win': -1}
  endif
  let l:p.title = a:title
  let l:p.hint = get(l:p, 'hint', s:BASE_HINT)
  let s:panels[a:kind] = l:p
  let s:last_kind = a:kind
  call tmc#panel#show(a:kind)
  return l:p.bufnr
endfunction

" Clear a panel's contents, ready for a fresh run.
function! tmc#panel#reset(kind) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    return
  endif
  call s:set_lines(l:p.bufnr, 0, -1, [])
  let l:p.header = 0
  let l:p.hint = s:BASE_HINT
  call tmc#panel#refresh_hint(a:kind)
  " Drop any <CR> submit mapping left over from a previous passing run.
  try
    call nvim_buf_del_keymap(l:p.bufnr, 'n', '<CR>')
  catch
  endtry
endfunction

function! tmc#panel#bufnr(kind) abort
  let l:p = s:get(a:kind)
  return s:buf_valid(l:p) ? l:p.bufnr : -1
endfunction

function! tmc#panel#winid(kind) abort
  let l:p = s:get(a:kind)
  return s:win_valid(l:p) ? l:p.winid : -1
endfunction

" Number of lines at the top of the buffer owned by the progress header.
function! tmc#panel#header_size(kind) abort
  return get(s:get(a:kind), 'header', 0)
endfunction

function! tmc#panel#set_header_size(kind, n) abort
  let l:p = s:get(a:kind)
  if !empty(l:p)
    let l:p.header = a:n
  endif
endfunction

" Append lines below whatever is already there, then follow the tail.
function! tmc#panel#append(kind, lines) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    return
  endif
  let l:lines = type(a:lines) == type([]) ? a:lines : [a:lines]
  if empty(l:lines)
    return
  endif

  let l:tailing = s:tailing_wins(l:p.bufnr)

  " A fresh scratch buffer already holds one empty line; overwrite it rather
  " than leaving a blank first line above the output.
  let l:count = nvim_buf_line_count(l:p.bufnr)
  if l:count == 1 && empty(nvim_buf_get_lines(l:p.bufnr, 0, 1, v:false)[0])
    call s:set_lines(l:p.bufnr, 0, 1, s:pad(l:lines))
  else
    call s:set_lines(l:p.bufnr, -1, -1, s:pad(l:lines))
  endif
  call s:follow(l:p.bufnr, l:tailing)
endfunction

" One blank row above the bottom border, so a finished run does not sit flush
" against it. Idempotent: called at the end of each flow's exit handler, after
" any action line has been appended.
function! tmc#panel#pad_bottom(kind) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    return
  endif
  let l:count = nvim_buf_line_count(l:p.bufnr)
  if l:count > 0 && empty(nvim_buf_get_lines(l:p.bufnr, -2, -1, v:false)[0])
    return
  endif
  let l:tailing = s:tailing_wins(l:p.bufnr)
  call s:set_lines(l:p.bufnr, -1, -1, [''])
  call s:follow(l:p.bufnr, l:tailing)
endfunction

" Streaming CLI chatter: the progress bar already shows the current task, so
" this is dropped unless g:tmc_panel_verbose is set. Keeping it in the body
" filled the panel with dozens of near-identical status lines on a submit.
function! tmc#panel#log(kind, lines) abort
  if !get(g:, 'tmc_panel_verbose', 0)
    return
  endif
  return tmc#panel#append(a:kind, a:lines)
endfunction

" Replace the first a:count lines (used by the progress header).
function! tmc#panel#set_head(kind, count, lines) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    return
  endif
  call s:set_lines(l:p.bufnr, 0, a:count, s:pad(a:lines))
endfunction

" Reserve the top of the buffer for a header, so later appends land below it.
" An emptied buffer still holds one blank line, which has to be consumed rather
" than pushed down -- otherwise it wedges a stray blank between header and body.
function! tmc#panel#claim_head(kind, lines) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    return
  endif
  let l:replace = 0
  if nvim_buf_line_count(l:p.bufnr) == 1
        \ && empty(nvim_buf_get_lines(l:p.bufnr, 0, 1, v:false)[0])
    let l:replace = 1
  endif
  call s:set_lines(l:p.bufnr, 0, l:replace, s:pad(a:lines))
  let l:p.header = len(a:lines)
endfunction

function! tmc#panel#is_visible(kind) abort
  return s:win_valid(s:get(a:kind))
endfunction

" Minimize: close the float, keep the buffer and the job, and hand focus back
" to whatever window the panel took it from. Deliberately silent -- completion
" is reported through tmc#notify#, and echoing here on top of that was noise.
function! tmc#panel#hide(kind) abort
  let l:p = s:get(a:kind)
  if s:win_valid(l:p)
    call nvim_win_close(l:p.winid, v:false)
  endif
  if empty(l:p)
    return
  endif
  let l:p.winid = -1
  let l:prev = get(l:p, 'prev_win', -1)
  if l:prev > 0 && nvim_win_is_valid(l:prev)
    try
      call nvim_set_current_win(l:prev)
    catch
    endtry
  endif
  let l:p.prev_win = -1
endfunction

function! tmc#panel#show(kind) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    call tmc#util#echo_error('No TMC ' . a:kind . ' panel to show')
    return
  endif
  if s:win_valid(l:p)
    call nvim_set_current_win(l:p.winid)
    return
  endif
  " Remember where focus came from, then take it: the panel's keys are
  " buffer-local, so an unfocused panel can never receive them.
  let l:p.prev_win = win_getid()
  let l:p.winid = nvim_open_win(l:p.bufnr, v:true, s:win_config(l:p))
  call nvim_set_option_value('wrap', v:true, {'win': l:p.winid})
  call nvim_set_option_value('cursorline', v:false, {'win': l:p.winid})
  let s:last_kind = a:kind
  call s:follow(l:p.bufnr, [l:p.winid])
endfunction

function! tmc#panel#toggle(kind) abort
  if tmc#panel#is_visible(a:kind)
    call tmc#panel#hide(a:kind)
  else
    call tmc#panel#show(a:kind)
  endif
endfunction

" Extend the footer hint, e.g. with 's submit' once a run has passed.
function! tmc#panel#add_hint(kind, extra) abort
  let l:p = s:get(a:kind)
  if empty(l:p)
    return
  endif
  let l:hint = get(l:p, 'hint', s:BASE_HINT)
  if l:hint !~# '\V' . escape(a:extra, '\')
    let l:p.hint = l:hint . ' · ' . a:extra
  endif
  call tmc#panel#refresh_hint(a:kind)
endfunction

function! tmc#panel#refresh_hint(kind) abort
  let l:p = s:get(a:kind)
  if s:win_valid(l:p)
    call nvim_win_set_config(l:p.winid, s:win_config(l:p))
  endif
endfunction

" Bind an extra key inside the panel (used for the Submit action).
function! tmc#panel#map(kind, lhs, rhs) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    return
  endif
  call nvim_buf_set_keymap(l:p.bufnr, 'n', a:lhs, a:rhs,
        \ {'silent': v:true, 'nowait': v:true, 'noremap': v:true})
endfunction

" The panel most recently opened or shown, for the bare :TmcPanel command.
function! tmc#panel#last_kind() abort
  return s:last_kind
endfunction

function! tmc#panel#kinds() abort
  return sort(keys(s:panels))
endfunction

" Command-line completion for :TmcPanel.
function! tmc#panel#complete(arg_lead, cmd_line, cursor_pos) abort
  return filter(tmc#panel#kinds(), 'v:val =~# "^" . a:arg_lead')
endfunction

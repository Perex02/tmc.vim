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

if exists('g:loaded_tmc_panel')
  finish
endif
let g:loaded_tmc_panel = 1

" kind -> {bufnr, winid, title, hint, header}
let s:panels = {}
let s:last_kind = ''

let s:BASE_HINT = 'q minimize · <C-c> cancel'

" ===========================
" Internals
" ===========================

function! s:get(kind) abort
  return get(s:panels, a:kind, {})
endfunction

function! s:buf_valid(p) abort
  return !empty(a:p) && has_key(a:p, 'bufnr') && a:p.bufnr > 0 && nvim_buf_is_valid(a:p.bufnr)
endfunction

function! s:win_valid(p) abort
  return !empty(a:p) && has_key(a:p, 'winid') && a:p.winid > 0 && nvim_win_is_valid(a:p.winid)
endfunction

function! s:make_buf(kind) abort
  let l:buf = nvim_create_buf(v:false, v:true)
  call nvim_set_option_value('bufhidden', 'hide', {'buf': l:buf})
  call nvim_set_option_value('buftype', 'nofile', {'buf': l:buf})
  call nvim_set_option_value('swapfile', v:false, {'buf': l:buf})
  call nvim_set_option_value('buflisted', v:false, {'buf': l:buf})
  call nvim_set_option_value('modifiable', v:true, {'buf': l:buf})
  call nvim_set_option_value('syntax', 'tmcresult', {'buf': l:buf})
  try
    call nvim_buf_set_name(l:buf, 'tmc://' . a:kind)
  catch
    " A buffer with that name may linger from an earlier session; harmless.
  endtry

  let l:opts = {'silent': v:true, 'nowait': v:true, 'noremap': v:true}
  call nvim_buf_set_keymap(l:buf, 'n', 'q',
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

" Scroll every window showing this buffer to the last line.
function! s:follow(buf) abort
  let l:last = nvim_buf_line_count(a:buf)
  for l:win in nvim_list_wins()
    try
      if nvim_win_get_buf(l:win) == a:buf
        call nvim_win_set_cursor(l:win, [l:last, 0])
      endif
    catch
      " Window vanished mid-iteration, or the line is momentarily out of range.
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
    let l:p = {'bufnr': s:make_buf(a:kind), 'winid': -1, 'header': 0}
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
  call nvim_buf_set_lines(l:p.bufnr, 0, -1, v:false, [])
  let l:p.header = 0
  let l:p.hint = s:BASE_HINT
  call tmc#panel#refresh_hint(a:kind)
  " Drop any 's' mapping left over from a previous passing run.
  try
    call nvim_buf_del_keymap(l:p.bufnr, 'n', 's')
  catch
  endtry
endfunction

function! tmc#panel#bufnr(kind) abort
  let l:p = s:get(a:kind)
  return s:buf_valid(l:p) ? l:p.bufnr : -1
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

  " A fresh scratch buffer already holds one empty line; overwrite it rather
  " than leaving a blank first line above the output.
  let l:count = nvim_buf_line_count(l:p.bufnr)
  if l:count == 1 && empty(nvim_buf_get_lines(l:p.bufnr, 0, 1, v:false)[0])
    call nvim_buf_set_lines(l:p.bufnr, 0, 1, v:false, l:lines)
  else
    call nvim_buf_set_lines(l:p.bufnr, -1, -1, v:false, l:lines)
  endif
  call s:follow(l:p.bufnr)
endfunction

" Replace the first a:count lines (used by the progress header).
function! tmc#panel#set_head(kind, count, lines) abort
  let l:p = s:get(a:kind)
  if !s:buf_valid(l:p)
    return
  endif
  call nvim_buf_set_lines(l:p.bufnr, 0, a:count, v:false, a:lines)
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
  call nvim_buf_set_lines(l:p.bufnr, 0, l:replace, v:false, a:lines)
  let l:p.header = len(a:lines)
endfunction

function! tmc#panel#is_visible(kind) abort
  return s:win_valid(s:get(a:kind))
endfunction

" Minimize: close the float, keep the buffer and the job.
function! tmc#panel#hide(kind) abort
  let l:p = s:get(a:kind)
  if s:win_valid(l:p)
    call nvim_win_close(l:p.winid, v:false)
  endif
  if !empty(l:p)
    let l:p.winid = -1
  endif
  if tmc#job#is_running(a:kind)
    call tmc#util#echo_info(printf('TMC %s still running in the background (:TmcPanel %s to reopen)',
          \ a:kind, a:kind))
  endif
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
  let l:p.winid = nvim_open_win(l:p.bufnr, v:false, s:win_config(l:p))
  call nvim_set_option_value('wrap', v:true, {'win': l:p.winid})
  call nvim_set_option_value('cursorline', v:false, {'win': l:p.winid})
  let s:last_kind = a:kind
  call s:follow(l:p.bufnr)
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

" Bind an extra key inside the panel (used for the [Submit (s)] action).
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

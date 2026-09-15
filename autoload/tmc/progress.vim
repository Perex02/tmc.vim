scriptencoding utf-8

" autoload/tmc/progress.vim
" Progress bar for a panel, replacing the old single-line spinner.
"
" Owns the first three lines of the panel buffer -- bar, current task, blank
" separator -- so tmc#panel#append() can keep writing below without any offset
" bookkeeping:
"
"    ████████████░░░░░░░░  58%
"  ⠹ Running test suite…
"
" The CLI reports 'percent-done' on its status updates, but not for every
" operation. When it is missing we animate an indeterminate sweep instead of
" parking a bar at 0%, which would read as a hang.

if exists('g:loaded_tmc_progress')
  finish
endif
let g:loaded_tmc_progress = 1

let s:HEADER = 3
let s:WIDTH = 24
let s:SWEEP = 6
let s:FRAMES = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏']

" kind -> {percent, message, timer, frame, done}
let s:state = {}

" ===========================
" Rendering
" ===========================

function! s:bar_determinate(percent) abort
  let l:pct = a:percent < 0.0 ? 0.0 : (a:percent > 1.0 ? 1.0 : a:percent)
  let l:filled = float2nr(round(l:pct * s:WIDTH))
  return printf('  %s%s  %3d%%',
        \ repeat('█', l:filled), repeat('░', s:WIDTH - l:filled),
        \ float2nr(round(l:pct * 100)))
endfunction

function! s:bar_indeterminate(frame) abort
  let l:span = s:WIDTH + s:SWEEP
  let l:pos = a:frame % l:span
  let l:bar = ''
  for l:i in range(s:WIDTH)
    let l:bar .= (l:i < l:pos && l:i >= l:pos - s:SWEEP) ? '█' : '░'
  endfor
  return '  ' . l:bar . '   ···'
endfunction

function! s:render(kind) abort
  let l:st = get(s:state, a:kind, {})
  if empty(l:st)
    return
  endif

  if l:st.done
    let l:head = s:bar_determinate(1.0)
    let l:task = '  ' . l:st.message
  else
    let l:head = l:st.percent >= 0.0
          \ ? s:bar_determinate(l:st.percent)
          \ : s:bar_indeterminate(l:st.frame)
    let l:task = '  ' . s:FRAMES[l:st.frame % len(s:FRAMES)] . ' ' . l:st.message
  endif

  call tmc#panel#set_head(a:kind, s:HEADER, [l:head, l:task, ''])
endfunction

" ===========================
" Public API
" ===========================

function! tmc#progress#start(kind, message) abort
  call tmc#progress#stop(a:kind)

  let s:state[a:kind] = {
        \ 'percent': -1.0,
        \ 'message': a:message,
        \ 'frame': 0,
        \ 'done': 0,
        \ 'timer': -1,
        \ }

  " Claim the header lines up front so appended output lands underneath.
  call tmc#panel#claim_head(a:kind, repeat([''], s:HEADER))
  call s:render(a:kind)

  let s:state[a:kind].timer =
        \ timer_start(100, {_ -> s:tick(a:kind)}, {'repeat': -1})
endfunction

function! s:tick(kind) abort
  let l:st = get(s:state, a:kind, {})
  if empty(l:st) || l:st.done || tmc#panel#bufnr(a:kind) < 0
    call tmc#progress#stop(a:kind)
    return
  endif
  let l:st.frame += 1
  call s:render(a:kind)
endfunction

" percent: 0.0-1.0, or a negative number when unknown.
function! tmc#progress#update(kind, percent, message) abort
  let l:st = get(s:state, a:kind, {})
  if empty(l:st)
    return
  endif
  let l:st.percent = a:percent * 1.0
  if !empty(a:message)
    let l:st.message = a:message
  endif
  call s:render(a:kind)
endfunction

" Freeze the bar and leave a summary on the task line.
function! tmc#progress#finish(kind, summary) abort
  let l:st = get(s:state, a:kind, {})
  if empty(l:st)
    return
  endif
  let l:st.done = 1
  let l:st.message = a:summary
  call s:render(a:kind)
  call tmc#progress#stop(a:kind)
endfunction

function! tmc#progress#stop(kind) abort
  let l:st = get(s:state, a:kind, {})
  if empty(l:st) || get(l:st, 'timer', -1) == -1
    return
  endif
  let l:t = l:st.timer
  let l:st.timer = -1
  call timer_stop(l:t)
endfunction

" Pull a 0.0-1.0 progress value out of a CLI status-update object.
" Returns -1.0 when the CLI did not report one.
function! tmc#progress#percent_of(obj) abort
  if type(a:obj) != type({}) || !has_key(a:obj, 'percent-done')
    return -1.0
  endif
  let l:v = a:obj['percent-done']
  if type(l:v) != type(0.0) && type(l:v) != type(0)
    return -1.0
  endif
  return l:v * 1.0
endfunction

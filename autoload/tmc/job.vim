scriptencoding utf-8

" autoload/tmc/job.vim
" One registry for the plugin's background CLI jobs, keyed by panel kind.
"
" Replaces the per-module s:last_result singletons and g:tmc_*_buf globals, so
" a backgrounded test run and a submit no longer overwrite each other's state.
" Each entry also carries the exercise root/id resolved when the job launched,
" which is what lets the [Submit (s)] action work from inside a panel buffer
" that is not itself part of the exercise.

if exists('g:loaded_tmc_job')
  finish
endif
let g:loaded_tmc_job = 1

" kind -> entry
let s:jobs = {}

" ===========================
" Internals
" ===========================

" Strip CR and ANSI escapes. The submit and paste jobs run on a pty to keep the
" CLI unbuffered, which means their output arrives full of terminal control
" sequences that would otherwise land in the panel verbatim.
function! s:clean(line) abort
  let l:s = substitute(a:line, '\r', '', 'g')
  let l:s = substitute(l:s, '\%x1b\[[0-9;?]*[ -/]*[@-~]', '', 'g')
  let l:s = substitute(l:s, '\%x1b[=>]', '', 'g')
  return l:s
endfunction

function! s:on_out(kind, data) abort
  let l:e = get(s:jobs, a:kind, {})
  if empty(l:e)
    return
  endif
  for l:raw in a:data
    let l:line = s:clean(l:raw)
    if empty(trim(l:line))
      continue
    endif
    call call(l:e.on_line, [a:kind, l:line])
  endfor
endfunction

function! s:on_exit(kind, code) abort
  let l:e = get(s:jobs, a:kind, {})
  if empty(l:e)
    return
  endif
  if l:e.state ==# 'running'
    let l:e.state = a:code == 0 ? 'done' : 'failed'
  endif
  let l:e.exit_code = a:code
  call call(l:e.on_exit, [a:kind, a:code])
endfunction

" ===========================
" Public API
" ===========================

" opts:
"   on_line  Funcref(kind, line)   required
"   on_exit  Funcref(kind, code)   required
"   pty      truthy to run on a pty
"   meta     dict carried alongside the job (root, exercise_id, ...)
function! tmc#job#start(kind, cmd, opts) abort
  let s:jobs[a:kind] = {
        \ 'kind': a:kind,
        \ 'job_id': -1,
        \ 'state': 'running',
        \ 'exit_code': -1,
        \ 'last_result': {},
        \ 'logs': [],
        \ 'meta': get(a:opts, 'meta', {}),
        \ 'on_line': a:opts.on_line,
        \ 'on_exit': a:opts.on_exit,
        \ }

  let l:jobopts = {
        \ 'stdout_buffered': v:false,
        \ 'stderr_buffered': v:false,
        \ 'on_stdout': {j, d, ev -> s:on_out(a:kind, d)},
        \ 'on_stderr': {j, d, ev -> s:on_out(a:kind, d)},
        \ 'on_exit':   {j, c, ev -> s:on_exit(a:kind, c)},
        \ }
  if get(a:opts, 'pty', 0)
    let l:jobopts.pty = v:true
  endif

  let s:jobs[a:kind].job_id = jobstart(a:cmd, l:jobopts)
  if s:jobs[a:kind].job_id <= 0
    let s:jobs[a:kind].state = 'failed'
    call tmc#util#echo_error('Failed to start tmc-langs-cli job')
  endif
  return s:jobs[a:kind].job_id
endfunction

function! tmc#job#get(kind) abort
  return get(s:jobs, a:kind, {})
endfunction

function! tmc#job#meta(kind) abort
  return get(get(s:jobs, a:kind, {}), 'meta', {})
endfunction

function! tmc#job#is_running(kind) abort
  return get(get(s:jobs, a:kind, {}), 'state', '') ==# 'running'
endfunction

function! tmc#job#set_result(kind, obj) abort
  let l:e = get(s:jobs, a:kind, {})
  if !empty(l:e)
    let l:e.last_result = a:obj
  endif
endfunction

function! tmc#job#result(kind) abort
  return get(get(s:jobs, a:kind, {}), 'last_result', {})
endfunction

function! tmc#job#cancel(kind) abort
  let l:e = get(s:jobs, a:kind, {})
  if empty(l:e) || l:e.state !=# 'running'
    call tmc#util#echo_info('No running TMC ' . a:kind . ' job to cancel')
    return
  endif
  let l:e.state = 'cancelled'
  try
    call jobstop(l:e.job_id)
  catch
  endtry
  call tmc#progress#finish(a:kind, '⚠️  Cancelled')
  call tmc#panel#append(a:kind, ['', '⚠️  Cancelled by user'])
endfunction

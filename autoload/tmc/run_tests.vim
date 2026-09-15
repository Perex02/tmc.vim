scriptencoding utf-8

" autoload/tmc/run_tests.vim
" Runs the local test suite for the current exercise in a floating panel.
" The job outlives the panel window, so <Esc> minimizes without stopping it.

if exists('g:loaded_tmc_run_tests')
  finish
endif
let g:loaded_tmc_run_tests = 1

let s:KIND = 'test'

" ===========================
" Public: Run tests for current exercise
" ===========================
function! tmc#run_tests#current() abort
  call tmc#cli#ensure()

  if tmc#job#is_running(s:KIND)
    call tmc#util#echo_warning('A TMC test run is already in progress')
    call tmc#panel#show(s:KIND)
    return
  endif

  let l:root = tmc#project#find_exercise_root()
  if empty(l:root)
    call tmc#util#echo_error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif

  " Resolved now, while a real exercise buffer is current: the panel buffer is
  " not inside the exercise, so the Submit action could not work this out later.
  let l:id = tmc#project#get_exercise_id(l:root)

  call tmc#panel#open(s:KIND, 'Tests · ' . fnamemodify(l:root, ':t'))
  call tmc#panel#reset(s:KIND)
  call tmc#progress#start(s:KIND, 'Starting test run…')

  call tmc#job#start(s:KIND, [g:tmc_cli_path, 'run-tests', '--exercise-path', l:root], {
        \ 'meta': {'root': l:root, 'exercise_id': l:id},
        \ 'on_line': function('s:on_line'),
        \ 'on_exit': function('s:on_exit'),
        \ })
endfunction

" ===========================
" Streaming output
" ===========================
function! s:on_line(kind, line) abort
  try
    let l:obj = json_decode(a:line)
  catch
    call tmc#panel#log(a:kind, 'ℹ️  ' . a:line)
    return
  endtry

  let l:kind = get(l:obj, 'output-kind', '')
  if l:kind ==# 'status-update'
    let l:msg = get(l:obj, 'message', '')
    call tmc#progress#update(a:kind, tmc#progress#percent_of(l:obj), l:msg)
    if !empty(l:msg)
      call tmc#panel#log(a:kind, '⏳ ' . l:msg)
    endif
  elseif l:kind ==# 'output-data'
    call tmc#job#set_result(a:kind, l:obj)
  endif
endfunction

" ===========================
" Completion
" ===========================
function! s:on_exit(kind, code) abort
  let l:res = tmc#job#result(a:kind)
  let l:data = s:output_data(l:res)
  let l:results = type(l:data) == type({}) ? get(l:data, 'testResults', []) : []

  let l:total = len(l:results)
  let l:failed = 0

  call tmc#panel#append(a:kind, ['', '--- Results ---'])

  for l:tc in l:results
    if get(l:tc, 'successful', v:false)
      call tmc#panel#append(a:kind, '✅ ' . get(l:tc, 'name', '?'))
    else
      let l:failed += 1
      call tmc#panel#append(a:kind, '❌ ' . get(l:tc, 'name', '?') . ':')
      let l:msg = substitute(get(l:tc, 'message', ''), '\\n', "\n", 'g')
      if !empty(l:msg)
        call tmc#panel#append(a:kind, split(l:msg, "\n"))
      endif
    endif
  endfor

  let l:passed = l:failed == 0 && l:total > 0
  if l:passed
    let l:summary = printf('✅ All %d tests passed!', l:total)
  elseif l:total > 0
    let l:summary = printf('❌ %d of %d tests failed', l:failed, l:total)
  else
    let l:summary = s:no_result_summary(l:res)
  endif

  call tmc#panel#append(a:kind, l:summary)
  call tmc#progress#finish(a:kind, l:summary)

  if l:passed
    call s:offer_submit(a:kind)
  endif

  call tmc#notify#result(a:kind, l:passed, l:summary)
endfunction

" A run with no testResults is either an error object or a suite with no tests;
" surface the CLI's own message rather than a bare 'no results'.
function! s:no_result_summary(res) abort
  let l:data = s:output_data(a:res)
  if type(l:data) == type({}) && has_key(l:data, 'trace')
    let l:trace = l:data['trace']
    if type(l:trace) == type([]) && !empty(l:trace)
      return '❌ ' . l:trace[0]
    endif
  endif
  let l:msg = get(a:res, 'message', '')
  return empty(l:msg) ? '⚠️  No tests were run' : '⚠️  ' . l:msg
endfunction

function! s:output_data(res) abort
  if type(a:res) != type({}) || !has_key(a:res, 'data')
    return {}
  endif
  let l:d = a:res['data']
  if type(l:d) != type({})
    return {}
  endif
  return get(l:d, 'output-data', {})
endfunction

" ===========================
" Submit action, offered only after a passing run
" ===========================
function! s:offer_submit(kind) abort
  call tmc#panel#append(a:kind, ['', '  Submit (⏎)'])
  call tmc#panel#map(a:kind, '<CR>',
        \ printf(':call tmc#run_tests#submit_passed(%s)<CR>', string(a:kind)))
  call tmc#panel#add_hint(a:kind, 'Enter submit')
endfunction

" Invoked by <CR> on the Submit line in the panel.
function! tmc#run_tests#submit_passed(kind) abort
  let l:meta = tmc#job#meta(a:kind)
  let l:root = get(l:meta, 'root', '')
  if empty(l:root)
    call tmc#util#echo_error('No exercise recorded for this test run')
    return
  endif
  call tmc#panel#hide(a:kind)
  call tmc#submit#exercise(l:root, get(l:meta, 'exercise_id', ''))
endfunction

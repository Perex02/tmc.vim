scriptencoding utf-8

" autoload/tmc/submit.vim
" Submits an exercise to the TMC server, reporting into a floating panel.

if exists('g:loaded_tmc_submit')
  finish
endif
let g:loaded_tmc_submit = 1

let s:KIND = 'submit'

" ===========================
" Public: submit the exercise containing the current buffer
" ===========================
function! tmc#submit#current() abort
  let l:root = tmc#project#find_exercise_root()
  if empty(l:root)
    call tmc#util#echo_error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif
  return tmc#submit#exercise(l:root, tmc#project#get_exercise_id(l:root))
endfunction

" ===========================
" Public: submit an explicit exercise
"
" Split out from tmc#submit#current() so the Submit action in the test
" panel can submit the exercise the run was started from -- the panel buffer
" itself is not inside the exercise, so re-deriving the root there would fail.
" ===========================
function! tmc#submit#exercise(root, id) abort
  call tmc#cli#ensure()

  if tmc#job#is_running(s:KIND)
    call tmc#util#echo_warning('A TMC submission is already in progress')
    call tmc#panel#show(s:KIND)
    return
  endif

  let l:id = a:id
  if empty(l:id)
    let l:id = input('Exercise ID: ')
    if empty(l:id)
      call tmc#util#echo_error('Submission cancelled: no exercise ID provided')
      return
    endif
  endif

  call tmc#panel#open(s:KIND, 'Submit · ' . fnamemodify(a:root, ':t'))
  call tmc#panel#reset(s:KIND)
  call tmc#progress#start(s:KIND, 'Submitting exercise…')

  let l:cmd = [g:tmc_cli_path, 'tmc',
        \ '--client-name', g:tmc_client_name,
        \ '--client-version', g:tmc_client_version,
        \ 'submit',
        \ '--exercise-id', l:id,
        \ '--submission-path', a:root]

  call tmc#job#start(s:KIND, l:cmd, {
        \ 'pty': 1,
        \ 'meta': {'root': a:root, 'exercise_id': l:id},
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

  let l:okind = get(l:obj, 'output-kind', '')
  if l:okind ==# 'status-update'
    let l:msg = get(l:obj, 'message', '')
    call tmc#progress#update(a:kind, tmc#progress#percent_of(l:obj), l:msg)
    if !empty(l:msg)
      call tmc#panel#log(a:kind, '⏳ ' . l:msg)
    endif
  elseif l:okind ==# 'output-data'
    call tmc#job#set_result(a:kind, l:obj)
  endif
endfunction

" ===========================
" Completion
" ===========================
function! s:on_exit(kind, code) abort
  let l:res = tmc#job#result(a:kind)
  let l:dat = s:output_data(l:res)

  if empty(l:dat)
    let l:summary = '❌ Submission ended without result'
    call tmc#panel#append(a:kind, ['', l:summary])
    call tmc#progress#finish(a:kind, l:summary)
    call tmc#panel#pad_bottom(a:kind)
    call tmc#notify#result(a:kind, 0, l:summary)
    return
  endif

  call tmc#panel#append(a:kind, ['', '--- Results ---'])

  let l:cases = get(l:dat, 'test_cases', [])
  let l:failed = 0
  let l:total = len(l:cases)

  for l:tc in l:cases
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

  let l:passed = get(l:dat, 'all_tests_passed', v:false)
  let l:summary = l:passed
        \ ? printf('✅ All tests passed on the server!%s', l:total > 0 ? printf(' (%d)', l:total) : '')
        \ : printf('❌ %d of %d tests failed on the server', l:failed, l:total)

  call tmc#panel#append(a:kind, l:summary)

  if has_key(l:dat, 'submission_url')
    call tmc#panel#append(a:kind, '🔗 Submission URL: ' . l:dat['submission_url'])
  endif

  call tmc#progress#finish(a:kind, l:summary)
  call tmc#panel#pad_bottom(a:kind)
  call tmc#notify#result(a:kind, l:passed, l:summary)
endfunction

function! s:output_data(res) abort
  if type(a:res) != type({}) || !has_key(a:res, 'data')
    return {}
  endif
  let l:d = a:res['data']
  if type(l:d) != type({})
    return {}
  endif
  let l:od = get(l:d, 'output-data', {})
  return type(l:od) == type({}) ? l:od : {}
endfunction

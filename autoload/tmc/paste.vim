scriptencoding utf-8

" autoload/tmc/paste.vim
" Creates a TMC paste for the current exercise, reporting into a floating panel.

if exists('g:loaded_tmc_paste')
  finish
endif
let g:loaded_tmc_paste = 1

let s:KIND = 'paste'

function! tmc#paste#current() abort
  call tmc#cli#ensure()

  if tmc#job#is_running(s:KIND)
    call tmc#util#echo_warning('A TMC paste is already in progress')
    call tmc#panel#show(s:KIND)
    return
  endif

  let l:root = tmc#project#find_exercise_root()
  if empty(l:root)
    call tmc#util#echo_error('Could not locate exercise root (.tmcproject.yml not found)')
    return
  endif

  let l:id = tmc#project#get_exercise_id(l:root)
  if empty(l:id)
    let l:id = input('Exercise ID: ')
    if empty(l:id)
      call tmc#util#echo_error('Paste cancelled: no exercise ID provided')
      return
    endif
  endif

  call tmc#panel#open(s:KIND, 'Paste · ' . fnamemodify(l:root, ':t'))
  call tmc#panel#reset(s:KIND)
  call tmc#progress#start(s:KIND, 'Creating paste…')

  let l:cmd = [g:tmc_cli_path, 'tmc',
        \ '--client-name', g:tmc_client_name,
        \ '--client-version', g:tmc_client_version,
        \ 'paste',
        \ '--exercise-id', l:id,
        \ '--submission-path', l:root]

  call tmc#job#start(s:KIND, l:cmd, {
        \ 'pty': 1,
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
  let l:dat = {}
  if type(l:res) == type({}) && has_key(l:res, 'data') && type(l:res['data']) == type({})
    let l:dat = get(l:res['data'], 'output-data', {})
  endif
  if type(l:dat) != type({})
    let l:dat = {}
  endif

  call tmc#panel#append(a:kind, ['', '--- Paste Completed ---'])

  let l:url = get(l:dat, 'paste_url', '')
  if empty(l:url)
    let l:summary = '❌ No paste URL in response'
    call tmc#panel#append(a:kind, l:summary)
  else
    let l:summary = '🔗 Paste URL: ' . l:url
    call tmc#panel#append(a:kind, l:summary)
    if has_key(l:dat, 'show_submission_url')
      call tmc#panel#append(a:kind, '🔗 Submission URL: ' . l:dat['show_submission_url'])
    endif
  endif

  call tmc#progress#finish(a:kind, empty(l:url) ? '❌ Paste failed' : '✅ Paste created')
  call tmc#notify#result(a:kind, !empty(l:url), l:summary)
endfunction

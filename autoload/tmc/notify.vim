scriptencoding utf-8

" autoload/tmc/notify.vim
" Desktop-style notifications via vim.notify, so a run that finishes while its
" panel is minimized still tells the user what happened.

if exists('g:loaded_tmc_notify')
  finish
endif
let g:loaded_tmc_notify = 1

" vim.log.levels
let s:LEVELS = {'debug': 1, 'info': 2, 'warn': 3, 'error': 4}

" Send a notification. level is one of 'info', 'warn', 'error', 'debug'.
function! tmc#notify#send(msg, level, ...) abort
  let l:title = a:0 >= 1 ? a:1 : 'TMC'
  let l:lvl = get(s:LEVELS, tolower(a:level), s:LEVELS['info'])
  call luaeval('(function(m, l, t) vim.notify(m, l, { title = t }) end)(_A[1], _A[2], _A[3])',
        \ [a:msg, l:lvl, l:title])
endfunction

" Report the outcome of a finished run.
"   kind    - panel kind the run belongs to ('test', 'submit', ...)
"   ok      - truthy when everything passed
"   summary - one-line message
"
" Only notifies when the panel is hidden, i.e. the run finished in the
" background: popping a notification over a panel the user is already reading
" is just noise. Set g:tmc_notify_always to override.
function! tmc#notify#result(kind, ok, summary) abort
  if tmc#panel#is_visible(a:kind) && !get(g:, 'tmc_notify_always', 0)
    return
  endif
  call tmc#notify#send(a:summary, a:ok ? 'info' : 'warn', 'TMC')
endfunction

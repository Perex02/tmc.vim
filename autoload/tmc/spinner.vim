scriptencoding utf-8

" autoload/tmc/spinner.vim
" DEPRECATED. The line-1 spinner was replaced by tmc#progress#*, which renders a
" real progress bar plus the current task into a panel header. These shims stay
" so any external caller keeps working; they map onto the 'test' panel, which is
" what the old single global spinner effectively assumed.

if exists('g:loaded_tmc_spinner')
  finish
endif
let g:loaded_tmc_spinner = 1

function! tmc#spinner#start(buf, message) abort
  return tmc#progress#start('test', a:message)
endfunction

function! tmc#spinner#stop() abort
  return tmc#progress#stop('test')
endfunction

function! tmc#spinner#tick(timer) abort
  " The progress module drives its own timer; nothing to do.
endfunction

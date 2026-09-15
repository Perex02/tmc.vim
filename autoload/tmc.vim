scriptencoding utf-8

if exists('g:loaded_tmc')
  finish
endif
let g:loaded_tmc = 1

" ========================================
" Backward compatibility wrappers
" ========================================

" CLI
function! tmc#ensure_cli() abort
  return tmc#cli#ensure()
endfunction

function! tmc#run_cli(args) abort
  return tmc#cli#run(a:args)
endfunction

function! tmc#run_cli_streaming(args) abort
  return tmc#cli#run_streaming(a:args)
endfunction

" Courses
function! tmc#list_courses() abort
  return tmc#course#list()
endfunction

function! tmc#list_exercises(course_id) abort
  return tmc#exercise#list(a:course_id)
endfunction

function! tmc#cd_course() abort
  return tmc#project#cd_course()
endfunction

" Auth
function! tmc#login(...) abort
  return call('tmc#auth#login', a:000)
endfunction

function! tmc#logout() abort
  return tmc#auth#logout()
endfunction

function! tmc#status() abort
  return tmc#auth#status()
endfunction

" Submit
function! tmc#submit_current() abort
  return tmc#submit#current()
endfunction

" Tests
function! tmc#run_tests_current() abort
  return tmc#run_tests#current()
endfunction

" Download
function! tmc#download_course_exercises(course_id, org, cb) abort
  return tmc#download#course_exercises(a:course_id, a:org, a:cb)
endfunction

" :TmcDownload <courseId> [org] dispatches here; the organisation defaults to
" g:tmc_organization so the command can be called with the course id alone.
function! tmc#course_exercises(course_id, ...) abort
  let l:org = a:0 >= 1 ? a:1 : get(g:, 'tmc_organization', 'mooc')
  return tmc#download#course_exercises(a:course_id, l:org, {_ -> 0})
endfunction

" Pick
function! tmc#pick_course_command() abort
  return tmc#ui#pick_course_command()
endfunction

function! tmc#pick_organization_command() abort
  return tmc#ui#pick_organization_command()
endfunction

function! tmc#paste_current() abort
  return tmc#paste#current()
endfunction

function! tmc#projects_dir() abort
  return tmc#project#get_dir()
endfunction

" Panels
" :TmcPanel with no argument targets the panel most recently opened.
function! tmc#toggle_panel(...) abort
  let l:kind = a:0 >= 1 && !empty(a:1) ? a:1 : tmc#panel#last_kind()
  if empty(l:kind)
    call tmc#util#echo_info('No TMC panel yet - run :TmcRunTests or :TmcSubmit first')
    return
  endif
  return tmc#panel#toggle(l:kind)
endfunction

scriptencoding utf-8

" autoload/tmc/download.vim
" Downloads a course's exercises into a floating panel, with progress and a
" per-exercise summary.

if exists('g:autoloaded_tmc_download')
  finish
endif
let g:autoloaded_tmc_download = 1

let s:KIND = 'download'

" Callbacks to run once the download finishes, keyed by nothing in particular:
" only one download runs at a time.
let s:done_cb = 0

" ================================
" Public: Download all exercises
" ================================
function! tmc#download#course_exercises(course_id, org, cb) abort
  let l:cli = tmc#cli#ensure()

  if empty(a:course_id)
    call tmc#util#echo_error('No course ID provided')
    call a:cb('')
    return
  endif

  if tmc#job#is_running(s:KIND)
    call tmc#util#echo_warning('A TMC download is already in progress')
    call tmc#panel#show(s:KIND)
    return
  endif

  " Get all exercises and count locked vs available
  let l:all_exercises = tmc#exercise#get_list(a:course_id)
  let l:total_count = len(l:all_exercises)

  " Get only available (unlocked) exercises to avoid 403 Forbidden errors
  let l:exercise_ids = tmc#exercise#get_available_ids(a:course_id)
  let l:available_count = len(l:exercise_ids)
  let l:locked_count = l:total_count - l:available_count

  if empty(l:exercise_ids)
    call tmc#util#echo_info('No available exercises to download for course ' . a:course_id
          \ . ' (all ' . l:total_count . ' are locked)')
    call a:cb('')
    return
  endif

  if l:locked_count > 0
    call tmc#util#echo_info('Downloading ' . l:available_count
          \ . ' available exercises (skipping ' . l:locked_count . ' locked)')
  else
    call tmc#util#echo_info('Downloading all ' . l:available_count . ' exercises')
  endif

  call tmc#panel#open(s:KIND, 'Download · course ' . a:course_id)
  call tmc#panel#reset(s:KIND)
  call tmc#progress#start(s:KIND, printf('Downloading %d exercises…', l:available_count))

  let l:args = [l:cli, 'tmc',
        \ '--client-name', g:tmc_client_name,
        \ '--client-version', g:tmc_client_version,
        \ 'download-or-update-course-exercises']
  for l:id in l:exercise_ids
    call extend(l:args, ['--exercise-id', l:id])
  endfor

  let s:done_cb = a:cb
  call tmc#job#start(s:KIND, l:args, {
        \ 'meta': {'course_id': a:course_id, 'org': a:org, 'expected': l:available_count},
        \ 'on_line': function('s:on_line'),
        \ 'on_exit': function('s:on_exit'),
        \ })
endfunction

" ================================
" Streaming output
" ================================
function! s:on_line(kind, line) abort
  try
    let l:obj = json_decode(a:line)
  catch
    return
  endtry

  let l:okind = get(l:obj, 'output-kind', '')
  if l:okind ==# 'status-update'
    let l:msg = get(l:obj, 'message', '')
    call tmc#progress#update(a:kind, tmc#progress#percent_of(l:obj), l:msg)
    if !empty(l:msg)
      call tmc#panel#append(a:kind, '⏳ ' . l:msg)
    endif
  elseif l:okind ==# 'output-data'
    call tmc#job#set_result(a:kind, l:obj)
  endif
endfunction

" ================================
" Completion
" ================================
function! s:on_exit(kind, code) abort
  let l:meta = tmc#job#meta(a:kind)
  let l:summary = s:print_summary(a:kind)

  call tmc#progress#finish(a:kind, l:summary)
  call tmc#notify#result(a:kind, l:summary =~# '^✅', l:summary)

  " Hand control back to the picker flow (cd into the course, list exercises).
  let l:cb = s:done_cb
  let s:done_cb = 0
  if type(l:cb) == v:t_func
    call call(l:cb, [get(l:meta, 'course_id', '')])
  endif
endfunction

function! s:print_summary(kind) abort
  let l:downloaded = 0
  let l:skipped = 0
  let l:failed = 0
  let l:perm_failures = 0

  let l:res = tmc#job#result(a:kind)
  let l:data = {}
  if type(l:res) == type({}) && has_key(l:res, 'data') && type(l:res['data']) == type({})
    let l:data = get(l:res['data'], 'output-data', {})
  endif

  if type(l:data) == type({}) && !empty(l:data)
    if has_key(l:data, 'downloaded')
      let l:downloaded = len(l:data['downloaded'])
      call tmc#panel#append(a:kind, ['', '--- Downloaded ---'])
      for l:item in l:data['downloaded']
        call tmc#panel#append(a:kind, '  ✅ ' . get(l:item, 'exercise-slug', '?'))
      endfor
    endif

    if has_key(l:data, 'skipped') && !empty(l:data['skipped'])
      let l:skipped = len(l:data['skipped'])
      call tmc#panel#append(a:kind, ['', '--- Skipped ---'])
      for l:item in l:data['skipped']
        call tmc#panel#append(a:kind, '  ⚠️  ' . get(l:item, 'exercise-slug', '?'))
      endfor
    endif

    if has_key(l:data, 'failed') && !empty(l:data['failed'])
      let l:failed = len(l:data['failed'])
      call tmc#panel#append(a:kind, ['', '--- Failed ---'])
      for l:failure in l:data['failed']
        let l:info = l:failure[0]
        let l:reason = join(l:failure[1], ' ')
        if l:reason =~? '403 Forbidden'
          let l:perm_failures += 1
        endif
        call tmc#panel#append(a:kind,
              \ '  ❌ ' . get(l:info, 'exercise-slug', '?') . ': ' . l:reason)
      endfor
    endif
  endif

  let l:summary = printf('%s %d downloaded, %d skipped, %d failed',
        \ l:failed == 0 ? '✅' : '❌', l:downloaded, l:skipped, l:failed)

  call tmc#panel#append(a:kind, ['', '--- Summary ---', l:summary])

  if l:perm_failures > 0
    call tmc#panel#append(a:kind,
          \ '💡 Note: Some failures may be due to exercises requiring you to submit previous ones first.')
  endif

  return l:summary
endfunction

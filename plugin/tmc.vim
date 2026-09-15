scriptencoding utf-8

" plugin/tmc.vim
" Entry points for commands and mappings
" Author: Daniel Koch (github: Ukonhattu)

if exists('g:loaded_tmc_plugin')
  finish
endif
let g:loaded_tmc_plugin = 1

" ===========================
" Commands
" ===========================

" Run tests for current exercise
command! TmcRunTests call tmc#run_tests_current()

" Submit current exercise
command! TmcSubmit call tmc#submit_current()

" Download all exercises for a course (requires course ID and org)
command! -nargs=+ TmcDownload call tmc#course_exercises(<f-args>)

" Pick course (organization → course → auto download)
command! TmcPickCourse call tmc#pick_course_command()

" Pick only organization
command! TmcPickOrganization call tmc#pick_organization_command()

" List courses for current organization
command! TmcListCourses call tmc#list_courses()

" List exercises for a course ID
command! -nargs=1 TmcListExercises call tmc#list_exercises(<f-args>)

" Login to TMC
command! -nargs=? TmcLogin call tmc#login(<f-args>)
command! TmcLogout call tmc#logout()
command! TmcStatus call tmc#status()

" Change to course directory

command! TmcCdCourse call tmc#cd_course()

command! TmcPaste call tmc#paste_current()

" Inspect resolved projects directory (for debugging)
command! TmcProjectsDir echo tmc#projects_dir()

" Show / minimize the result panels
command! -nargs=? -complete=customlist,tmc#panel#complete TmcPanel
      \ call tmc#toggle_panel(<f-args>)

" --- Aliases that match README / common naming ---
command! -nargs=0 TmcCourses     call tmc#list_courses()
command! -nargs=1 TmcExercises   call tmc#list_exercises(<f-args>)
command! -nargs=0 TmcPickOrg     call tmc#pick_organization_command()

" ===========================
" Key Mappings (optional)
" ===========================
" Provide <Plug> targets so users can remap cleanly
nnoremap <silent> <Plug>(tmc-run-tests)        :TmcRunTests<CR>
nnoremap <silent> <Plug>(tmc-submit-current)   :TmcSubmit<CR>
nnoremap <silent> <Plug>(tmc-toggle-panel)     :TmcPanel<CR>

" Default leader mappings (can be disabled)
"
" Set through nvim_set_keymap rather than :nmap so each one carries a 'desc'.
" which-key renders those as the entry labels; without them <leader>t shows up
" as a bare "+3 keymaps". 'noremap' must stay false for the <Plug> targets to
" resolve.
if !get(g:, 'tmc_disable_default_mappings', 0)
  let s:tmc_maps = [
        \ ['<leader>tt', '<Plug>(tmc-run-tests)',      'Run tests'],
        \ ['<leader>ts', '<Plug>(tmc-submit-current)', 'Submit exercise'],
        \ ['<leader>tw', '<Plug>(tmc-toggle-panel)',   'Toggle TMC panel'],
        \ ]
  for s:m in s:tmc_maps
    call nvim_set_keymap('n', s:m[0], s:m[1],
          \ {'desc': s:m[2], 'silent': v:true, 'noremap': v:false})
  endfor
  unlet s:tmc_maps s:m

  " Name the <leader>t group in which-key, if it is in use. pcall'd so that
  " sourcing this file without the plugin's lua/ on 'runtimepath' degrades to
  " an unnamed group rather than an error at startup.
  lua pcall(function() require('tmc.whichkey').register() end)
endif


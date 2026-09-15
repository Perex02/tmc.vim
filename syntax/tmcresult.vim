
" Syntax highlighting for TMC test/download results
"
" Panel content is indented by autoload/tmc/panel.vim. Rules therefore accept
" leading whitespace, but must exclude it from the match with '\zs': a linked
" group with a background (DiffText on the Submit button, say) would otherwise
" paint that padding too and the highlight would run to the window border.

if exists("b:current_syntax")
  finish
endif

" ✅ Passed
syntax match TmcPass /^\s*\zs✅.*$/
highlight def link TmcPass DiffAdded

" ❌ Failed
syntax match TmcFail /^\s*\zs❌.*$/
highlight def link TmcFail DiffRemoved

" ⏳ Progress / downloading
syntax match TmcProgress /^\s*\zs⏳.*$/
highlight def link TmcProgress WarningMsg

" ⚠️ Skipped
syntax match TmcSkipped /^\s*\zs⚠️.*$/
highlight def link TmcSkipped Todo

" 💡 Notes
syntax match TmcNote /^\s*\zs💡.*$/
highlight def link TmcNote Comment

" Headers like --- Summary ---
syntax match TmcHeader /^\s*\zs--- .* ---$/
highlight def link TmcHeader Title

" Log labels (Stdout, Stderr)
syntax match TmcLog /^\s\+\zs\(Stdout\|Stderr\):/
highlight def link TmcLog Comment

" Progress bar: filled / empty track, and the percentage beside it
syntax match TmcBarFill /█\+/
highlight def link TmcBarFill Statement

syntax match TmcBarEmpty /░\+/
highlight def link TmcBarEmpty NonText

syntax match TmcPercent /\d\{1,3}%$/
highlight def link TmcPercent Number

" Submit action button
syntax match TmcButton /^\s*\zsSubmit (⏎)$/
highlight def link TmcButton DiffText

" Raw CLI passthrough lines
syntax match TmcInfo /^\s*\zsℹ.*$/
highlight def link TmcInfo Comment

let b:current_syntax = "tmcresult"


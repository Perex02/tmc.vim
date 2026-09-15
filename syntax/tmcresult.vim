
" Syntax highlighting for TMC test/download results

if exists("b:current_syntax")
  finish
endif

" ✅ Passed
syntax match TmcPass /^✅.*$/
highlight def link TmcPass DiffAdded

" ❌ Failed
syntax match TmcFail /^❌.*$/
highlight def link TmcFail DiffRemoved

" ⏳ Progress / downloading
syntax match TmcProgress /^⏳.*$/
highlight def link TmcProgress WarningMsg

" ⚠️ Skipped
syntax match TmcSkipped /^⚠️.*$/
highlight def link TmcSkipped Todo

" 💡 Notes
syntax match TmcNote /^💡.*$/
highlight def link TmcNote Comment

" Headers like --- Summary ---
syntax match TmcHeader /^--- .* ---$/
highlight def link TmcHeader Title

" Log labels (Stdout, Stderr)
syntax match TmcLog /^\s\+\(Stdout\|Stderr\):/
highlight def link TmcLog Comment

" Progress bar: filled / empty track, and the percentage beside it
syntax match TmcBarFill /█\+/
highlight def link TmcBarFill Statement

syntax match TmcBarEmpty /░\+/
highlight def link TmcBarEmpty NonText

syntax match TmcPercent /\d\{1,3}%$/
highlight def link TmcPercent Number

" [Submit (s)] action button
syntax match TmcButton /^\[Submit (s)\]$/
highlight def link TmcButton DiffText

" Raw CLI passthrough lines
syntax match TmcInfo /^ℹ.*$/
highlight def link TmcInfo Comment

let b:current_syntax = "tmcresult"


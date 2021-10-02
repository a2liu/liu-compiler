if exists("b:did_indent")
  finish
endif
let b:did_indent = 1

setlocal nosmartindent
setlocal nolisp
setlocal autoindent
setlocal shiftwidth=4

setlocal indentexpr=GetLiuIndent(v:lnum)

if exists("*GetLiuIndent")
  finish
endif

function! GetLiuIndent(lnum)
  let prev = prevnonblank(a:lnum-1)

  if prev == 0
    return 0
  endif

  let prevline = getline(prev)
  let line = getline(a:lnum)

  let ind = indent(prev)

  if prevline =~ '[({]\s*$'
    let ind += &shiftwidth
  endif

  if line =~ '^\s*[)}]'
    let ind -= &shiftwidth
  endif

  return ind
endfunction

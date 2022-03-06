if exists("b:current_syntax")
  finish
endif

syntax keyword liuStruct struct
syntax keyword liuType type
syntax keyword liuEnum enum
syntax keyword liuLet let

syntax keyword liuIf if
syntax keyword liuElse else
syntax keyword liuFor for
syntax keyword liuProc proc nextgroup=liuProcName skipwhite skipempty

syntax keyword liuDataType string u8 u16 u32 u64 s8 s16 s32 s64 bool
syntax keyword liuBool true false
syntax keyword liuNone none

syntax keyword liuReturn return
syntax keyword liuDefer defer

syntax keyword liuIt it

syntax region liuString start=/\v"/ skip=/\v\\./ end=/\v"/

syntax match liuProcName "[a-zA-Z_][a-zA-Z0-9_]*" display contained

syntax match liuTagNote "@\<\w\+\>" display

syntax match liuClass "\v<[A-Z]\w+>" display
syntax match liuConstant "\v<[A-Z0-9,_]+>" display

syntax match liuInteger "\<\d\+\>" display
syntax match liuFloat "\<[0-9][0-9_]*\%(\.[0-9][0-9_]*\)\%([eE][+-]\=[0-9_]\+\)\=" display
syntax match liuHex "\<0x[0-9A-Fa-f]\+\>" display

syntax match liuDirective "#\<\w\+\>" display

syntax match liuCommentNote "@\<\w\+\>" contained display
syntax match liuLineComment "//.*" contains=liuCommentNote
syntax region liuBlockComment start=/\v\/\*/ end=/\v\*\// contains=liuBlockComment, liuCommentNote

highlight def link liuIt Keyword
highlight def link liuCast Keyword
highlight def link liuReturn Keyword
highlight def link liuDefer Keyword
highlight def link liuProc Keyword

highlight def link liuString String

highlight def link liuStruct Structure
highlight def link liuEnum Structure
highlight def link liuLet Keyword

highlight def link liuProcName Function

highlight def link liuDirective Macro
highlight def link liuIf Conditional
highlight def link liuThen Conditional
highlight def link liuElse Conditional
highlight def link liuFor Repeat

highlight def link liuLineComment Comment
highlight def link liuBlockComment Comment
highlight def link liuCommentNote Todo

highlight def link liuClass Type
highlight def link liuTemplate Constant

highlight def link liuTagNote Identifier
highlight def link liuDataType Type
highlight def link liuBool Boolean
highlight def link liuConstant Constant
highlight def link liuNone Constant
highlight def link liuInteger Number
highlight def link liuFloat Float
highlight def link liuHex Number

let b:current_syntax = "liu"

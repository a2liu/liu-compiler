// based on https://github.com/mpaland/printf/blob/master/printf.c

write :: (thing: *$T, fmt: string, args: .. Any) {
    fmt_bytes : [] u8 = ---;
    fmt_bytes.data = fmt.data;
    fmt_bytes.count = fmt.count;
    assert(try_write(thing, fmt_bytes));
    assert(args.count == 0);
}

#scope_file

PrintFlags :: enum_flags u32 {
    ZEROPAD;
    LEFT;
    PLUS;
    SPACE;
    HASH;
    UPPERCASE;
    CHAR;
    SHORT;
    LONG;
    LONG_LONG;
    PRECISION;
    ADAPT_EXP;
}



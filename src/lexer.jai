#import "Basic";
#import "hashmap";

Symbols :: struct {
    symbol_to_name : [..] string;
    name_to_symbol : Map(string, s64);
}

symbol_table :: () -> Symbols {
    syms : Symbols;
    array_reserve(*syms.symbol_to_name, 64);
    map_reserve(*syms.name_to_symbol, 64);

    return syms;
}

Token :: struct {
    Kind :: enum {
        ERROR;

        FOR;
        IF;
        ELSE;
        DEFER;
        GO;
        LET;
        MATCH;
        TYPE;

        OR;
        XOR;
        AND;
        NOT;

        TRUE_VALUE;
        FALSE_VALUE;
        NONE_VALUE;

        STRING_TYPE;
        ANY_TYPE;
        VOID_TYPE;
        BOOL_TYPE;
        S64_TYPE;

        SPACE_OR_TAB;
        NEWLINE;
        SEMICOLON;

        IDENT;
        INTEGER_LITERAL;
        FLOAT_LITERAL;
        STRING_LITERAL;
        RANGE;

        DOT;
        COMMA;
        COLON;
        AMPERSAND;
        DOUBLE_AMPERSAND;
        VERTICAL;
        DOUBLE_VERTICAL;
        STAR;
        PERCENT;
        MINUS;
        PLUS;
        DIVIDE;
        LEFT_SHIFT;
        RIGHT_SHIFT;

        EQUALS;
        NOT_EQUALS;
        DOUBLE_EQUALS;
        LESS_THAN;
        LEQ_THAN;
        GREATER_THAN;
        GEQ_THAN;
        LEFT_ARROW;
        RIGHT_ARROW;
        RIGHT_DOUBLE_ARROW;

        LBRACE;
        RBRACE;
        LBRACKET;
        RBRACKET;
        LPAREN;
        RPAREN;

        // Unused
        DOT_DOT_EQUAL;
        TILDE;
        TICK;
        EXCLAMATION;
        DOLLAR;
        HASH;
        QUESTION;
        CARET;
        A_CIRCLE;
        BACKSLASH;
        LEFT_DOUBLE_ARROW;
    }

    Data :: union {
        integer_value : u64;
        float_value : float64;
        string_value : string;
        ident_symbol : s64;
    }

    kind : Kind = .ERROR;
    data : Data;
    file: s64;
    line: s32;
    character: s32;
}

Lexer :: struct {
    symbols : Symbols;
    file_data : string;
    cursor : s64 = 0;
    line: s32 = 0;
    character: s32 = 0;

    make :: (text: string) -> Lexer {
        lexer : Lexer;
        lexer.symbols = symbol_table();
        lexer.file_data = text;

        return lexer;
    }
}

parse_number :: (lexer: *Lexer) -> bool, u64 {
    value : u64;

    return true, value;
}


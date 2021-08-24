#import "Basic";
#import "hashmap";

Symbols :: struct {
    symbol_to_name : [..] string;
    name_to_symbol : Map(string, s64);

    make :: () -> Symbols {
        syms : Symbols;
        syms.name_to_symbol = empty_map(string, s64, capacity = 64);
        array_reserve(*syms.symbol_to_name, 64);

        return syms;
    }
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
    begin: s32; end: s32;
}

has_members :: ($T: Type, members: .. string) -> bool {
    info := type_info(T);
    for member_name: members {
        member := get_field(info, member_name);
        if !member    return false;
        if member.type != s32     return false;
    }

    return true;
}

ResultSpan :: struct(Inner: Type) {
    #if #run type_info(Inner).type == .STRUCT {
        using value: Inner;
        #if !has_members(Inner, "begin", "end") {
            begin: s32;
            end: s32;
        }
    } else {
        value: Inner;
        begin: s32;
        end: s32;
    }
    did_succeed: bool = true;
    was_final: bool = false; // unused by lexer
    fail_message: string;
}

Lexer :: struct {
    symbols : Symbols;
    file_data : string;
    cursor : s32 = 0;
    line: s32 = 0;
    line_offset: s32 = 0;

    make :: (text: string) -> Lexer {
        lexer : Lexer;
        lexer.symbols = Symbols.make();
        lexer.file_data = text;

        return lexer;
    }
}

start_result :: (lexer: *Lexer, $type: Type) -> ResultSpan(type) #expand {
    result : ResultSpan(type);
    result.was_final = true;
    result.begin = lexer.cursor;
    result.end = lexer.cursor;

    return result;
}

lex_number :: (lexer: *Lexer) -> ResultSpan(u64) {
    result := start_result(lexer, u64);

    char := expect(lexer);
    assert(#char "0" <= char && char <= #char "9");
    result.value = char - #char "0";

    while true {
        success, char := peek(lexer);
        if char < #char "0" || #char "9" < char     break;

        new_value := result.value * 10 + (char - #char "0");
        if new_value < result.value {
            result.did_succeed = false;
            result.fail_message = "value was too big";
            return result;
        }

        result.value = new_value;
        expect(lexer);
    }

    return result;
}


#scope_file

check :: (result: ResultSpan($T)) -> T #expand {
    if result.did_succeed {
        return result.value;
    }

    if result.was_final     `return result;
}

check :: (lexer: *Lexer, success : bool, message: string, was_final := false) #expand {
    result := `result;

    if !success {
        result.did_succeed = false;
        result.was_final = result.was_final || was_final;
        result.end = lexer.cursor;
        result.fail_message = message;

        `return result;
    }
}

pop :: (lexer: *Lexer) -> bool, u8 #expand {
    result := `result;

    if lexer.cursor >= lexer.file_data.count {
        return false, 0;
    }

    value := lexer.file_data[lexer.cursor];
    if value == {
    case #char "\n";
        lexer.line += 1;
        lexer.line_offset = 0;
    case #char "\r";
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor + 1] == #char "\n" {
            lexer.cursor += 1;
            value = #char "\n";
        } else {
            result.did_succeed = false;
            result.was_final = true;
            result.end = lexer.cursor;
            result.fail_message = "got '\\r' character in place we weren't expecting";

            `return result;
        }
    case;
        lexer.line_offset += 1;
    }

    lexer.cursor += 1;
    return true, value;
}

expect :: (lexer: *Lexer) -> u8 #expand {
    result := `result;

    if lexer.cursor >= lexer.file_data.count {
        result.did_succeed = false;
        result.was_final = true;
        result.end = lexer.cursor;
        result.fail_message = "reached end of file while still lexing something";

        `return result;
    }

    value := lexer.file_data[lexer.cursor];
    lexer.cursor += 1;

    if value == {
    case #char "\n";
        lexer.line += 1;
        lexer.line_offset = 0;
    case #char "\r";
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor + 1] == #char "\n" {
            value = #char "\n";
            lexer.line += 1;
            lexer.line_offset = 0;
            lexer.cursor += 1;
        } else {
            result.did_succeed = false;
            result.was_final = true;
            result.end = lexer.cursor;
            result.fail_message = "got '\\r' character in place we weren't expecting";

            `return result;
        }
    case;
        lexer.line_offset += 1;
    }

    return value;
}

peek :: (lexer: *Lexer) -> bool, u8 #expand {
    result := `result;

    if lexer.cursor >= lexer.file_data.count {
        return false, 0;
    }

    value := lexer.file_data[lexer.cursor];
    if value == #char "\r" {
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor + 1] == #char "\n" {
            value = #char "\n";
        } else {
            result.did_succeed = false;
            result.was_final = true;
            result.end = lexer.cursor;
            result.fail_message = "got '\\r' character in place we weren't expecting";

            `return result;
        }
    }

    return true, value;
}

#import "Basic";
#import "hashmap";

keywords : Map(string, Token.Kind);

UNDERSCORE_SYMBOL : s32 : 0;
IT_SYMBOL : s32 : 1;
IDX_SYMBOL : s32 : 2;

lexer_init :: () {
    keywords = empty_map(string, Token.Kind, capacity = 64);

    map_add(*keywords, "for", .FOR);
    map_add(*keywords, "if", .IF);
    map_add(*keywords, "else", .ELSE);
    map_add(*keywords, "defer", .DEFER);
    map_add(*keywords, "go", .GO);
    map_add(*keywords, "let", .LET);
    map_add(*keywords, "match", .MATCH);
    map_add(*keywords, "type", .TYPE);

    map_add(*keywords, "or", .OR);
    map_add(*keywords, "xor", .XOR);
    map_add(*keywords, "and", .AND);
    map_add(*keywords, "not", .NOT);

    map_add(*keywords, "true", .TRUE_VALUE);
    map_add(*keywords, "false", .FALSE_VALUE);
    map_add(*keywords, "none", .NONE_VALUE);

    map_add(*keywords, "string", .STRING_TYPE);
    map_add(*keywords, "any", .ANY_TYPE);
    map_add(*keywords, "void", .VOID_TYPE);
    map_add(*keywords, "bool", .BOOL_TYPE);
    map_add(*keywords, "s64", .S64_TYPE);
}

Symbols :: struct {
    symbol_to_name : [..] string;
    name_to_symbol : Map(string, s32);

    make :: () -> Symbols {
        syms : Symbols;
        syms.name_to_symbol = empty_map(string, s32, capacity = 64);
        array_reserve(*syms.symbol_to_name, 64);

        assert(UNDERSCORE_SYMBOL == add_symbol(*syms, "_"));
        assert(IT_SYMBOL == add_symbol(*syms, "it"));
        assert(IDX_SYMBOL == add_symbol(*syms, "idx"));

        return syms;
    }
}

Token :: struct {
    Kind :: enum {
        ERROR;
        EOF;

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
    using data : Data;
    file: s32;
    begin: s32;
    end: s32;
}

has_members :: ($T: Type, members: .. string) -> bool {
    info := type_info(T);

    for member_name: members {
        member := get_field(info, member_name);
        if !member      return false;
        if member.type != type_info(s32)    return false;
    }

    return true;
}

ResultSpan :: struct(Inner: Type) {
    #if #run type_info(Inner).type == .STRUCT {
        using value: Inner;
        #if #run !has_members(Inner, "file") {
            file: s32;
        }
        #if #run !has_members(Inner, "begin") {
            begin: s32;
        }
        #if #run !has_members(Inner, "end") {
            end: s32;
        }
    } else {
        value: Inner;
        begin: s32;
        end: s32;
    }

    did_succeed: bool = true;
    was_final: bool = false; // unused by lexer
    fail_message: string = "";
}

Lexer :: struct {
    symbols : Symbols;
    file_data : string;
    cursor : s32 = 0;
    file: s32;
    line: s32 = 0;
    line_offset: s32 = 0;

    make :: (text: string) -> Lexer {
        lexer : Lexer;
        lexer.symbols = Symbols.make();
        lexer.file_data = text;

        return lexer;
    }
}

start_result :: (lexer: *Lexer, $type: Type) -> ResultSpan(type) {
    result : ResultSpan(type);
    result.file = lexer.file;
    result.was_final = true;
    result.begin = lexer.cursor;
    result.end = lexer.cursor;

    return result;
}

lex_number :: (lexer: *Lexer) -> ResultSpan(u64) {
    result := start_result(lexer, u64);

}

lex_token :: (lexer: *Lexer) -> ResultSpan(Token) {
    return lex_raw_token(lexer);
}

lex_raw_token :: (lexer: *Lexer) -> ResultSpan(Token) {
    result := start_result(lexer, Token);
    success, char := pop(lexer);
    if !success {
        result.kind = .EOF;
        return result;
    }

    if char == {
    case #char " "; #through;
    case #char "\t";
        result.kind = .SPACE_OR_TAB;
        while match(lexer, char == #char " " || char == #char "\t") {}

        return result;

    case #char "\n";
        result.kind = .NEWLINE;
        return result;

    case #char ";";
        result.kind = .SEMICOLON;
        return result;

    case #char ",";
        result.kind = .COMMA;
        return result;

    case #char ".";
        if match(lexer, #char ".") {
            result.kind = .RANGE;
            return result;
        }

        result.kind = .DOT;
        return result;

    case #char "=";
        if match(lexer, #char "=") {
            result.kind = .DOUBLE_EQUALS;
            return result;
        }

        result.kind = .EQUALS;

    case #char "{";
        result.kind = .LBRACE;
        return result;
    case #char "}";
        result.kind = .RBRACE;
        return result;

    case #char "[";
        result.kind = .LBRACKET;
        return result;
    case #char "]";
        result.kind = .RBRACKET;
        return result;

    case #char "(";
        result.kind = .LPAREN;
        return result;
    case #char ")";
        result.kind = .RPAREN;
        return result;
    }

    if #char "0" <= char && char <= #char "9" {
        value : u64 = char - #char "0";

        while true {
            success, char := peek(lexer);
            if char < #char "0" || #char "9" < char     break;
            expect(lexer);

            new_value := value * 10 + (char - #char "0");
            if new_value < value {
                result.did_succeed = false;
                result.fail_message = "value was too big";

                return result;
            }

            value = new_value;
        }

        result.kind = .INTEGER_LITERAL;
        result.integer_value = value;
        return result;
    }

    match_id_char_begin :: #code (#char "a" <= char && char <= #char "z")
        || (#char "A" <= char && char <= #char "Z")
        || char == #char "_";
    match_id_char :: #code (#char "a" <= char && char <= #char "z")
        || (#char "A" <= char && char <= #char "Z")
        || char == #char "_" || (#char "0" <= char && char <= #char "9");

    if #insert match_id_char_begin {
        ident_string : string = ---;
        ident_string.data = lexer.file_data.data + result.begin;
        ident_string.count = 1;

        while match(lexer, match_id_char)   ident_string.count += 1;

        success, keyword_kind := map_find(*keywords, ident_string);
        if success {
            result.kind = keyword_kind;
            return result;
        }

        result.kind = .IDENT;
        result.ident_symbol = add_symbol(*lexer.symbols, ident_string);

        return result;
    }

    result.kind = .ERROR;
    result.did_succeed = false;
    result.fail_message = "didn't recognize the character";
    return result;
}

#scope_file

add_symbol :: (syms: *Symbols, ident: string) -> s32 {
    found, sym := map_find(*syms.name_to_symbol, ident);
    if found    return sym;

    sym = cast,trunc(s32) syms.symbol_to_name.count;
    array_add(*syms.symbol_to_name, ident);
    map_set(*syms.name_to_symbol, ident, sym);

    return sym;
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

match :: (lexer: *Lexer, to_match: u8) -> bool #expand {
    if lexer.cursor >= lexer.file_data.count    return false;

    original_cursor := lexer.cursor;
    char := lexer.file_data[lexer.cursor];
    lexer.cursor += 1;

    if char == {
    case #char "\n";
        lexer.line += 1;
        lexer.line_offset = 0;
    case #char "\r";
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor + 1] == #char "\n" {
            char = #char "\n";
            lexer.line += 1;
            lexer.line_offset = 0;
            lexer.cursor += 1;
        } else {
            result := `result;
            result.did_succeed = false;
            result.was_final = true;
            result.end = lexer.cursor;
            result.fail_message = "got '\\r' character in place we weren't expecting";

            `return result;
        }
    case;
        lexer.line_offset += 1;
    }

    if char == to_match {
        `result.end = lexer.cursor;
        return true;
    }

    lexer.cursor = original_cursor;
    `result.end = lexer.cursor;
    return false;
}

match :: (lexer: *Lexer, pattern: Code) -> bool #expand {
    if lexer.cursor >= lexer.file_data.count    return false;

    original_cursor := lexer.cursor;
    char := lexer.file_data[lexer.cursor];
    lexer.cursor += 1;

    if char == {
    case #char "\n";
        lexer.line += 1;
        lexer.line_offset = 0;
    case #char "\r";
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor + 1] == #char "\n" {
            char = #char "\n";
            lexer.line += 1;
            lexer.line_offset = 0;
            lexer.cursor += 1;
        } else {
            result := `result;
            result.did_succeed = false;
            result.was_final = true;
            result.end = lexer.cursor;
            result.fail_message = "got '\\r' character in place we weren't expecting";

            `return result;
        }
    case;
        lexer.line_offset += 1;
    }

    if #insert_internal pattern {
        `result.end = lexer.cursor;
        return true;
    }

    lexer.cursor = original_cursor;
    `result.end = lexer.cursor;
    return false;
}

pop :: (lexer: *Lexer) -> bool, u8 #expand {
    if lexer.cursor >= lexer.file_data.count    return false, 0;

    result := `result;
    value := lexer.file_data[lexer.cursor];
    lexer.cursor += 1;

    if value == {
    case #char "\n";
        lexer.line += 1;
        lexer.line_offset = 0;
    case #char "\r";
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor] == #char "\n" {
            lexer.cursor += 1;
            lexer.line += 1;
            lexer.line_offset = 0;
            value = #char "\n";
        } else {
            result.did_succeed = false;
            result.was_final = true;
            result.fail_message = "got '\\r' character in place we weren't expecting";
            result.end = lexer.cursor;

            `return result;
        }
    case;
        lexer.line_offset += 1;
    }

    `result.end = lexer.cursor;
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
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor] == #char "\n" {
            lexer.cursor += 1;
            value = #char "\n";
            lexer.line += 1;
            lexer.line_offset = 0;
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

    `result.end = lexer.cursor;
    return value;
}

peek :: (lexer: *Lexer) -> bool, u8 #expand {
    if lexer.cursor >= lexer.file_data.count    return false, 0;

    result := `result;
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

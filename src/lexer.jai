#import "gone";
#import "Basic";
#import "hashmap";
#import "strings";
#import "write";

keywords : Map(string, Token.Kind);

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
    map_add(*keywords, "deref", .DEREF);
    map_add(*keywords, "break", .BREAK);
    map_add(*keywords, "continue", .CONTINUE);
    map_add(*keywords, "throw", .THROW);

    map_add(*keywords, "or", .OR);
    map_add(*keywords, "and", .AND);
    map_add(*keywords, "bitor", .BIT_OR);
    map_add(*keywords, "bitxor", .BIT_XOR);
    map_add(*keywords, "bitand", .BIT_AND);

    map_add(*keywords, "true", .TRUE_VALUE);
    map_add(*keywords, "false", .FALSE_VALUE);
    map_add(*keywords, "none", .NONE_VALUE);

    map_add(*keywords, "string", .STRING_TYPE);
    map_add(*keywords, "any", .ANY_TYPE);
    map_add(*keywords, "void", .VOID_TYPE);
    map_add(*keywords, "bool", .BOOL_TYPE);
    map_add(*keywords, "s64", .S64_TYPE);
}

Token :: struct {
    Kind :: enum u8 {
        EOF;
        LINE_COMMENT;
        BLOCK_COMMENT;
        WHITESPACE;

        FOR;
        IF;
        ELSE;
        DEFER;
        THROW;
        GO;
        LET;
        MATCH;
        TYPE;
        DEREF;
        BREAK;
        CONTINUE;
        RETURN;

        OR;
        AND;
        BIT_OR;
        BIT_XOR;
        BIT_AND;

        TRUE_VALUE;
        FALSE_VALUE;
        NONE_VALUE;

        STRING_TYPE;
        ANY_TYPE;
        VOID_TYPE;
        BOOL_TYPE;
        S64_TYPE;

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
        EXCLAMATION;
        TILDE;
        STAR;
        DOUBLE_STAR;
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
        RIGHT_ARROW;
        RIGHT_DOUBLE_ARROW;

        LBRACE; // {
        RBRACE;
        LBRACKET; // [
        RBRACKET;
        LPAREN;
        RPAREN;

        // Unused
        DOT_DOT_EQUAL;
        TICK;
        DOLLAR;
        QUESTION;
        CARET;
        LEFT_ARROW;
        A_CIRCLE;
        BACKSLASH;
        AMPERSAND;
        DOUBLE_AMPERSAND;
        VERTICAL;
        DOUBLE_VERTICAL;
    }

    Data :: union {
        integer_value : u64;
        float_value : float64;
        string_value : string;
        ident_symbol : s32;
    }

    kind : Kind = .EOF;
    using data : Data;
    begin : s32;
    end : s32;
}

Lexer :: struct {
    symbols : *Symbols;
    file_data : string;
    cursor : s32 = 0;
    line: s32 = 0;
    line_offset: s32 = 0;

    make :: (text: string, symbols: *Symbols) -> Lexer {
        lexer : Lexer;
        lexer.symbols = symbols;
        lexer.file_data = text;

        return lexer;
    }
}

lex_token :: (lexer: *Lexer) -> Result(Token) {
    while true {
        result := lex_raw_token(lexer);
        if !result.did_succeed      return result;

        if result.kind == {
            case .WHITESPACE;     continue;
            case .LINE_COMMENT;     continue;
            case .BLOCK_COMMENT;    continue;
        }

        return result;
    }
}

lex_raw_token :: (lexer: *Lexer) -> Result(Token) {
    result := start_result(lexer, Token);
    success, char := pop(lexer);
    if !success {
        result.kind = .EOF;
        return result;
    }

    if char == {
    case #char " "; #through;
    case #char "\t";
        result.kind = .WHITESPACE;
        while match(lexer, char == #char " " || char == #char "\t") {}

        return result;

    case #char "/";
        if match(lexer, #char "*") {
            while true {
                success, char = pop(lexer);
                if !success {
                    result.did_succeed = false;
                    result.error = "block comments need to end with a '*/'";
                    return result;
                }

                if char == #char "*" && match(lexer, #char "/") {
                    result.kind = .BLOCK_COMMENT;
                    return result;
                }
            }
        }

        if match(lexer, #char "/") {
            while true {
                success, char = pop(lexer);
                if !success     break;
                if char == #char "\n"   break;
            }

            result.kind = .LINE_COMMENT;
            return result;
        }

        result.kind = .DIVIDE;
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
            if match(lexer, #char "=") {
                result.kind = .DOT_DOT_EQUAL;
                return result;
            }

            result.kind = .RANGE;
            return result;
        }

        result.kind = .DOT;
        return result;

    case #char ":";
        result.kind = .COLON;
        return result;

    case #char "=";
        if match(lexer, #char "=") {
            result.kind = .DOUBLE_EQUALS;
            return result;
        }

        if match(lexer, #char ">") {
            result.kind = .RIGHT_DOUBLE_ARROW;
            return result;
        }

        result.kind = .EQUALS;
        return result;

    case #char "<"; // @Todo should the lexer try to prevent you from doing stupid stuff
        if match(lexer, #char "=") {
            result.kind = .LEQ_THAN;
            return result;
        }

        if match(lexer, #char "-") {
            result.kind = .LEFT_ARROW;
            return result;
        }

        if match(lexer, #char "<") {
            result.kind = .LEFT_SHIFT;
            return result;
        }

        result.kind = .LESS_THAN;
        return result;

    case #char ">";
        if match(lexer, #char "=") {
            result.kind = .GEQ_THAN;
            return result;
        }

        if match(lexer, #char ">") {
            result.kind = .RIGHT_SHIFT;
            return result;
        }

        result.kind = .GREATER_THAN;
        return result;

    case #char "~";
        result.kind = .TILDE;
        return result;

    case #char "!";
        if match(lexer, #char "=") {
            result.kind = .NOT_EQUALS;
            return result;
        }

        result.kind = .EXCLAMATION;
        return result;

    case #char "+";
        result.kind = .PLUS;
        return result;

    case #char "-";
        if match(lexer, #char ">") {
            result.kind = .RIGHT_ARROW;
            return result;
        }

        result.kind = .MINUS;
        return result;

    case #char "*";
        if match(lexer, #char "*") {
            result.kind = .DOUBLE_STAR;
            return result;
        }

        result.kind = .STAR;
        return result;

    case #char "%";
        result.kind = .PERCENT;
        return result;

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

    case #char "\"";
        return lex_string_literal_after_quote(lexer, result);
    }

    if #char "0" <= char && char <= #char "9" {
        value : u64 = char - #char "0";

        while true {
            success, char := peek(lexer);
            if char < #char "0" || #char "9" < char     break;
            expect(lexer, "what the heck this shouldn't ever error");

            new_value := value * 10 + (char - #char "0");
            if new_value < value {
                result.did_succeed = false;
                result.error = "value was too big";

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
        result.ident_symbol = add_symbol(lexer.symbols, ident_string);

        return result;
    }

    result.did_succeed = false;
    result.error = "didn't recognize the character";

    return result;
}

lex_string_literal_after_quote :: inline (lexer: *Lexer, result: Result(Token)) -> Result(Token) {
    return lex_string_literal_after_quote_(lexer, result);
}

#scope_file

start_result :: (lexer: *Lexer, $type: Type) -> Result(type) {
    result : Result(type);
    result.error = "internal error? result might not have been initialized";
    result.did_succeed = true;
    result.begin = lexer.cursor;
    result.end = lexer.cursor;

    return result;
}


lex_string_literal_after_quote_ :: (lexer: *Lexer, _result: Result(Token)) -> Result(Token) {
    result := _result;
    builder := StringBuilder.make();

    while true {
        char := expect(lexer, "strings need to end with a double quote -> \"");
        if char == #char "\"" {
            result.kind = .STRING_LITERAL;
            result.string_value = to_string(*builder, allocator = __temporary_allocator);
            return result;
        }

        if char != #char "\\" {
            write(*builder, char);
            continue;
        }

        char = expect(lexer, "strings need to end with a double quote -> \"");
        if char == {
        case #char "'";
            write(*builder, #char "'");
            continue;
        case #char "\"";
            write(*builder, #char "\"");
            continue;

        case #char "r";
            write(*builder, #char "\r");
            continue;
        case #char "n";
            write(*builder, #char "\n");
            continue;

        case #char "\\";
            write(*builder, #char "\\");
            continue;
        }

        write(*builder, char);
    }

    return result;
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
            result.end = lexer.cursor;
            result.did_succeed = false;
            result.error = "got '\\r' character in place we weren't expecting";

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
            result.end = lexer.cursor;
            result.error = "got '\\r' character in place we weren't expecting";

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
            result.error = "got '\\r' character in place we weren't expecting";
            result.end = lexer.cursor;

            `return result;
        }
    case;
        lexer.line_offset += 1;
    }

    `result.end = lexer.cursor;
    return true, value;
}

expect :: (lexer: *Lexer, message: string) -> u8 #expand {
    result := `result;

    if lexer.cursor >= lexer.file_data.count {
        result.did_succeed = false;
        result.end = lexer.cursor;
        result.error = message;

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
            result.end = lexer.cursor;
            result.error = "got '\\r' character in place we weren't expecting";

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
            result.end = lexer.cursor;
            result.error = "got '\\r' character in place we weren't expecting";

            `return result;
        }
    }

    return true, value;
}

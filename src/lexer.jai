#import "Basic";

#import "liu";
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
    map_add(*keywords, "proc", .PROC);
    map_add(*keywords, "return", .RETURN);
    map_add(*keywords, "match", .MATCH);
    map_add(*keywords, "break", .BREAK);
    map_add(*keywords, "continue", .CONTINUE);
    map_add(*keywords, "throw", .THROW);

    map_add(*keywords, "or", .OR);
    map_add(*keywords, "and", .AND);
    map_add(*keywords, "bitor", .BIT_OR);
    map_add(*keywords, "bitxor", .BIT_XOR);
    map_add(*keywords, "bitand", .BIT_AND);
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
        PROC;
        MATCH;
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

        EQUAL_SIGN;
        NOT_EQUAL_SIGN;
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

    Data :: struct {
        _begin : void;
        #place _begin;
        integer_value : u64;
        is_negative : bool;

        #place _begin;
        float_value : float64;

        #place _begin;
        string_value : string;

        #place _begin;
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
        err, token := read(result);
        if err      return result;

        if token.kind == {
            case .WHITESPACE;     continue;
            case .LINE_COMMENT;     continue;
            case .BLOCK_COMMENT;    continue;
        }

        return result;
    }
}

lex_raw_token :: (lexer: *Lexer) -> Result(Token) {
    begin := lexer.cursor;
    success, char := pop(lexer);
    if !success {
        ret(.EOF);
    }

    ret :: (kind: Token.Kind) #expand {
        token : Token;
        token.kind = kind;
        token.begin = begin;
        token.end = lexer.cursor;
        `return ok(token);
    }

    throw :: (message: string, _cursor : s32 = -1) #expand {
        cursor := ifx _cursor != -1 then _cursor else `lexer.cursor;
        span := new_span(cursor, cursor + 1); // @Todo do we wanna support weird UTF-8 stuff?
        `return error(*span, message);
    }

    if char == {
    case #char " "; #through;
    case #char "\t";
        while match(lexer, char == #char " " || char == #char "\t") {}

        ret(.WHITESPACE);

    case #char "/";
        if match(lexer, #char "*") {
            while true {
                success, char = pop(lexer);
                if !success {
                    throw("block comments need to end with a '*/'", lexer.cursor - 1);
                }

                if char == #char "*" && match(lexer, #char "/") {
                    ret(.BLOCK_COMMENT);
                }
            }
        }

        if match(lexer, #char "/") {
            while true {
                success, char = pop(lexer);
                if !success     break;
                if char == #char "\n"   break;
            }

            ret(.LINE_COMMENT);
        }

        ret(.DIVIDE);

    case #char "\n";
        ret(.NEWLINE);

    case #char ";";
        ret(.SEMICOLON);

    case #char ",";
        ret(.COMMA);

    case #char ".";
        if match(lexer, #char ".") {
            if match(lexer, #char "=") {
                ret(.DOT_DOT_EQUAL);
            }

            ret(.RANGE);
        }

        ret(.DOT);

    case #char ":";
        ret(.COLON);

    case #char "=";
        if match(lexer, #char "=") {
            ret(.DOUBLE_EQUALS);
        }

        if match(lexer, #char ">") {
            ret(.RIGHT_DOUBLE_ARROW);
        }

        ret(.EQUAL_SIGN);

    case #char "<"; // @Todo should the lexer try to prevent you from doing stupid stuff
        if match(lexer, #char "=") {
            ret(.LEQ_THAN);
        }

        if match(lexer, #char "-") {
            ret(.LEFT_ARROW);
        }

        if match(lexer, #char "<") {
            ret(.LEFT_SHIFT);
        }

        ret(.LESS_THAN);

    case #char ">";
        if match(lexer, #char "=") {
            ret(.GEQ_THAN);
        }

        if match(lexer, #char ">") {
            ret(.RIGHT_SHIFT);
        }

        ret(.GREATER_THAN);

    case #char "~";
        ret(.TILDE);

    case #char "!";
        if match(lexer, #char "=") {
            ret(.NOT_EQUAL_SIGN);
        }

        ret(.EXCLAMATION);

    case #char "+";
        ret(.PLUS);

    case #char "-";
        if match(lexer, #char ">") {
            ret(.RIGHT_ARROW);
        }

        success, value := try_lex_number_literal(lexer);
        if success {
            token : Token;
            token.kind = .INTEGER_LITERAL;
            token.integer_value = value;
            token.is_negative = true;
            token.begin = begin;
            token.end = lexer.cursor;
            return ok(token);
        }

        ret(.MINUS);

    case #char "*";
        if match(lexer, #char "*") {
            ret(.DOUBLE_STAR);
        }

        ret(.STAR);

    case #char "%";
        ret(.PERCENT);

    case #char "{";
        ret(.LBRACE);
    case #char "}";
        ret(.RBRACE);

    case #char "[";
        ret(.LBRACKET);
    case #char "]";
        ret(.RBRACKET);

    case #char "(";
        ret(.LPAREN);
    case #char ")";
        ret(.RPAREN);

    case #char "\"";
        return lex_string_literal_after_quote(lexer);
    }

    value : u64 = ---;
    success, value = lex_number_literal(lexer, char);
    if success {
        token : Token;
        token.kind = .INTEGER_LITERAL;
        token.integer_value = value;
        token.is_negative = false;
        token.begin = begin;
        token.end = lexer.cursor;
        return ok(token);
    }

    match_id_char_begin :: #code (#char "a" <= char && char <= #char "z")
        || (#char "A" <= char && char <= #char "Z")
        || char == #char "_";
    match_id_char :: #code (#char "a" <= char && char <= #char "z")
        || (#char "A" <= char && char <= #char "Z")
        || char == #char "_" || (#char "0" <= char && char <= #char "9");

    if #insert match_id_char_begin {
        ident_string : string = ---;
        ident_string.data = lexer.file_data.data + begin;
        ident_string.count = 1;

        while match(lexer, match_id_char)   ident_string.count += 1;

        success, keyword_kind := map_find(*keywords, ident_string);
        if success {
            ret(keyword_kind);
        }

        token : Token;
        token.kind = .IDENT;
        token.ident_symbol = add_symbol(lexer.symbols, ident_string);
        token.begin = begin;
        token.end = lexer.cursor;
        return ok(token);
    }

    throw("didn't recognize the character", begin);
}

#scope_file

lex_number_literal :: (lexer: *Lexer, initial: u8) -> bool, u64 #expand {
    if initial < #char "0" || #char "9" < initial     return false, 0;
    value : u64 = initial - #char "0";

    while true {
        if lexer.cursor >= lexer.file_data.count {
            return true, value;
        }

        char := lexer.file_data[lexer.cursor];
        if char < #char "0" || #char "9" < char     break;
        lexer.cursor += 1;

        new_value := value * 10 + (char - #char "0");
        if new_value < value {
            span := new_span(`begin, lexer.cursor);
            `return error(*span, "value was too big");
        }

        value = new_value;
    }

    return true, value;
}

try_lex_number_literal :: (lexer: *Lexer) -> bool, u64 #expand {
    value : u64 = 0;
    found_one := false;
    while true {
        if lexer.cursor >= lexer.file_data.count {
            return found_one, value;
        }

        char := lexer.file_data[lexer.cursor];
        if char < #char "0" || #char "9" < char     break;
        lexer.cursor += 1;

        new_value := value * 10 + (char - #char "0");
        if new_value < value {
            span := new_span(`begin, lexer.cursor);
            `return error(*span, "value was too big");
        }

        value = new_value;
        found_one = true;
    }

    return found_one, value;
}

lex_string_literal_after_quote :: (lexer: *Lexer) -> Result(Token) #expand {
    begin := `begin;
    builder := StringBuilder.make();

    while true {
        char := expect(lexer, "strings need to end with a double quote -> \"");
        if char == #char "\"" {
            token : Token;
            token.kind = .STRING_LITERAL;
            token.begin = `begin;
            token.end = lexer.cursor;
            token.string_value = to_string(*builder, allocator = __temporary_allocator);
            return ok(token);
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

    span := new_span(`begin, lexer.cursor);
    return error(*span, "unreachable");
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
            span := new_span(`begin, lexer.cursor);
            `return error(*span, "got '\\r' character in place we weren't expecting");
        }
    case;
        lexer.line_offset += 1;
    }

    if char == to_match {
        return true;
    }

    lexer.cursor = original_cursor;
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
            span := new_span(`begin, lexer.cursor);
            `return error(*span, "got '\\r' character in place we weren't expecting");
        }
    case;
        lexer.line_offset += 1;
    }

    if #insert_internal pattern {
        return true;
    }

    lexer.cursor = original_cursor;
    return false;
}

pop :: (lexer: *Lexer) -> bool, u8 #expand {
    if lexer.cursor >= lexer.file_data.count    return false, 0;

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
            span := new_span(`begin, lexer.cursor);
            `return error(*span, "got '\\r' character in place we weren't expecting");
        }
    case;
        lexer.line_offset += 1;
    }

    return true, value;
}

expect :: (lexer: *Lexer, message: string) -> u8 #expand {
    if lexer.cursor >= lexer.file_data.count {
        span := new_span(`begin, lexer.cursor);
        `return error(*span, message);
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
            span := new_span(`begin, lexer.cursor);
            `return error(*span, "got '\\r' character in place we weren't expecting");
        }
    case;
        lexer.line_offset += 1;
    }

    return value;
}

peek :: (lexer: *Lexer) -> bool, u8 #expand {
    if lexer.cursor >= lexer.file_data.count    return false, 0;

    value := lexer.file_data[lexer.cursor];
    if value == #char "\r" {
        if lexer.cursor < lexer.file_data.count && lexer.file_data[lexer.cursor + 1] == #char "\n" {
            value = #char "\n";
        } else {
            span := new_span(`begin, lexer.cursor);
            `return error(*span, "got '\\r' character in place we weren't expecting");
        }
    }

    return true, value;
}

error :: (value: *$T/interface Span, message: string, loc := #caller_location) -> Result(Token) {
    return Liu.error(value, message, loc = loc, success_type = Token);
}

Liu :: #import "liu";

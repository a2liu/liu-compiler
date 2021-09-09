#import "Basic";
#import "buckets";
#import "lexer";

Expr :: struct {
    Kind :: enum {
        COMPTIME_DECLARATION;
        DECLARATION;
        MODULE;

        // binary ops
        PLUS;
    }

    kind: Kind;
    begin: s32;
    end: s32;
}

Plus :: struct {
    using base: Expr;
    left: *Expr;
    right: *Expr;
}

Module :: struct {
    using base: Expr;
    file: s32;
    statements: [] *Expr;
}

Parser :: struct {
    tokens : [..] Token;
    cursor : s64;

    consume_lexer_and_make :: (lexer: *Lexer) -> Result(Parser) {
        result : Result(Parser);
        result.was_final = true;

        token := lex_token(lexer);
        while true {
            if !token.did_succeed {
                result.did_succeed = false;
                result.error = token.error;
                result.begin = token.begin;
                result.end = token.end;
                return result;
            }

            if token.kind == .EOF
                break;

            array_add(*result.tokens, token.value);
            token = lex_token(lexer);
        }

        result.begin = -1;
        result.end = -1;
        return result;
    }
}

parse_complete_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    // declarations
    success, matches := match(parser, .IDENT, .COLON);
    if success {
    }

    return result;
}

parse_simple_expr :: () {
}

#scope_file

start_result :: (parser: *Parser, $type: Type) -> Result(type) {
    result : Result(type);
    result.error = "internal error? result might not have been initialized";
    result.begin = parser.tokens[parser.cursor].begin;
    result.end = result.begin;

    return result;
}

match :: (parser: *Parser, to_match: .. Token.Kind) -> bool, [] Token #expand {
    assert(to_match.count > 0);
    tokens: [] Token;

    if parser.cursor + to_match.count > parser.tokens.count {
        return false, tokens;
    }

    cursor := parser.cursor;
    for to_match {
        if it != parser.tokens[cursor + it_index].kind {
            return false, tokens;
        }
    }

    tokens.data = *parser.tokens[parser.cursor];
    tokens.count = to_match.count;

    parser.cursor += to_match.count;
    `result.end = parser.tokens[parser.cursor - 1].end;
    return true, tokens;
}





#import "Basic";
#import "buckets";
#import "lexer";

Expr :: struct {
    Kind :: enum u32 {
        UNINITIALIZED :: 0;

        COMPTIME_DECLARATION;
        DECLARATION;
        BLOCK;
        MODULE;

        // binary ops
        PLUS;
        MINUS;
        MULTIPLY;
        DIVIDE;

        // Atoms
        IDENT;
    }

    kind: Kind = .UNINITIALIZED;
    begin: s32;
    end: s32;
}

BinaryOp :: struct {
    using _base: Expr;
    left: *Expr;
    right: *Expr;
}

Block :: struct {
    using _base: Expr;
    _base.kind = .BLOCK;
    statements: [] *Expr;
}

Module :: struct {
    using __base: Block;
    __base.kind = .MODULE;
    file: s32;
}

Ident :: struct {
    using _base: Expr;
    _base.kind = .IDENT;
    ident_symbol : s32;
}

for_expansion :: (iter: *Expr, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    `it_index : void;
    nodes : [..] *Expr;
    array_add(*nodes, iter);

    while nodes.count > 0 {
        `it : *Expr = pop(*nodes);

        #insert body;

        if it.kind == {
        case .PLUS;
            node := cast(*BinaryOp) it;
            array_add(*nodes, node.right);
            array_add(*nodes, node.left);
        }
    }
}

Parser :: struct {
    tokens : [..] Token;
    cursor : s64 = 0;
    skip_newline : bool = false;

    consume_lexer_and_make :: (lexer: *Lexer) -> Result(Parser) {
        result : Result(Parser);

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

// Expressions that cannot be assigned to a value or used in larger expression
// without parens. Like assignment and variable mutation.
parse_statement_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    success, matches := match(parser, .NEWLINE);
    while success {
        success, matches = match(parser, .NEWLINE);
    }

    // declarations
    previous_skip := parser.skip_newline;
    parser.skip_newline = false;
    success, matches = match(parser, .IDENT, .COLON);
    parser.skip_newline = previous_skip;
    if success {
    }

    // its an expresion of some kind
    parse_result := parse_complete_expr(parser);
    expr := unwrap(parse_result);

    // is it an assignment?
    // @Todo

    result.value = expr;
    return result;
}

// Expressions that can be assigned to a value without parens, but can't be in a
// larger expression without parens. i.e. blocks or control flow stuff
parse_complete_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    // control flow
    // @Todo

    // Blocks
    // @Todo

    parse_result := parse_binary_expr(parser);
    expr := unwrap(parse_result);

    result.value = expr;
    return result;
}

// binary expressions, like a + b + c + d
parse_binary_expr :: (parser: *Parser, min_precedence := 0) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    parse_result := parse_simple_expr(parser);
    expr := unwrap(parse_result);

    // https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
    // This algorithm is supposed to be efficient. No idea if that's actually true,
    // but it is incredibly concise.
    success, token := peek(parser);
    while success {
        is_op, info := binary_operator_info(token.kind);
        if !is_op || info.precedence < min_precedence {
            break;
        }
        expect(parser);

        next_min_precedence := info.precedence;
        if info.is_left_to_right    next_min_precedence += 1;

        parse_result = parse_binary_expr(parser, next_min_precedence);
        right := unwrap(parse_result);
        new_expr := Buck(BinaryOp);
        new_expr.kind = info.op_kind;
        new_expr.left = expr;
        new_expr.right = right;
        expr = new_expr;

        success, token = peek(parser);
    }

    result.value = expr;
    return result;
}

// infix and postfix expressions, like chase a[1], a.b.c[13]
parse_simple_expr :: (parser: *Parser) -> Result(*Expr) {
    return parse_atom(parser);
    // result := start_result(parser, *Expr);
    // return result;
}

// Atoms like 12, begin, (12 + 13)
parse_atom :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    success, matches := match(parser, .IDENT);
    if success {
        expr := Buck(Ident);
        expr.ident_symbol = matches[0].ident_symbol;
        result.value = expr;
        return result;
    }

    // parenthesized expression is the only other option
    previous_skip := parser.skip_newline;
    expect_match(parser, .LPAREN);
    parser.skip_newline = true;

    parse_result := parse_statement_expr(parser);
    expr := unwrap(parse_result);

    expect_match(parser, .RPAREN);
    parser.skip_newline = previous_skip;

    result.value = expr;
    return result;
}

#scope_file

BinaryOpInfo :: struct {
    op_kind: Expr.Kind;
    precedence: u8;
    is_left_to_right: bool;
}

// @Todo This could probably be like compile-time or something
binary_operator_info :: (kind: Token.Kind) -> bool, BinaryOpInfo {
    success := true;
    info : BinaryOpInfo;
    if kind == {
    case .PLUS;
        info.op_kind = .PLUS;
        info.precedence = 20;
        info.is_left_to_right = true;

    case .MINUS;
        info.op_kind = .MINUS;
        info.precedence = 20;
        info.is_left_to_right = true;

    case .STAR;
        info.op_kind = .MULTIPLY;
        info.precedence = 20;
        info.is_left_to_right = true;

    case .DIVIDE;
        info.op_kind = .MINUS;
        info.precedence = 20;
        info.is_left_to_right = true;

    case;
        success = false;
    }

    return success, info;
}

unwrap :: (result: Result(*Expr)) -> *Expr #expand {
    if !result.did_succeed      `return result;

    `result.end = max(`result.end, result.end);
    result.value.end = result.end;
    result.value.begin = result.begin;
    return result.value;
}

start_result :: (parser: *Parser, $type: Type) -> Result(type) {
    result : Result(type);
    result.error = "internal error? result might not have been initialized";
    result.begin = parser.tokens[parser.cursor].begin;
    result.end = result.begin;

    return result;
}

peek :: (parser: *Parser) -> bool, *Token #expand {
    while parser.cursor < parser.tokens.count {
        token := *parser.tokens[parser.cursor];
        if token.kind == .NEWLINE && parser.skip_newline {
            parser.cursor += 1;
            continue;
        }

       `result.end = token.end;
        return true, token;
    }

    return false, null;
}

expect_peek :: (parser: *Parser) -> *Token #expand {
    while parser.cursor < parser.tokens.count {
        token := *parser.tokens[parser.cursor];
        if token.kind == .NEWLINE && parser.skip_newline {
            parser.cursor += 1;
            continue;
        }

       `result.end = token.end;
        return token;
    }

    result := `result;
    result.end = parser.tokens[parser.tokens.count - 1].end;
    result.did_succeed = false;
    result.error = "got to the end of the file when we expected another token";

    `return result;
}

expect :: (parser: *Parser) -> *Token #expand {
    while parser.cursor < parser.tokens.count {
        token := *parser.tokens[parser.cursor];
        parser.cursor += 1;
        if token.kind == .NEWLINE && parser.skip_newline {
            continue;
        }

        `result.end = token.end;
        return token;
    }

    result := `result;
    result.end = parser.tokens[parser.tokens.count - 1].end;
    result.did_succeed = false;
    result.error = "got to the end of the file when we expected another token";
    assert(false);

    `return result;
}

expect_match :: (parser: *Parser, to_match: .. Token.Kind) -> [] Token #expand {
    assert(to_match.count > 0);
    tokens: [] Token;

    match_cursor := 0;
    cursor := parser.cursor;
    while cursor < parser.tokens.count {
        match_kind := to_match[match_cursor];
        token := *parser.tokens[cursor];
        cursor += 1;

        if match_kind != token.kind {
            if token.kind == .NEWLINE && parser.skip_newline
                continue;

            result := `result;
            result.end = token.end;
            result.did_succeed = false;
            result.error = "expected to find match to tokens";

            `return result;
        }

        match_cursor += 1;

        if match_cursor == to_match.count {
            tokens.data = *parser.tokens[parser.cursor];
            tokens.count = to_match.count;

            parser.cursor = cursor;
            `result.end = parser.tokens[parser.cursor - 1].end;
            return tokens;
        }
    }

    result := `result;
    result.end = parser.tokens[parser.tokens.count - 1].end;
    result.did_succeed = false;
    result.error = "expected to find match to tokens";

    `return result;
}

match :: (parser: *Parser, to_match: .. Token.Kind) -> bool, [] Token #expand {
    assert(to_match.count > 0);
    tokens: [] Token;

    match_cursor := 0;
    cursor := parser.cursor;
    while cursor < parser.tokens.count {
        match_kind := to_match[match_cursor];
        token := *parser.tokens[cursor];
        cursor += 1;

        if match_kind != token.kind {
            if token.kind == .NEWLINE && parser.skip_newline
                continue;

            return false, tokens;
        }

        match_cursor += 1;

        if match_cursor == to_match.count {
            tokens.data = *parser.tokens[parser.cursor];
            tokens.count = to_match.count;

            parser.cursor = cursor;
            `result.end = parser.tokens[parser.cursor - 1].end;
            return true, tokens;
        }
    }

    return false, tokens;
}

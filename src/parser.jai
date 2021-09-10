#import "Basic";
#import "buckets";
#import "lexer";

Expr :: struct {
    Kind :: enum u16 {
        UNINITIALIZED :: 0;

        // file
        MODULE :: 10;

        // statement
        DECLARATION :: 20;

        // 1 declaration => b := 13
        // 3 declarations => a, b, c := 12, 13, 14

        DECLARATION_COMPTIME; // a :: 12
        DECLARATION_SPLIT; // a, b, c := match(parser)
        DECLARATION_COMPTIME_SPLIT; // a, b, c :: match(parser)

        // complete
        BLOCK :: 30;
        TUPLE;

        // binary ops
        PLUS :: 40;
        MINUS;
        MULTIPLY;
        DIVIDE;

        // simple
        REF :: 60;
        CHASE;
        SUBSCRIPT;

        // Atoms
        IDENT :: 70;
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

Tuple :: struct {
    using _base: Expr;
    _base.kind = .TUPLE;
    members: [] *Expr;
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

// it_index is the level in the tree you're at
for_expansion :: (iter: *Expr, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    Node :: struct {
        expr: *Expr;
        level: s64;
    }
    nodes : [..] Node;
    node : Node;
    node.expr = iter;
    node.level = 0;
    array_add(*nodes, node);

    prev_index := -1;
    while nodes.count > 0 {
        node = pop(*nodes);
        `it := node.expr;
        `it_index := node.level;
        `it_motion := it_index - prev_index;
        prev_index = it_index;

        #insert body;

        if it.kind == {
        // Binary op
        case .PLUS;     #through;
        case .MINUS;    #through;
        case .MULTIPLY; #through;
        case .DIVIDE;
            binary := cast(*BinaryOp) it;
            node.level += 1;
            node.expr = binary.right;
            array_add(*nodes, node);

            node.expr = binary.left;
            array_add(*nodes, node);
        }
    }
}

Parser :: struct {
    Enclosing :: enum u8 {
        NONE;
        PAREN;
        BRACE;
        BRACKET;
    }

    tokens : [..] Token;
    cursor : s64 = 0;
    enclosing : Enclosing = .NONE;

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

    eat_newlines(parser);

    // simple declarations
    success, matches := match(parser, .IDENT, .COLON);
    if success {
    }

    // its a non-declaration expresion of some kind
    expr := unwrap(parse_complete_expr(parser));

    // is it an assignment?
    // @Todo

    ret(expr);
}

// Expressions that can be assigned to a value without parens, but can't be in a
// larger expression without parens. i.e. blocks or control flow stuff
parse_complete_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    // control flow
    // @Todo

    // Blocks
    success, matches := match(parser, .LBRACE);
    if success {
        push_enclosing(parser, .BRACE);
        eat_newlines(parser);

        // @Todo

        assert(false, "unimplemented");
    }

    expr := unwrap(parse_binary_expr(parser));
    success, matches = match(parser, .COMMA);
    if !success         ret(expr);

    // tuples: a, b, c
    tuple_exprs : [..] *Expr;
    array_add(*tuple_exprs, expr);
    defer array_free(tuple_exprs);

    while success {
        expr = unwrap(parse_binary_expr(parser));
        array_add(*tuple_exprs, expr);
        success, matches = match(parser, .COMMA);
    }

    // it's not a tuple
    if tuple_exprs.count == 0     ret(expr);

    array_add(*tuple_exprs, expr);
    tuple := Buck(Tuple);
    exprs := BuckArray(tuple_exprs.count, *Expr, initialized = false);
    memcpy(exprs.data, tuple_exprs.data, exprs.count * size_of(*Expr));
    tuple.members = exprs;

    ret(tuple);
}

// binary expressions, like a + b + c + d
parse_binary_expr :: (parser: *Parser, min_precedence := 0) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    expr := unwrap(parse_simple_expr(parser));

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

        right := unwrap(parse_binary_expr(parser, next_min_precedence));
        new_expr := Buck(BinaryOp);
        new_expr.kind = info.op_kind;
        new_expr.left = expr;
        new_expr.right = right;
        expr = new_expr;

        success, token = peek(parser);
    }

    ret(expr);
}

// infix and postfix expressions, like chase a[1], a.b.c[13]
parse_simple_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser, *Expr);
    expr := unwrap(parse_atom(parser));
    ret(expr);
}

// Atoms like 12, begin, (12 + 13)
parse_atom :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser, *Expr);

    success, matches := match(parser, .IDENT);
    if success {
        expr := Buck(Ident);
        expr.ident_symbol = matches[0].ident_symbol;

        ret(expr);
    }

    // parenthesized expression is the only other option
    expect_match(parser, .LPAREN);
    push_enclosing(parser, .PAREN);
    expr := unwrap(parse_statement_expr(parser));
    expect_match(parser, .RPAREN);

    ret(expr);
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
        info.precedence = 10;
        info.is_left_to_right = true;

    case .MINUS;
        info.op_kind = .MINUS;
        info.precedence = 10;
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
    return result.value;
}

ret :: (expr: *Expr) #expand {
    result := `result;
    expr.end = result.end;
    expr.begin = result.begin;
    result.value = expr;

    `return result;
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
        if token.kind == .NEWLINE && parser.enclosing == .PAREN {
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
        if token.kind == .NEWLINE && parser.enclosing == .PAREN {
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
        if token.kind == .NEWLINE && parser.enclosing == .PAREN {
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
            if token.kind == .NEWLINE && parser.enclosing == .PAREN
                continue;

            result := `result;
            result.begin = token.begin;
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
    last := parser.tokens[parser.tokens.count - 1];
    result.begin = last.begin;
    result.end = last.end;
    result.did_succeed = false;
    result.error = "expected to find match to tokens";

    `return result;
}

push_enclosing :: (parser: *Parser, enclosing: Parser.Enclosing) #expand {
    previous := parser.enclosing;
    parser.enclosing = enclosing;
    `defer parser.enclosing = previous;
}

expr_is_over :: (parser: *Parser) -> bool {
    success := false;
    token : *Token;

    while parser.cursor < parser.tokens.count {
        token = *parser.tokens[parser.cursor];
        if token.kind == .NEWLINE && parser.enclosing == .PAREN {
            parser.cursor += 1;
            continue;
        }

        success = true;
        break;
    }

    if !success     return true;
    if kind == .SEMICOLON     return true;

    if #complete parser.enclosing == {
    case .NONE;
        return kind == .NEWLINE;
    case .PAREN;
        return kind == .RPAREN;
    case .BRACKET;
        return kind == .RBRACKET;
    case .BRACE;
        return kind == .RBRACE || kind == .NEWLINE;
    }
}

token_would_end_scope :: (parser: *Parser, kind: Token.Kind) -> bool {
    if #complete parser.enclosing == {
    case .NONE;
        return false;
    case .PAREN;
        return kind == .RPAREN;
    case .BRACKET;
        return kind == .RBRACKET;
    case .BRACE;
        return kind == .RBRACE;
    }
}

finalize_statement :: (parser: *Parser) -> bool #expand {
    finalized := false;
    token : *Token;

    while parser.cursor < parser.tokens.count {
        token = *parser.tokens[parser.cursor];
        if token.kind == .NEWLINE {
            finalized = true;
            parser.cursor += 1;
            continue;
        }

        break;
    }
    if !success     return;

    if token_would_end_scope(parser, token.kind) {
        parser.cursor += 1;
        return false;
    }

    finalized := false;
    if parser.enclosing == {
    case .NONE; #through;
    case .BRACE;
        finalized = (token.kind == .NEWLINE);
    }

    if finalized {
        parser.cursor += 1;
        return true;
    }

    result := `result;
    last := parser.tokens[parser.tokens.count - 1];
    result.begin = last.begin;
    result.end = last.end;
    result.did_succeed = false;
    result.error = "expected to find separator between expressions";

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
            if token.kind == .NEWLINE && parser.enclosing == .PAREN
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

eat_newlines :: (parser: *Parser) #expand {
    end := `result.end;
    while parser.cursor < parser.tokens.count {
        token := *parser.tokens[parser.cursor];
        if token.kind != .NEWLINE       break;

        end = token.end;
        parser.cursor += 1;
    }

    `result.end = end;
}


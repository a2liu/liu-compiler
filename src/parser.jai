#import "Basic";
#import "buckets";
#import "lexer";
#import "utils";

Expr :: struct {
    Kind :: enum u16 {
        UNINITIALIZED :: 0;

        MODULE;

        // statement expression
        DECLARATION;
        // 1 declaration => b := 13
        // 3 declarations => a, b, c := 12, 13, 14

        DECLARATION_SPLIT; // a, b, c := match(parser)

        // complete expression
        BLOCK;
        TUPLE;

        // binary expression
        PLUS;
        MINUS;
        MULTIPLY;
        DIVIDE;

        EQUALS;
        NOT_EQUALS;
        DOUBLE_EQUALS;
        LESS_THAN;
        LEQ_THAN;
        GREATER_THAN;
        GEQ_THAN;

        OR;
        AND;
        NOT;
        BIT_OR;
        BIT_XOR;
        BIT_AND;
        BIT_NOT;

        // unary expression
        REF;
        DEREF;
        SUBSCRIPT;

        // atom
        IDENT;
        EMPTY_PAREN;
    }

    Flags :: enum_flags u16 {
        COMPTIME;
        PARENTHESIZED;
    }

    kind : Kind = .UNINITIALIZED;
    flags : Flags = 0;
    begin : s32;
    end : s32;
}

BinaryOp :: struct {
    using _base : Expr;
    left : *Expr;
    right : *Expr;
}

Tuple :: struct {
    using _base : Expr;
    _base.kind = .TUPLE;
    members : [] *Expr; // members allocated right after tuple struct
}

Block :: struct {
    using _base : Expr;
    _base.kind = .BLOCK;
    statements : [] *Expr; // statements allocated right after block struct
}

Module :: struct {
    using _base : Expr;
    _base.kind = .MODULE;
    file : s32;
    statements : [] *Expr; // statements allocated right after module struct
}

Ident :: struct {
    using _base : Expr;
    _base.kind = .IDENT;
    ident_symbol : s32;
}

Declaration :: struct {
    using _base : Expr;
    _base.kind = .DECLARATION;
    type_declaration_nullable : *Expr;
    value_nullable : *Expr;
    ident_symbol : s32;
}

DeclarationSplit :: struct {
    using _base : Expr;
    _base.kind = .DECLARATION_SPLIT;
    type_declaration_nullable : *Expr;
    value_nullable : *Expr;
    ident_symbols : [] s32;
}

// it_index is the level in the tree you're at
for_expansion :: (iter: *Expr, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    Node :: struct {
        expr: *Expr;
        level: s64;
    }

    visit :: (exprs: .. *Expr) #expand {
        for < exprs {
            if it == null       continue;
            node := `node;
            node.expr = it;
            array_add(*`nodes, node);
        }
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

        node.level += 1;
        if it.kind == { // @Todo add #complete to this
        case .UNINITIALIZED;
            assert(false);

        case .MODULE;
            module := cast(*Module) it;
            visit(..module.statements);

        case .BLOCK;
            block := cast(*Block) it;
            visit(..block.statements);

        case .TUPLE;
            tuple := cast(*Tuple) it;
            visit(..tuple.members);

        case .DECLARATION;
            decl := cast(*Declaration) it;
            visit(decl.type_declaration_nullable, decl.value_nullable);

        case .DECLARATION_SPLIT;
            decl := cast(*DeclarationSplit) it;
            visit(decl.type_declaration_nullable, decl.value_nullable);

        // Binary op
        case .PLUS;              #through;
        case .MINUS;             #through;
        case .MULTIPLY;          #through;
        case .DIVIDE;            #through;
        case .EQUALS;            #through;
        case .NOT_EQUALS;        #through;
        case .DOUBLE_EQUALS;     #through;
        case .LESS_THAN;         #through;
        case .LEQ_THAN;          #through;
        case .GREATER_THAN;      #through;
        case .GEQ_THAN;          #through;
        case .OR;                #through;
        case .AND;               #through;
        case .BIT_OR;            #through;
        case .BIT_XOR;           #through;
        case .BIT_AND;
            binary := cast(*BinaryOp) it;
            visit(binary.left, binary.right);
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

parse_file :: (parser: *Parser, file: s32) -> Result(*Module) {

    file_statements : [..] *Expr;
    defer array_free(file_statements);


    module := Buck(Module);
    module.statements = BuckArray(file_statements.count, *Expr, initialized = false);
    memcpy(module.statements.data, file_statements.data, file_statements.count * size_of(*Expr));

    ret(module);
}

// Expressions that cannot be assigned to a value or used in larger expression
// without parens. Like assignment and variable mutation.
parse_statement_expr :: (parser: *Parser, additional: *[..] *Expr) -> Result(*Expr) {
    result := start_result(parser);

    // simple declarations
    success, matches := match(parser, .IDENT, .COLON);
    if success {
        // @Todo
    }

    // its a non-declaration expresion of some kind
    expr := unwrap(parse_complete_expr(parser));

    // is it an assignment?
    // @Todo

    // is it a compound declaration?
    // @Todo

    array_add(additional, expr);
    ret(expr);
}

for_expansion :: (parser: *Parser, body: Code, flags: For_Flags) #expand {
    assert(parser.enclosing == .NONE);
    eat_statement_separators(parser, extend_result = false);

    // @Todo `should_continue` should really be named something else man
    should_continue, token := peek(parser, extend_result = false);
    had_separator := true;
    extra_exprs : [..] *Expr;
    extra_exprs_cursor := 0;
    defer array_free(extra_exprs);

    `it : Result(*Expr);
    `it_index : void;
    for _unused, _unused_index: C_Style((#code should_continue), #code { #insert body; }).{} {
        if extra_exprs_cursor < extra_exprs.count {
            it.did_succeed = true;
            it.value = extra_exprs[extra_exprs_cursor];
            it.begin = it.value.begin;
            it.end = it.value.end;
            extra_exprs_cursor += 1;
            continue;
        }

        if !had_separator {
            message := "missing separator between end of previous expression and beginning of next one";
            it = err(token, message);
            should_continue = false;
            continue;
        }

        extra_exprs.count = 0;
        it = parse_statement_expr(parser, *extra_exprs);
        if !it.did_succeed {
            should_continue = false;
            continue;
        }

        extra_exprs_cursor = 1;
        had_separator = eat_statement_separators(parser, extend_result = false);
        should_continue, token = peek(parser, extend_result = false);
    }
}

// Expressions that can be assigned to a value without parens, but can't be in a
// larger expression without parens. i.e. blocks or control flow stuff
parse_complete_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser);

    // control flow
    // @Todo

    // Blocks
    success, matches := match(parser, .LBRACE);
    if success {
        push_enclosing(parser, .BRACE);
        eat_statement_separators(parser);
        block_statements : [..] *Expr;
        defer array_free(block_statements);

        should_continue, token := peek(parser);
        had_separator := true;
        while should_continue {
            if token.kind == .RBRACE {
                block := Buck(Block);
                block.statements = BuckArray(block_statements.count, *Expr, initialized = false);
                memcpy(block.statements.data, block_statements.data, block_statements.count * size_of(*Expr));

                ret(block);
            }

            if !had_separator
                throw(token, "missing separator between end of previous expression and beginning of next one");

            unwrap(parse_statement_expr(parser, *block_statements));

            had_separator = eat_statement_separators(parser);
            should_continue, token = peek(parser);
        }

        token = *parser.tokens[parser.tokens.count - 1];
        throw(token, "scope ended before closing '}'");
    }

    expr := unwrap(parse_binary_expr(parser));
    success, matches = match(parser, .COMMA);
    if !success         ret(expr);

    // tuples: a, b, c
    tuple_exprs : [..] *Expr;
    array_add(*tuple_exprs, expr);
    defer array_free(tuple_exprs);

    while success {
        // Statement breaks should stop tuple parsing
        has_next, token := peek(parser);
        if !has_next    break;
        if token.kind == .SEMICOLON     break;

        // this will never show up in parser.enclosing == .PAREN
        if token.kind == .NEWLINE       break;

        if parser.enclosing == {
        case .PAREN;
            if token.kind == .RPAREN    break;
        case .BRACKET;
            if token.kind == .RBRACKET  break;
        case .BRACE;
            if token.kind == .RBRACE    break;
        }

        expr = unwrap(parse_binary_expr(parser));
        array_add(*tuple_exprs, expr);
        success, matches = match(parser, .COMMA);
    }

    tuple := Buck(Tuple);
    tuple.members = BuckArray(tuple_exprs.count, *Expr, initialized = false);
    memcpy(tuple.members.data, tuple_exprs.data, tuple_exprs.count * size_of(*Expr));

    ret(tuple);
}

parse_binary_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser);
    expr := unwrap(parse_binary_expr(parser, 0));
    ret(expr);
}

// binary expressions, like a + b + c + d
parse_binary_expr :: (parser: *Parser, min_precedence : s64) -> Result(*Expr) {
    result := start_result(parser);

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
        if info.check_operands
            unwrap(info.check_operands(expr, right));

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
    result := start_result(parser);
    expr := unwrap(parse_atom(parser));
    ret(expr);
}

// Atoms like 12, begin, (12 + 13)
parse_atom :: (parser: *Parser) -> Result(*Expr) {
    result := start_result(parser);

    success, matches := match(parser, .IDENT);
    if success {
        expr := Buck(Ident);
        expr.ident_symbol = matches[0].ident_symbol;

        ret(expr);
    }

    success, matches = match(parser, .LPAREN);
    if success {
        push_enclosing(parser, .PAREN);
        eat_statement_separators(parser);
        paren_statements : [..] *Expr;
        defer array_free(paren_statements);

        should_continue, token := peek(parser);
        had_separator := true;
        while should_continue {
            if token.kind == .RPAREN {
                if paren_statements.count == 0 {
                    paren := Buck(Expr);
                    paren.kind = .EMPTY_PAREN;
                    ret(paren);
                }

                if paren_statements.count == 1 {
                    expr := paren_statements[0];
                    expr.flags = expr.flags | .PARENTHESIZED;
                    result.begin = expr.begin;
                    result.end = expr.end;
                    result.value = expr;

                    return result;
                }

                block := Buck(Block);
                block.statements = BuckArray(paren_statements.count, *Expr, initialized = false);
                memcpy(block.statements.data, paren_statements.data, paren_statements.count * size_of(*Expr));

                ret(block);
            }

            if !had_separator
                throw(token, "missing separator between end of previous expression and beginning of next one");

            unwrap(parse_statement_expr(parser, *paren_statements));

            had_separator = eat_statement_separators(parser);
            should_continue, token = peek(parser);
        }

        throw(*parser.tokens[parser.tokens.count - 1], "scope ended before closing ')'");
    }

    token := expect_peek(parser);
    throw(token, "didn't recognize token when parsing atom");
}

#scope_file

BinaryOpInfo :: struct {
    op_kind: Expr.Kind;
    precedence: u8 = ---;
    is_left_to_right: bool = true;
    check_operands : (left: *Expr, right: *Expr) -> Result(void) = null;
}

check_keyword_binary_operands :: ($self: Expr.Kind, left: *Expr, right: *Expr) -> Result(void) {
    is_keyword :: (kind: Expr.Kind) -> bool {
        if kind == {
        case .OR; #through;
        case .AND; #through;
        case .BIT_OR; #through;
        case .BIT_XOR; #through;
        case .BIT_AND;
            return true;
        }

        return false;
    }

    result: Result(void);
    message := "To use keyword binary operands ('and', 'or', 'bitand', 'bitor', 'bitxor') with each other, you need to use parentheses";

    if left.kind != self && is_keyword(left.kind) && !(left.flags & .PARENTHESIZED)
        throw(left, message);

    if right.kind != self && is_keyword(right.kind) && !(right.flags & .PARENTHESIZED)
        throw(right, message);

    result.begin = -1;
    result.end = -1;
    return result;
}

// @Todo This could probably be like compile-time or something
binary_operator_info :: (kind: Token.Kind) -> bool, BinaryOpInfo {
    success := true;
    info : BinaryOpInfo;

    if kind == {
    case .PLUS;
        info.op_kind = .PLUS;
        info.precedence = 50;

    case .MINUS;
        info.op_kind = .MINUS;
        info.precedence = 50;

    // Multiplication
    case .STAR;
        info.op_kind = .MULTIPLY;
        info.precedence = 60;

    case .DIVIDE;
        info.op_kind = .DIVIDE;
        info.precedence = 60;

    // Comparison
    case .EQUALS;
        info.op_kind = .EQUALS;
        info.precedence = 20;

    case .NOT_EQUALS;
        info.op_kind = .NOT_EQUALS;
        info.precedence = 20;

    case .DOUBLE_EQUALS;
        info.op_kind = .DOUBLE_EQUALS;
        info.precedence = 20;

    case .LESS_THAN;
        info.op_kind = .LESS_THAN;
        info.precedence = 20;

    case .LEQ_THAN;
        info.op_kind = .LEQ_THAN;
        info.precedence = 20;

    case .GREATER_THAN;
        info.op_kind = .GREATER_THAN;
        info.precedence = 20;

    case .GEQ_THAN;
        info.op_kind = .GEQ_THAN;
        info.precedence = 20;

    // Boolean and bitwise operators
    case .OR;
        info.op_kind = .OR;
        info.precedence = 10;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .OR);

    case .AND;
        info.op_kind = .AND;
        info.precedence = 10;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .AND);

    case .BIT_OR;
        info.op_kind = .BIT_OR;
        info.precedence = 10;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .BIT_OR);

    case .BIT_XOR;
        info.op_kind = .BIT_XOR;
        info.precedence = 10;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .BIT_XOR);

    case .BIT_AND;
        info.op_kind = .BIT_AND;
        info.precedence = 10;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .BIT_AND);

    case;
        success = false;
    }

    return success, info;
}

unwrap :: (result: Result(void)) #expand {
    if !result.did_succeed {
        outer_result := `result;
        outer_result.begin = result.begin;
        outer_result.end = result.end;
        outer_result.error = result.error;

        `return outer_result;
    }

    `result.end = max(`result.end, result.end);
}

unwrap :: (result: Result($T)) -> T #expand {
    if !result.did_succeed {
        outer_result := `result;
        outer_result.begin = result.begin;
        outer_result.end = result.end;
        outer_result.error = result.error;

        `return outer_result;
    }

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

SpannedInterface :: struct {
    begin: s32;
    end: s32;
}

throw :: (message: string) #expand {
    result := `result;
    result.did_succeed = false;
    result.error = message;

    `return result;
}

throw :: (value: *$T/interface SpannedInterface, message: string) #expand {
    result := `result;
    result.begin = value.begin;
    result.end = value.end;
    result.did_succeed = false;
    result.error = message;

    `return result;
}

err :: (message: string) -> Result(*Expr) #expand {
    result := `result;
    result.did_succeed = false;
    result.error = message;

    `return result;
}

err :: (value: *$T/interface SpannedInterface, message: string) -> Result(*Expr) #expand {
    result : Result(*Expr);
    result.begin = value.begin;
    result.end = value.end;
    result.did_succeed = false;
    result.error = message;

    return result;
}

start_result :: (parser: *Parser) -> Result(*Expr) #expand {
    result : Result(*Expr);
    result.error = "internal error? result might not have been initialized";

    if parser.enclosing == .PAREN {
        while parser.cursor < parser.tokens.count {
            token := *parser.tokens[parser.cursor];
            if token.kind != .NEWLINE
                break;

            parser.cursor += 1;
        }
    }

    // @Cleanup Is this useful?
    if parser.cursor >= parser.tokens.count {
        result.begin = parser.tokens[parser.tokens.count - 1].end;
        result.end = result.begin;
        result.did_succeed = false;
        result.error = "got to the end of the file when we expected another token";
        `return result;
    }

    result.begin = parser.tokens[parser.cursor].begin;
    result.end = result.begin;

    return result;
}

peek :: (parser: *Parser, $extend_result := true) -> bool, *Token #expand {
    while parser.cursor < parser.tokens.count {
        token := *parser.tokens[parser.cursor];
        if token.kind == .NEWLINE && parser.enclosing == .PAREN {
            parser.cursor += 1;
            continue;
        }

       #if extend_result {
       `result.end = token.end;
       }
       return true, token;
    }

    return false, null;
}

expect_peek :: (parser: *Parser,
                message := "got to the end of the file when we expected another token") -> *Token #expand {
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
    result.begin = parser.tokens[parser.tokens.count - 1].end;
    result.end = result.begin;
    result.did_succeed = false;
    result.error = message;

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
    result.begin = parser.tokens[parser.tokens.count - 1].end;
    result.end = result.begin;
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
    result.begin = parser.tokens[parser.tokens.count - 1].end;
    result.end = result.begin;
    result.did_succeed = false;
    result.error = "expected to find match to tokens";

    `return result;
}

push_enclosing :: (parser: *Parser, enclosing: Parser.Enclosing) #expand {
    previous := parser.enclosing;
    parser.enclosing = enclosing;
    `defer parser.enclosing = previous;
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

eat_newlines :: (parser: *Parser) -> bool #expand {
    cursor := parser.cursor;
    end := `result.end;
    while parser.cursor < parser.tokens.count {
        token := *parser.tokens[parser.cursor];
        if token.kind != .NEWLINE       break;

        end = token.end;
        parser.cursor += 1;
    }

    `result.end = end;
    return parser.cursor != cursor;
}

eat_statement_separators :: (parser: *Parser, $extend_result := true) -> bool #expand {
    found_separator := false;
    #if extend_result {
    end := `result.end;
    }
    while parser.cursor < parser.tokens.count {
        token := *parser.tokens[parser.cursor];
        if token.kind == {
        case .NEWLINE;
            if parser.enclosing != .PAREN
                found_separator = true;
        case .SEMICOLON;
            found_separator = true;
        case;
            break;
        }

        #if extend_result {
        end = token.end;
        }
        parser.cursor += 1;
    }

    #if extend_result {
    `result.end = end;
    }
    return found_separator;
}

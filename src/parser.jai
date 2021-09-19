#import "Basic";
Math :: #import "Math";

#import "liu";
#import "ast";
Ast :: #import "ast";
#import "buckets";
#import "lexer";
#import "utils";

Parser :: struct {
    tokens : [..] Token;
    cursor : s64 = 0;
    enclosing : Token.Kind = .EOF;
    enable_assign_binary_expr : bool = false;

    consume_lexer_and_make :: (lexer: *Lexer) -> Result(Parser) {
        result : Result(Parser);
        parser := *result.value;

        while true {
            token := unwrap(lex_token(lexer));

            array_add(*parser.tokens, token);
            if token.kind == .EOF
                break;
        }

        return result;
    }

    free :: (parser: *Parser) {
        array_free(parser.tokens);
    }
}

for_expansion :: (parser: *Parser, body: Code, flags: For_Flags) #expand {
    assert(parser.enclosing == .EOF);
    eat_statement_separators();

    extra_exprs : [..] *Expr;
    extra_exprs_cursor := 0;
    defer array_free(extra_exprs);

    `it : Result(*Expr);
    `it_index : void;

    for enclose_result: enclosed(.EOF, .NEWLINE, .SEMICOLON) {
        for run_body: named_break {
            err := read(enclose_result);
            if err {
                it = error(err, success_type = *Expr);
                break run_body;
            }

            if extra_exprs_cursor < extra_exprs.count {
                it = ok(extra_exprs[extra_exprs_cursor]);
                extra_exprs_cursor += 1;
                break run_body;
            }

            extra_exprs.count = 0;
            it = parse_statement_expr(parser, *extra_exprs);
            extra_exprs_cursor = 1;
        }

        #insert body;

        if !it.did_succeed      break;
    }
}

parse_file :: (symbols: *Symbols, file_id: s32, file_data: string) -> Result(*FileExpr) {
    lexer := Lexer.make(file_data, symbols);
    result : Result(*FileExpr);
    parser := *unwrap(Parser.consume_lexer_and_make(*lexer));
    defer Parser.free(parser);

    buckets := BucketList.make();
    file := Ast.Buck(FileExpr, buckets = *buckets);
    file.file_id = file_id;
    file.buckets = buckets;
    use_tree(file);

    begin : s32;
    begin, result = start_parse(*FileExpr);

    file_statements : [..] *Expr;
    defer array_free(file_statements);

    for expr_result: parser {
        expr := unwrap(expr_result);
        array_add(*file_statements, expr);
    }

    file.statements = BuckArray(file_statements);

    result.value = file;
    return result;
}

// Expressions that cannot be assigned to a value or used in larger expression
// without parens. Like assignment and variable mutation.
//
// On success, returns data through `additional`, and return value contains first
// value in `additional`. This could probably be a lil cleaner, but meh.
parse_statement_expr :: (parser: *Parser, additional: *[..] *Expr) -> Result(*Expr) {
    begin, result := start_parse();

    // simple declarations
    success, matches := match(.IDENT, .COLON);
    if success {
        idents : [..] *DeclarationIdent;
        defer array_free(idents);
        ident := Buck(DeclarationIdent);
        ident.symbol = matches[0].ident_symbol;
        ident.begin = matches[0].begin;
        ident.end = matches[0].end;
        ident.file_id = context.current_tree.file_id;
        array_add(*idents, ident);

        if match(.EQUAL_SIGN) {
            expr := unwrap(parse_complete_expr(parser));

            decl := Buck(DeclarationExpr);
            decl.idents = BuckArray(idents);
            decl.value_nullable = expr;

            ret(decl);
        }

        ty_expr := unwrap(parse_complete_expr(parser));
        if match(.EQUAL_SIGN) {
            expr := unwrap(parse_complete_expr(parser));

            decl := Buck(DeclarationExpr);
            decl.idents = BuckArray(idents);
            decl.type_declaration_nullable = ty_expr;
            decl.value_nullable = expr;

            ret(decl);
        }

        decl := Buck(DeclarationExpr);
        decl.idents = BuckArray(idents);
        decl.type_declaration_nullable = ty_expr;

        ret(decl);
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

// Expressions that can be assigned to a value without parens, but can't be in a
// larger expression without parens. i.e. blocks or control flow stuff
parse_complete_expr :: (parser: *Parser) -> Result(*Expr) {
    begin, result := start_parse();

    // control flow
    // @Todo

    // Blocks
    success, matches := match(.LBRACE);
    if success {
        eat_statement_separators();
        block_statements : [..] *Expr;
        defer array_free(block_statements);

        for enclosed(.RBRACE, .NEWLINE, .SEMICOLON) {
            unwrap(it);
            unwrap(parse_statement_expr(parser, *block_statements));
        }

        block := Buck(BlockExpr);
        block.statements = BuckArray(block_statements);

        ret(block);
    }

    // tuples: a, b, c
    tuple_exprs : [..] *Expr;
    defer array_free(tuple_exprs);

    stops := Token.Kind.[.NEWLINE, .SEMICOLON, .EQUAL_SIGN, .COLON, .EOF];
    for enclosed(parser.enclosing, .COMMA, extra_stops = stops, consume_stop = false) {
        unwrap(it);
        expr := unwrap(parse_binary_expr(parser));
        array_add(*tuple_exprs, expr);
    }

    if tuple_exprs.count == 0
        throw(peek(), "idk man, i guess the statement ended prematurely?");


    if tuple_exprs.count == 1
        ret(tuple_exprs[0]);

    tuple := Buck(TupleExpr);
    tuple.members = BuckArray(tuple_exprs);

    ret(tuple);
}

parse_binary_expr :: (parser: *Parser) -> Result(*Expr) {
    begin, result := start_parse();
    expr := unwrap(parse_binary_expr(parser, 0));
    ret(expr);
}

// binary expressions, like a + b + c + d
parse_binary_expr :: (parser: *Parser, min_precedence : s64) -> Result(*Expr) {
    begin, result := start_parse();

    expr := unwrap(parse_unary_expr(parser));

    // https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
    // This algorithm is supposed to be efficient. No idea if that's actually true,
    // but it is incredibly concise.
    token := peek();
    while true {
        is_op, info := binary_operator_info(parser, token.kind);
        if !is_op || info.precedence < min_precedence {
            break;
        }
        parser.cursor += 1;

        next_min_precedence := info.precedence;
        if info.is_left_to_right    next_min_precedence += 1;

        right := unwrap(parse_binary_expr(parser, next_min_precedence));
        if info.check_operands
            unwrap(info.check_operands(expr, right));

        new_expr := Buck(BinaryExpr);
        new_expr.kind = info.op_kind;
        new_expr.left = expr;
        new_expr.right = right;
        expr = new_expr;

        token = peek();
    }

    ret(expr);
}

// infix and postfix expressions, like *a[1], a.b.c[13](12)
parse_unary_expr :: (parser: *Parser) -> Result(*Expr) {
    begin, result := start_parse();

    // parse prefix recursively
    // @Todo

    expr := unwrap(parse_atom(parser));

    had_match := true;
    while had_match {
        had_match = false;

        if match(.LPAREN) {
            had_match = true;

            args : [..] *Expr;
            defer array_free(args);

            for enclosed(.RPAREN, .COMMA, enable_assign_binary_expr = true) {
                unwrap(it);
                arg := unwrap(parse_binary_expr(parser));
                array_add(*args, arg);
            }

            call := Buck(CallExpr);
            call.callee = expr;
            call.arguments = BuckArray(args);

            expr = call;
        }

        if match(.LBRACKET) {
            had_match = true;

            args : [..] *Expr;
            defer array_free(args);

            // @Todo should i enable assign_binary_expr here? operator [] is basically
            // just a function call.
            for enclosed(.RBRACKET, .COMMA, enable_assign_binary_expr = true) {
                unwrap(it);
                arg := unwrap(parse_binary_expr(parser));
                array_add(*args, arg);
            }

            call := Buck(SubscriptExpr);
            call.callee = expr;
            call.arguments = BuckArray(args);

            expr = call;
        }
    }

    ret(expr);
}

// Atoms like 12, begin, (12 + 13)
parse_atom :: (parser: *Parser) -> Result(*Expr) {
    begin, result := start_parse();

    success, matches := match(.IDENT);
    if success {
        expr := Buck(IdentExpr);
        expr.symbol = matches[0].ident_symbol;

        ret(expr);
    }

    success, matches = match(.INTEGER_LITERAL);
    if success {
        token := *matches[0];
        value := token.integer_value;
        if token.is_negative {
            // @Note this is the way it is to handle (S64_MAX * -1) - 1 being a valid S64 value.
            if value - 1 > cast(u64) Math.S64_MAX
                throw(token, "value is too large for s64!");

            expr := Buck(IntegerExpr);
            expr.value = cast,trunc(s64) (value - 1);
            expr.value *= -1;
            expr.value -= 1;

            ret(expr);
        }

        if value > cast(u64) Math.S64_MAX {
            // @Todo add u64 support
            throw(token, "value is too large for s64!");
        }

        expr := Buck(IntegerExpr);
        expr.value = cast,trunc(s64) value;

        ret(expr);
    }

    if match(.LPAREN) {
        eat_statement_separators();
        paren_statements : [..] *Expr;
        defer array_free(paren_statements);

        for enclosed(.RPAREN, .SEMICOLON) {
            unwrap(it);
            unwrap(parse_statement_expr(parser, *paren_statements));
        }

        if paren_statements.count == 0 {
            paren := Buck(Expr);
            paren.kind = .EMPTY_PAREN;

            ret(paren);
        }

        if paren_statements.count == 1 {
            expr := paren_statements[0];
            expr.syntax_flags = expr.syntax_flags | .PARENTHESIZED;

            ret(expr);
        }

        paren := Buck(ParenExpr);
        paren.statements = BuckArray(paren_statements);

        ret(paren);
    }

    throw(peek(), "didn't recognize token when parsing atom");
}

#scope_file

BinaryExprInfo :: struct {
    op_kind: Expr.Kind;
    precedence: u8 = ---;
    is_left_to_right: bool = true;
    // @Todo this should be something like make_expr : (left, right) -> Result(*Expr)
    // So that we can make assignment expressions a lil nicer right off the bat
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

    if left.kind != self && is_keyword(left.kind) && !(left.syntax_flags & .PARENTHESIZED)
        throw(left, message);

    if right.kind != self && is_keyword(right.kind) && !(right.syntax_flags & .PARENTHESIZED)
        throw(right, message);

    return result;
}

binary_operator_info :: (parser: *Parser, kind: Token.Kind) -> bool, BinaryExprInfo {
    info : BinaryExprInfo;

    if kind == {
    case .PLUS;
        info.op_kind = .ADD;
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

    // Simple assignment
    case .EQUAL_SIGN;
        if !parser.enable_assign_binary_expr        return false, info;

        info.op_kind = .ASSIGN;
        info.precedence = 10;
        info.is_left_to_right = false;

    // Comparison
    case .NOT_EQUAL_SIGN;
        info.op_kind = .NOT_EQUAL;
        info.precedence = 30;

    case .DOUBLE_EQUALS;
        info.op_kind = .CHECK_EQUAL;
        info.precedence = 30;

    case .LESS_THAN;
        info.op_kind = .LESS_THAN;
        info.precedence = 30;

    case .LEQ_THAN;
        info.op_kind = .LEQ_THAN;
        info.precedence = 30;

    case .GREATER_THAN;
        info.op_kind = .GREATER_THAN;
        info.precedence = 30;

    case .GEQ_THAN;
        info.op_kind = .GEQ_THAN;
        info.precedence = 30;

    // Boolean and bitwise operators
    case .OR;
        info.op_kind = .OR;
        info.precedence = 20;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .OR);

    case .AND;
        info.op_kind = .AND;
        info.precedence = 20;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .AND);

    case .BIT_OR;
        info.op_kind = .BIT_OR;
        info.precedence = 20;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .BIT_OR);

    case .BIT_XOR;
        info.op_kind = .BIT_XOR;
        info.precedence = 20;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .BIT_XOR);

    case .BIT_AND;
        info.op_kind = .BIT_AND;
        info.precedence = 20;
        info.check_operands = #bake_arguments check_keyword_binary_operands(self = .BIT_AND);

    case;
        return false, info;
    }

    return true, info;
}

unwrap :: (result: Result(void)) #expand {
    err := read(result);
    if err {
        `return error(err, success_type = `result.Value);
    }
}

unwrap :: (result: Result($T)) -> T #expand {
    err, value := read(result);
    if err {
        `return error(err, success_type = `result.Value);
    }

    return value;
}

ret :: (expr: *Expr) #expand {
    `return ok(expr);
}

throw :: (value: *$T/interface Span, message: string, loc := #caller_location) #expand {
    `return error(value, message, success_type = `result.Value);
}

start_parse :: ($T : Type = *Expr) -> s32, Result(T) #expand {
    parser : void;
    p := `parser;

    result : Result(T);

    if should_skip_newlines(p) {
        while p.cursor < p.tokens.count {
            token := *p.tokens[p.cursor];
            if token.kind != .NEWLINE
                break;

            p.cursor += 1;
        }
    }

    return p.tokens[p.cursor].begin, result;
}

peek :: () -> *Token #expand {
    parser : void;
    p := `parser;

    while true {
        token := *p.tokens[p.cursor];
        if token.kind == .NEWLINE && should_skip_newlines(p) {
            p.cursor += 1;
            continue;
        }

       return token;
    }
}

pop :: () -> *Token #expand {
    parser : void;
    p := `parser;

    while true {
        token := *p.tokens[p.cursor];
        p.cursor += 1;
        if token.kind == .NEWLINE && should_skip_newlines(p) {
            continue;
        }

        return token;
    }
}

match :: (to_match: .. Token.Kind) -> bool, [] Token #expand {
    parser : void;
    p := `parser;

    assert(to_match.count > 0);
    tokens: [] Token;

    match_cursor := 0;
    cursor := p.cursor;
    while cursor < p.tokens.count {
        match_kind := to_match[match_cursor];
        token := *p.tokens[cursor];
        cursor += 1;

        if match_kind != token.kind {
            if token.kind == .NEWLINE && should_skip_newlines(p)
                continue;

            return false, tokens;
        }

        match_cursor += 1;

        if match_cursor == to_match.count {
            tokens.data = *p.tokens[p.cursor];
            tokens.count = to_match.count;

            p.cursor = cursor;
            return true, tokens;
        }
    }

    return false, tokens;
}

eat_statement_separators :: () -> bool #expand {
    parser : void;
    p := `parser;

    found_separator := false;
    while p.cursor < p.tokens.count {
        token := *p.tokens[p.cursor];
        if token.kind == {
        case .NEWLINE;
            if !should_skip_newlines(p)
                found_separator = true;
        case .SEMICOLON;
            found_separator = true;
        case;
            break;
        }

        p.cursor += 1;
    }

    return found_separator;
}

should_skip_newlines :: (parser: *Parser) -> bool {
    return parser.enclosing == .RPAREN || parser.enclosing == .RBRACKET;
}

Enclosed :: struct {
    separators : [] Token.Kind;
    extra_stops : [] Token.Kind;
    enclosing : Token.Kind;
    consume_stop : bool;
    enable_assign_binary_expr : bool;
    #if LIU_DEBUG {
    location : Source_Code_Location;
    }

    // @Todo consume_stop and extra_stops are only in here for the benefit of tuples.
    // maybe tuples just shouldn't use this code?
}

enclosed :: (enclosing: Token.Kind, separators: .. Token.Kind, extra_stops : [] Token.Kind = .[], consume_stop := true, enable_assign_binary_expr := false, loc := #caller_location) -> Enclosed {
    iter : Enclosed;
    iter.enclosing = enclosing;
    iter.separators = separators;
    iter.extra_stops = extra_stops;
    iter.consume_stop = consume_stop;
    iter.enable_assign_binary_expr = enable_assign_binary_expr;
    #if LIU_DEBUG      iter.location = loc;

    return iter;
}

for_expansion :: (iter: *Enclosed, body: Code, flags: For_Flags) #expand {
    `it : Result(void);
    `it_index : void;

    parser : void;
    p := `parser;

    previous_enclosing := p.enclosing;
    p.enclosing = iter.enclosing;
    defer p.enclosing = previous_enclosing;

    previous_assign_enable := p.enable_assign_binary_expr;
    p.enclosing = iter.enclosing;
    p.enable_assign_binary_expr = iter.enable_assign_binary_expr;
    defer p.enable_assign_binary_expr = previous_assign_enable;

    token := *p.tokens[p.cursor];
    keep_looping, had_separator := true, true;
    while keep_looping {
        if token.kind == iter.enclosing || array_find(iter.extra_stops, token.kind) {
            // we found a stopping point
            if iter.consume_stop        p.cursor += 1;
            break;
        } else if !had_separator {
            message := "missing separator between end of previous expression and beginning of next one";
            it = error(token, message, loc = iter.location);
        } else {
            it = ok();
        }

        for look_for_separator: named_break {
            #insert (break = { keep_looping = false; break look_for_separator; },
                     continue = { break look_for_separator; }) body;
        }

        had_separator = false;
        while true {
            token = *p.tokens[p.cursor];
            // @Todo this allows stuff like: name,,,,,,, 12
            if array_find(iter.separators, token.kind) {
                had_separator = true;
                token = *p.tokens[p.cursor];
                p.cursor += 1;
                continue;
            }

            if token.kind == .NEWLINE && should_skip_newlines(p) {
                token = *p.tokens[p.cursor];
                p.cursor += 1;
                continue;
            }

            break;
        }
    }
}

Buck :: ($T: Type) -> *T #expand {
    parser: void;
    p := `parser;

    expr := Ast.Buck(T);
    expr.begin = `begin;
    expr.end = p.tokens[p.cursor].end;
    return expr;
}


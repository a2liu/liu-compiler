#import "gone";
#import "Basic";
#import "buckets";
#import "lexer";
#import "utils";

Expr :: struct {
    Kind :: enum u8 {
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

        ASSIGN;
        NOT_EQUAL;
        CHECK_EQUAL;
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
        DOT_ACCESS;
        CALL;

        // atom
        IDENT;
        EMPTY_PAREN;
    }

    SyntaxFlags :: enum_flags u8 {
        COMPTIME;
        PARENTHESIZED;
    }

    kind : Kind = .UNINITIALIZED;
    flags : SyntaxFlags = 0;
    begin : s32;
    end : s32;

    // Flags for when the exprs become typed
    // TypeFlags :: enum_flags u16 {}

    type : GoneType;
    #place type;
    do_not_used_s32 : s32;
    do_not_used_u8 : u8;
    padding_u8 : u8; // @Todo we can use these for flags
    padding_u16 : u16;

    // These bois make sure that nothing fishy happens to GoneType, because we use its padding for data
    #assert(size_of(GoneType) == 8);
    #assert(type_info(GoneType).members.count == 2);
    #assert(type_info(type_of(GoneType.type_id)) == type_info(s32));
    #assert(type_info(type_of(GoneType.pointer_count)) == type_info(u8));
    #assert(type_info(GoneType).members[0].type == type_info(type_of(GoneType.type_id)));
}

BinaryExpr :: struct {
    using _base : Expr;
    left : *Expr;
    right : *Expr;
}

TupleExpr :: struct {
    using _base : Expr;
    _base.kind = .TUPLE;
    members : [] *Expr; // members allocated right after tuple struct
}

BlockExpr :: struct {
    using _base : Expr;
    _base.kind = .BLOCK;
    statements : [] *Expr; // statements allocated right after block struct
}

ModuleExpr :: struct {
    using _base : Expr;
    _base.kind = .MODULE;
    file_id : s32;
    statements : [] *Expr; // statements allocated right after module struct
}

CallExpr :: struct {
    using _base : Expr;
    _base.kind = .CALL;
    callee: *Expr;
    arguments : [] *Expr; // arguments allocated right after call struct
}

IdentExpr :: struct {
    using _base : Expr;
    _base.kind = .IDENT;
    ident_symbol : s32;
}

DotAccessExpr :: struct {
    using _base : Expr;
    _base.kind = .DOT_ACCESS;
    field_symbol : s32;
    base_object : *Expr;
}

DeclarationExpr :: struct {
    using _base : Expr;
    _base.kind = .DECLARATION;
    type_declaration_nullable : *Expr;
    value_nullable : *Expr;
    ident_symbol : s32;
}

DeclarationSplitExpr :: struct {
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
            module := cast(*ModuleExpr) it;
            visit(..module.statements);

        case .BLOCK;
            block := cast(*BlockExpr) it;
            visit(..block.statements);

        case .TUPLE;
            tuple := cast(*TupleExpr) it;
            visit(..tuple.members);

        case .DECLARATION;
            decl := cast(*DeclarationExpr) it;
            visit(decl.type_declaration_nullable, decl.value_nullable);

        case .DECLARATION_SPLIT;
            decl := cast(*DeclarationSplitExpr) it;
            visit(decl.type_declaration_nullable, decl.value_nullable);

        // Binary op
        case .PLUS;             #through;
        case .MINUS;            #through;
        case .MULTIPLY;         #through;
        case .DIVIDE;           #through;
        case .ASSIGN;           #through;
        case .NOT_EQUAL;        #through;
        case .CHECK_EQUAL;      #through;
        case .LESS_THAN;        #through;
        case .LEQ_THAN;         #through;
        case .GREATER_THAN;     #through;
        case .GEQ_THAN;         #through;
        case .OR;               #through;
        case .AND;              #through;
        case .BIT_OR;           #through;
        case .BIT_XOR;          #through;
        case .BIT_AND;
            binary := cast(*BinaryExpr) it;
            visit(binary.left, binary.right);
        }
    }
}

Parser :: struct {
    buckets: BucketList;
    tokens : [..] Token;
    cursor : s64 = 0;
    enclosing : Token.Kind = .EOF;

    consume_lexer_and_make :: (lexer: *Lexer) -> Result(Parser) {
        result : Result(Parser);
        parser := *result.value;

        token := lex_token(lexer);
        while true {
            if !token.did_succeed {
                result.did_succeed = false;
                result.error = token.error;
                result.begin = token.begin;
                result.end = token.end;

                return result;
            }

            array_add(*parser.tokens, token.value);
            if token.kind == .EOF
                break;

            token = lex_token(lexer);
        }

        parser.buckets = BucketList.make();
        result.begin = -1;
        result.end = -1;

        return result;
    }

    free :: (parser: *Parser) {
        array_reset(*parser.tokens);
    }
}

for_expansion :: (parser: *Parser, body: Code, flags: For_Flags) #expand {
    assert(parser.enclosing == .EOF);
    eat_statement_separators(extend_result = false);

    extra_exprs : [..] *Expr;
    extra_exprs_cursor := 0;
    defer array_free(extra_exprs);

    `it : Result(*Expr);
    `it_index : void;

    for enclose_result: enclosed(.EOF, .NEWLINE, .SEMICOLON) {
        for run_body: named_break {
            if !enclose_result.did_succeed {
                it.did_succeed = false;
                it.begin = enclose_result.begin;
                it.end = enclose_result.end;
                it.error = enclose_result.error;
                break run_body;
            }

            if extra_exprs_cursor < extra_exprs.count {
                it.did_succeed = true;
                it.value = extra_exprs[extra_exprs_cursor];
                it.begin = it.value.begin;
                it.end = it.value.end;
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

parse_file :: (symbols: *Symbols, file_id: s32, file_data: string) -> Result(*ModuleExpr) {
    lexer := Lexer.make(file_data, symbols);
    result : Result(*ModuleExpr);
    parser := *unwrap(Parser.consume_lexer_and_make(*lexer));
    defer Parser.free(parser);

    result = start_result(*ModuleExpr);

    file_statements : [..] *Expr;
    defer array_free(file_statements);

    for expr_result: parser {
        expr := unwrap(expr_result);
        array_add(*file_statements, expr);
    }

    module := Buck(ModuleExpr);
    module.file_id = file_id;
    module.statements = BuckArray(file_statements);

    result.value = module;
    return result;
}

// Expressions that cannot be assigned to a value or used in larger expression
// without parens. Like assignment and variable mutation.
//
// On success, returns data through `additional`, and return value contains first
// value in `additional`. This could probably be a lil cleaner, but meh.
parse_statement_expr :: (parser: *Parser, additional: *[..] *Expr) -> Result(*Expr) {
    result := start_result();

    // simple declarations
    success, matches := match(.IDENT, .COLON);
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

// Expressions that can be assigned to a value without parens, but can't be in a
// larger expression without parens. i.e. blocks or control flow stuff
parse_complete_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result();

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

    expr := unwrap(parse_binary_expr(parser));
    success, matches = match(.COMMA);
    if !success         ret(expr);

    // tuples: a, b, c
    tuple_exprs : [..] *Expr;
    array_add(*tuple_exprs, expr);
    defer array_free(tuple_exprs);

    stops := Token.Kind.[.NEWLINE, .SEMICOLON, .EOF];

    for enclosed(parser.enclosing, .COMMA, extra_stops = stops, consume_stop = false) {
        unwrap(it);
        expr = unwrap(parse_binary_expr(parser));
        array_add(*tuple_exprs, expr);
    }

    tuple := Buck(TupleExpr);
    tuple.members = BuckArray(tuple_exprs);

    ret(tuple);
}

parse_binary_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result();
    expr := unwrap(parse_binary_expr(parser, 0));
    ret(expr);
}

// binary expressions, like a + b + c + d
parse_binary_expr :: (parser: *Parser, min_precedence : s64) -> Result(*Expr) {
    result := start_result();

    expr := unwrap(parse_unary_expr(parser));

    // https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
    // This algorithm is supposed to be efficient. No idea if that's actually true,
    // but it is incredibly concise.
    token := peek();
    while true {
        is_op, info := binary_operator_info(token.kind);
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

// infix and postfix expressions, like deref a[1], a.b.c[13](12)
parse_unary_expr :: (parser: *Parser) -> Result(*Expr) {
    result := start_result();

    // parse prefix recursively
    // @Todo

    expr := unwrap(parse_atom(parser));

    while true {
        success, matches := match(.LPAREN);
        if success {
            args : [..] *Expr;
            defer array_free(args);

            for enclosed(.RPAREN, .COMMA) {
                unwrap(it);
                arg := unwrap(parse_binary_expr(parser));
                array_add(*args, arg);
            }

            call := Buck(CallExpr);
            call.callee = expr;
            call.arguments = BuckArray(args);

            expr = call;

        }

        break;
    }

    ret(expr);
}

// Atoms like 12, begin, (12 + 13)
parse_atom :: (parser: *Parser) -> Result(*Expr) {
    result := start_result();

    success, matches := match(.IDENT);
    if success {
        expr := Buck(IdentExpr);
        expr.ident_symbol = matches[0].ident_symbol;

        ret(expr);
    }

    success, matches = match(.LPAREN);
    if success {
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
            expr.flags = expr.flags | .PARENTHESIZED;

            ret(expr);
        }

        block := Buck(BlockExpr);
        block.statements = BuckArray(paren_statements);

        ret(block);
    }

    token := peek();
    throw(token, "didn't recognize token when parsing atom");
}

#scope_file

Enclosed :: struct {
    separators : [] Token.Kind;
    extra_stops : [] Token.Kind;
    enclosing : Token.Kind;
    consume_stop : bool;

    // @Todo consume_stop and extra_stops are only in here for the benefit of tuples.
    // maybe tuples just shouldn't use this code?
}

enclosed :: (enclosing: Token.Kind, separators: .. Token.Kind, extra_stops : [] Token.Kind = .[], consume_stop := true) -> Enclosed {
    iter : Enclosed;
    iter.enclosing = enclosing;
    iter.separators = separators;
    iter.extra_stops = extra_stops;
    iter.consume_stop = consume_stop;

    return iter;
}

for_expansion :: (iter: *Enclosed, body: Code, flags: For_Flags) #expand {
    `it : Result(void);
    `it_index : void;

    parser : void;
    p := `parser;

    previous := p.enclosing;
    p.enclosing = iter.enclosing;
    defer p.enclosing = previous;

    token := *p.tokens[p.cursor];
    keep_looping, had_separator := true, true;
    while keep_looping {
        if token.kind == iter.enclosing || array_find(iter.extra_stops, token.kind) {
            // we found a stopping point
            if iter.consume_stop        p.cursor += 1;
            break;
        } else if !had_separator {
            it.begin = token.begin;
            it.end = token.end;
            it.did_succeed = false;
            it.error = "missing separator between end of previous expression and beginning of next one";
        } else {
            it.did_succeed = true;
            it.begin = -1;
            it.end = -1;
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


BinaryExprInfo :: struct {
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

binary_operator_info :: (kind: Token.Kind) -> bool, BinaryExprInfo {
    success := true;
    info : BinaryExprInfo;

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

    // Simple assignment
    case .EQUAL_SIGN;
        info.op_kind = .ASSIGN;
        info.precedence = 10;

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
        success = false;
    }

    return success, info;
}

unwrap :: (result: Result(void)) #expand {
    if !result.did_succeed {
        outer_result := `result;
        outer_result.did_succeed = false;
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
        outer_result.did_succeed = false;
        outer_result.begin = result.begin;
        outer_result.end = result.end;
        outer_result.error = result.error;

        `return outer_result;
    }

    `result.end = max(`result.end, result.end);
    return result.value;
}

ret :: (expr: *Expr) #expand {
    result : Result(*Expr) = `result;
    result.value = expr;
    result.begin = expr.begin;
    result.end = expr.end;

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

start_result :: ($T : Type = *Expr) -> Result(T) #expand {
    parser : void;
    p := `parser;

    result : Result(T);
    result.error = "internal error? result might not have been initialized";

    if should_skip_newlines(p) {
        while p.cursor < p.tokens.count {
            token := *p.tokens[p.cursor];
            if token.kind != .NEWLINE
                break;

            p.cursor += 1;
        }
    }

    result.begin = p.tokens[p.cursor].begin;
    result.end = result.begin;

    return result;
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

       `result.end = token.end;
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

        `result.end = token.end;
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
            `result.end = p.tokens[p.cursor - 1].end;
            return true, tokens;
        }
    }

    return false, tokens;
}

eat_statement_separators :: ($extend_result := true) -> bool #expand {
    parser : void;
    p := `parser;

    found_separator := false;
    #if extend_result {
    end := `result.end;
    }
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

        #if extend_result {
        end = token.end;
        }
        p.cursor += 1;
    }

    #if extend_result {
    `result.end = end;
    }
    return found_separator;
}

should_skip_newlines :: (parser: *Parser) -> bool {
    return parser.enclosing == .RPAREN || parser.enclosing == .RBRACKET;
}

Buck :: ($T: Type) -> *T #expand {
    parser : void;
    p := `parser;

    push_allocator(bucket_allocator, *p.buckets);
    value := New(T, initialized = true);
    value.end = `result.end;
    value.begin = `result.begin;

    return value;
}

BuckArray :: (array: [] $T) -> [] T #expand {
    parser : void;
    p := `parser;

    push_allocator(bucket_allocator, *p.buckets);
    out : [] T = NewArray(array.count, T, initialized = false);
    memcpy(out.data, array.data, array.count * size_of(T));
    return out;
}

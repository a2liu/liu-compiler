#import "Basic";
#import "Hash_Table";

#import "buckets";
#import "liu";
#import "ast";

Scope :: struct {
    ComptimeDecl :: struct {
        decl: *DeclarationExpr;
        index: s64;
    }

    comptime_variables : Table(s32, ComptimeDecl);
    runtime_variables : Table(s32, *DeclarationIdent);
    parent: *Scope = null;

    make :: (parent : *Scope = null) -> Scope {
        scope : Scope;

        init(*scope.comptime_variables);
        init(*scope.runtime_variables);

        return scope;
    }
}

check_decl :: (decl_node: *DeclarationExpr, scope: *Scope,
               comptime := false) -> Result(void) {
    declared_type := UNSPECIFIED_TYPE;
    type_decl := decl_node.type_declaration_nullable;
    if type_decl {
        unwrap(check_expr(type_decl, scope));
        declared_type = unwrap(as_type_expr(type_decl));
    }

    value_type := UNSPECIFIED_TYPE;
    value := decl_node.value_nullable;
    assert(value != null); // @Todo this should probably be allowed
    unwrap(check_expr(value, scope, expected_type = declared_type));
    value_type = type_of_expr(value);

    declared_type = unwrap(check_type_transition(decl_node, declared_type, value_type));

    assert(decl_node.idents.count == 1, "haven't implemented multiple variable decls yet");
    ident := decl_node.idents[0];

    if comptime {
        if !is_const(value)
            throw(value, "value used in constant context wasn't a constant");

        set_type(ident, declared_type);
        if declared_type == TYPE_TYPE {
            ident.const_value.as_type = unwrap(as_type_expr(value));
        } else if declared_type == S64_TYPE {
            ident.const_value.as_s64 = value.const_value.as_s64;
        } else {
            assert(false, "declared type was %", declared_type);
        }

        ident.type_flags |= .IS_CONST;

        ret(decl_node, NONE_TYPE);
    }

    previous, found := table_find(scope.runtime_variables, ident.symbol);
    if found
        throw(decl_node, "redeclared identifier");

    // @Todo this needs to change when i add supporting compile-time declarations
    set_type(ident, declared_type);
    table_add(*scope.runtime_variables, ident.symbol, ident);

    ret(decl_node, NONE_TYPE);
}

check_type_transition :: (node: *$T/Expr, target: LiuType, value_type: LiuType) -> Result(LiuType) {
    assert(value_type != UNSPECIFIED_TYPE);

    if target == value_type
        return ok(target);

    if target == UNSPECIFIED_TYPE
        return ok(value_type);

    return error(node, "type mismatch", success_type = LiuType);
}

check_file :: (file: *FileExpr) -> Result(void) {
    start_tc(file);
    use_tree(file);

    global_scope := Scope.make();
    unwrap(check_scope(file.statements, *global_scope));
    set_type(file, NONE_TYPE);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
    scope := Scope.make();
    unwrap(check_scope(block.statements, *scope));

    set_type(block, NONE_TYPE);
    ret();
}

check_scope :: (stmts: [] *Expr, scope: *Scope) -> Result(void) {
    for stmt: stmts {
        if stmt.kind != .COMPTIME_DECLARATION       continue;

        // predeclare declaration
        decl := cast(*DeclarationExpr) stmt;

        assert(decl.idents.count == 1, "haven't implemented multiple variable decls yet");
        ident := decl.idents[0];

        previous, found := table_find(scope.comptime_variables, ident.symbol);
        if found
            throw(decl, "redeclared identifier");

        comptime_decl : Scope.ComptimeDecl;
        comptime_decl.decl = decl;
        comptime_decl.index = 0;
        table_add(*scope.comptime_variables, ident.symbol, comptime_decl);
    }

    for stmt: stmts { // Compile comptime values first
        if stmt.kind != .COMPTIME_DECLARATION       continue;

        decl := cast(*DeclarationExpr) stmt;
        if !is_typed(decl) {
            decl.type_flags |= .CHECKING_IN_PROGRESS;
            unwrap(check_decl(decl, scope, comptime = true));
        }
    }


    for stmt: stmts {
        unwrap(check_expr(stmt, scope));
    }

    ret();
}

check_expr :: (expr: *Expr, scope: *Scope, expected_type := UNSPECIFIED_TYPE) -> Result(void) {
    start_tc(expr);

    if expr.kind == {
    case .UNINITIALIZED;
        assert(false);

    case .FILE;
        assert(false, "files within other expressions doesn't make any sense.");

    case .BLOCK;
        block := cast(*BlockExpr) expr;
        unwrap(check_block(block, scope));
        ret();

    case .INTEGER;
        literal := cast(*IntegerExpr) expr;
        literal.type_flags |= .IS_CONST;
        ret(literal, S64_TYPE);

    case .IDENT;
        ident := cast(*IdentExpr) expr;
        decl := unwrap(search_scope(scope, ident.symbol));
        if !decl
            throw(ident, "unrecognized identifier");

        ident.declaration = decl;
        if is_const(decl) {
            ident.type_flags |= .IS_CONST;
            ident.const_value = decl.const_value;
            ret(ident, decl.type);
        }

        err, type_value := read(as_type_expr(decl));
        if err {
            ret(ident, type_of_expr(decl));
        }

        ret_type(ident, type_value);

    case .CALL;
        // @Todo lmao this is totally wrong
        call := cast(*CallExpr) expr;
        ret(call, NONE_TYPE);

    case .ADD;
        // @Todo this doesn't really scale, nor does it really check whether or
        // not the given type can take this operator. IDK man we'll see i guess.
        plus := cast(*BinaryExpr) expr;
        unwrap(check_expr(plus.left, scope));
        unwrap(check_expr(plus.right, scope));
        left, right := plus.left, plus.right;
        expr_type := unwrap(check_type_transition(plus.left, expected_type, left.type));
        expr_type = unwrap(check_type_transition(plus.left, expr_type, right.type));

        ret(plus, expr_type);

    case .COMPTIME_DECLARATION;
        assert(is_typed(expr));
        ret();

    case .DECLARATION;
        decl := cast(*DeclarationExpr) expr;
        unwrap(check_decl(decl, scope));
        ret();
    }

    assert(false, "% expressions are unimplemented", expr.kind);
    ret(expr, UNSPECIFIED_TYPE); // for control flow warnings
}

as_type_expr :: (expr: *Expr) -> Result(LiuType) {
    if !is_const(expr)
        return error(expr, "expression isn't constant!", success_type = LiuType);

    if expr.type != TYPE_TYPE
        return error(expr, "the value here needs to be a type", success_type = LiuType);

    return ok(expr.const_value.as_type);
}

typechecker_init :: () {
    builtin_scope = Scope.make();
    buckets := BucketList.make();

    idents : [..] *DeclarationIdent;
    symbols : [..] s32;
    defer array_free(idents);
    defer array_free(symbols);

    remember_allocators(*idents);
    remember_allocators(*symbols);

    builtin_type_name :: (symbol: s32, ty: LiuType) #expand {
        ident := New(DeclarationIdent);
        ident.symbol = symbol;
        ident.begin = -1;
        ident.end = -1;
        set_type_as_value(ident, ty);
        array_add(*idents, ident);
        array_add(*symbols, symbol);
    }

    push_allocator(bucket_allocator, *buckets);

    builtin_type_name(S64_SYMBOL, S64_TYPE);
    builtin_type_name(TYPE_SYMBOL, TYPE_TYPE);

    decl := New(DeclarationExpr);
    decl.idents = array_copy(idents);
    decl.begin = -1;
    decl.end = -1;
    set_type(decl, NONE_TYPE);

    comptime_decl : Scope.ComptimeDecl;
    comptime_decl.decl = decl;
    for symbols {
        comptime_decl.index = it_index;
        table_add(*builtin_scope.comptime_variables, it, comptime_decl);
    }
}

#scope_file

// comptime builtins are things like s64
builtin_scope : Scope = ---;

search_scope :: (_scope: *Scope, ident: s32, comptime := false) -> Result(*DeclarationIdent) {
    decl, success := table_find(builtin_scope.runtime_variables, ident);
    assert(!success); // @Todo should there be something here?

    comptime_decl : Scope.ComptimeDecl;
    comptime_decl, success = table_find(builtin_scope.comptime_variables, ident);
    if success      return ok(comptime_decl.decl.idents[comptime_decl.index]);

    scope := _scope;
    while scope {
        if !comptime {
            decl, success := table_find(scope.runtime_variables, ident);
            if success      return ok(decl);
        }

        comptime_decl, success := table_find(scope.comptime_variables, ident);
        if !is_typed(comptime_decl.decl) {
            comptime_decl.decl.type_flags |= .CHECKING_IN_PROGRESS;
            result := check_decl(comptime_decl.decl, scope, comptime = true);
            unwrap(result, success_type = *DeclarationIdent);
        }
        if success      return ok(comptime_decl.decl.idents[comptime_decl.index]);

        scope = scope.parent;
    }

    out : *DeclarationIdent = null;
    return ok(out);
}

ret :: () #expand {
    `return ok();
}

ret :: (expr: *Expr, type: LiuType) #expand {
    set_type(expr, type);

    `return ok();
}

ret_type :: (expr: *Expr, type: LiuType) #expand {
    set_type_as_value(expr, type);

    `return ok();
}

throw :: (value: *$T/interface Span, message: string, loc := #caller_location) #expand {
    `return error(value, message, loc = loc);
}

unwrap :: (result: Result($T), $success_type := void) -> T #expand
#modify {
    if T == type_info(void) {
        T = null;
    }
}
{
    err, success := read(result);
    if err      `return error(err, success_type = success_type);

    return success;
}

unwrap :: (result: Result(void), $success_type := void) #expand {
    err := read(result);
    if err      `return error(err, success_type = success_type);
}

start_tc :: (value: *$T, loc := #caller_location) #expand {
    checking := 0 != (value.type_flags & .CHECKING_IN_PROGRESS);
    assert(!checking, "circular dependency detected", loc = loc);

    if is_typed(value)       `return ok();
    value.type_flags |= .CHECKING_IN_PROGRESS;
}

set_type :: inline (value : *Expr, ty: LiuType) {
    assert(!is_typed(value));
    assert(ty != UNSPECIFIED_TYPE);

    value.type = ty;
    value.type_flags |= .IS_TYPED;
    value.type_flags &= ~.CHECKING_IN_PROGRESS;
}

set_type_as_value :: inline (value : *Expr, ty: LiuType) {
    assert(!is_typed(value));
    assert(ty != UNSPECIFIED_TYPE, "set null as type value %", ty);

    value.type = TYPE_TYPE;
    value.type_flags &= ~.CHECKING_IN_PROGRESS;
    value.type_flags |= .IS_TYPED;
    value.type_flags |= .IS_CONST;
    value.const_value.as_type = ty;
}

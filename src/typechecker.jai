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
    comptime_capture := false;

    make :: (parent : *Scope = null, comptime := false) -> Scope {
        scope : Scope;

        init(*scope.comptime_variables);
        init(*scope.runtime_variables);
        scope.parent = parent;
        scope.comptime_capture = comptime;

        return scope;
    }
}

check_decl :: (decl_node: *DeclarationExpr, scope: *Scope) -> Result(void) {
    comptime := decl_node.kind == .COMPTIME_DECLARATION;
    declared_type := UNSPECIFIED_TYPE;
    type_decl := decl_node.type_declaration_nullable;
    if type_decl {
        type_scope := Scope.make(scope, comptime = true);
        unwrap(check_expr(type_decl, *type_scope));
        declared_type = unwrap(as_type_expr(type_decl));
    }

    value_type := UNSPECIFIED_TYPE;
    value := decl_node.value_nullable;
    // assert(value != null); // @Todo this should probably be allowed, idk
    if value != null {
        value_scope := Scope.make(scope, comptime);
        unwrap(check_expr(value, *value_scope, expected_type = declared_type));
        value_type = type_of_expr(value);
    }

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

        ret(decl_node, VOID_TYPE);
    }

    previous, found := table_find(scope.runtime_variables, ident.symbol);
    if found
        throw(decl_node, "redeclared identifier");

    // @Todo this needs to change when i add supporting compile-time declarations
    set_type(ident, declared_type);
    table_add(*scope.runtime_variables, ident.symbol, ident);

    ret(decl_node, VOID_TYPE);
}

check_type_transition :: (node: *$T/Expr, target: LiuType, value_type: LiuType) -> Result(LiuType) {
    if value_type == UNSPECIFIED_TYPE && target == UNSPECIFIED_TYPE
        assert(false, "ya really don't know what type it is eh?");

    if target == value_type
        return ok(target);

    if target == UNSPECIFIED_TYPE
        return ok(value_type);
    if value_type == UNSPECIFIED_TYPE
        return ok(target);

    return error(node, "type mismatch", success_type = LiuType);
}

check_file :: (file: *FileExpr) -> Result(void) {
    start_tc(file);
    use_tree(file);

    global_scope := Scope.make();
    unwrap(check_scope(file.statements, *global_scope));
    set_type(file, VOID_TYPE);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
    scope := Scope.make(parent_scope);
    unwrap(check_scope(block.statements, *scope));

    set_type(block, VOID_TYPE);
    ret();
}

check_proc :: (proc_expr: *ProcedureExpr, parent_scope: *Scope) -> Result(void) {
    enclosing_scope := Scope.make(parent_scope, true); // @Todo get working closures
    for param: proc_expr.params {
        unwrap(check_decl(param, *enclosing_scope));
    }

    set_type(proc_expr, VOID_TYPE);
    proc_expr.type_flags |= .IS_CONST;
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
            unwrap(check_decl(decl, scope));
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
        ret(call, VOID_TYPE);

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

    case .PROCEDURE;
        proc_expr := cast(*ProcedureExpr) expr;
        unwrap(check_proc(proc_expr, scope));
        ret();

    case .COMPTIME_DECLARATION;
        assert(is_typed(expr));
        ret();

    case .DECLARATION;
        decl := cast(*DeclarationExpr) expr;
        unwrap(check_decl(decl, scope));
        ret();
    }

    message := sprint("% expressions are unimplemented", expr.kind);
    throw(expr, message);
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
    _static_buckets = BucketList.make();
    remember_allocators(*_types_array);

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
        set_value(ident, ty);
        array_add(*idents, ident);
        array_add(*symbols, symbol);
    }

    push_allocator(bucket_allocator, *_static_buckets);

    builtin_type_name(S64_SYMBOL, S64_TYPE);
    builtin_type_name(TYPE_SYMBOL, TYPE_TYPE);
    builtin_type_name(VOID_SYMBOL, VOID_TYPE);

    decl := New(DeclarationExpr);
    decl.idents = array_copy(idents);
    decl.begin = -1;
    decl.end = -1;
    set_type(decl, VOID_TYPE);

    comptime_decl : Scope.ComptimeDecl;
    comptime_decl.decl = decl;
    for symbols {
        comptime_decl.index = it_index;
        table_add(*builtin_scope.comptime_variables, it, comptime_decl);
    }

    builtin_type :: (sym: LiuType, $T: Type) -> *T {
        #assert(inherits_from(T, TypeInfo));
        assert_eq(sym.type_id, cast(s32) (_types_array.count + 1));
        ptr := New(T);
        array_add(*_types_array, ptr);

        return ptr;
    }

    none_type := builtin_type(VOID_TYPE, TypeInfo);
    none_type.kind = .NONE;

    int_type := builtin_type(S64_TYPE, TypeInfo);
    int_type.kind = .INTEGER;

    type_type := builtin_type(TYPE_TYPE, TypeInfo);
    type_type.kind = .TYPE;
}

#scope_file

operator [] :: (db: type_of(types), ty: LiuType) -> *TypeInfo {
    assert(ty.type_id > 0);
    return _types_array[ty.type_id - 1];
}

// comptime builtins are things like s64
_static_buckets : BucketList = ---;
builtin_scope : Scope = ---;
_types_array : [..] *TypeInfo;
types : struct {};

search_scope :: (_scope: *Scope, ident: s32) -> Result(*DeclarationIdent) {
    decl, success := table_find(builtin_scope.runtime_variables, ident);
    assert(!success); // @Todo should there be something here? Maybe the context?

    comptime_decl : Scope.ComptimeDecl;
    comptime_decl, success = table_find(builtin_scope.comptime_variables, ident);
    if success      return ok(comptime_decl.decl.idents[comptime_decl.index]);

    scope := _scope;
    only_comptime := false;
    while scope {
        if !only_comptime {
            decl, success := table_find(scope.runtime_variables, ident);
            if success      return ok(decl);
        }

        comptime_decl, success := table_find(scope.comptime_variables, ident);
        if success {
            if !is_typed(comptime_decl.decl) {
                comptime_decl.decl.type_flags |= .CHECKING_IN_PROGRESS;
                result := check_decl(comptime_decl.decl, scope);
                unwrap(result, success_type = *DeclarationIdent);
            }

            return ok(comptime_decl.decl.idents[comptime_decl.index]);
        }

        only_comptime = only_comptime || scope.comptime_capture;
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
    set_value(expr, type);

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

set_value :: (expr: *Expr, value: s64) {
    assert(!is_typed(expr));

    expr.type = S64_TYPE;
    expr.type_flags |= .IS_TYPED;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
    expr.type_flags |= .IS_CONST;
    expr.const_value.as_s64 = value;
}

set_value :: (expr : *Expr, value: LiuType) {
    assert(!is_typed(expr));
    assert(value != UNSPECIFIED_TYPE, "set null as type expr %", value);

    expr.type = TYPE_TYPE;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
    expr.type_flags |= .IS_TYPED;
    expr.type_flags |= .IS_CONST;
    expr.const_value.as_type = value;
}

set_type :: inline (expr : *Expr, ty: LiuType) {
    assert(!is_typed(expr));
    assert(ty != UNSPECIFIED_TYPE);

    expr.type = ty;
    expr.type_flags |= .IS_TYPED;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
}

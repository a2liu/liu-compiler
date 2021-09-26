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
    Kind :: enum u8 {
        BASE;
        PROC;
    }

    kind : Kind = .BASE;
    comptime_variables : Table(s32, ComptimeDecl);
    runtime_variables : Table(s32, *DeclarationIdent);
    parent: *Scope = null;
    comptime_capture := false;

    init :: (scope: *Scope, parent : *Scope, comptime : bool) {
        init(*scope.comptime_variables);
        init(*scope.runtime_variables);
        scope.parent = parent;
        scope.comptime_capture = comptime;
    }

    uninit :: (scope: *Scope) {
        uninit(*scope.comptime_variables);
        uninit(*scope.runtime_variables);
    }
}

init_scoped :: (scope: *Scope, parent : *Scope = null, comptime := false) #expand {
    Scope.init(scope, parent, comptime);

    `defer Scope.uninit(scope);
}

ProcScope :: struct {
    using _base : Scope;
    _base.kind = .PROC;
    return_type : LiuType;
}

init_scoped :: (scope: *ProcScope, parent : *Scope, return_type : LiuType, comptime := false) #expand {
    Scope.init(*scope._base, parent, comptime);
    scope.return_type = return_type;

    `defer Scope.uninit(scope);
}

check_decl :: (decl_node: *DeclarationExpr, scope: *Scope) -> Result(void) {
    comptime := decl_node.kind == .COMPTIME_DECLARATION;
    declared_type := UNSPECIFIED_TYPE;
    type_decl := decl_node.type_declaration_nullable;
    if type_decl {
        type_scope : Scope;
        init_scoped(*type_scope, scope, comptime = true);

        unwrap(check_expr(type_decl, *type_scope));
        declared_type = unwrap(as_type_expr(type_decl));
    }

    value_type := UNSPECIFIED_TYPE;
    value := decl_node.value_nullable;
    // assert(value != null); // @Todo this should probably be allowed, idk
    if value != null {
        value_scope : Scope;
        init_scoped(*value_scope, scope, comptime);
        unwrap(check_expr(value, *value_scope, expected_type = declared_type));
        value_type = unwrap(type_of_expr(value));
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

    global_scope : Scope;
    init_scoped(*global_scope);
    unwrap(check_scope(file.statements, *global_scope));
    set_type(file, VOID_TYPE);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
    scope : Scope;
    init_scoped(*scope, parent_scope);
    unwrap(check_scope(block.statements, *scope));

    set_type(block, VOID_TYPE);
    ret();
}

check_proc :: (proc_expr: *ProcedureExpr, parent_scope: *Scope) -> Result(void) {
    params_scope : Scope;
    init_scoped(*params_scope, parent_scope, true); // @Todo get working closures
    unwrap(check_scope(cast([] *Expr) proc_expr.params, *params_scope));

    // @Todo How do we do parameterized return types? Scan beforehand? Lazy errors?
    // probably scan beforehand.
    unwrap(check_expr(proc_expr.return_type, *params_scope));
    return_type := unwrap(as_type_expr(proc_expr.return_type));

    proc_scope : ProcScope;
    init_scoped(*proc_scope, *params_scope, return_type, false);
    unwrap(check_expr(proc_expr.body, *proc_scope));

    const_proc(proc_expr, VOID_TYPE);
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
        decl_type := unwrap(type_of_expr(decl));
        if is_const(decl) {
            ident.type_flags |= .IS_CONST;
            ident.const_value = decl.const_value;
        }

        ret(ident, decl_type);

    case .CALL;
        // @Todo lmao this is totally wrong
        call := cast(*CallExpr) expr;
        ret(call, VOID_TYPE);

    case .RETURN;
        return_expr := cast(*ReturnExpr) expr;
        unwrap(check_expr(return_expr.value, scope));
        ret(return_expr, VOID_TYPE);

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
    // We really need memory debuggers. Use-after-free should be an obvious bug
    // to catch in debug builds, honestly. Like what the fuck. Just uncommit the
    // range and set the reserved block to illegal. Like how can this not be solved.
    // I don't need malloc to be fast in GODDAMN DEBUG BUILDS. FOR FUCKS SAKE
    // OPERATING SYSTEMS HAVE SUPPORTED THIS SINCE THIS FUCKING INCEPTION OF
    // VIRTUAL MEMORY. STOP TELLING ME THESE THINGS ARE UNSAFE AND ACTUALLY DO THE
    // THINGS THAT WOULD MAKE IT SAFE.
    Scope.init(*builtin_scope, null, true);

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
        assert(is_typed(ident));
        array_add(*idents, ident);
        array_add(*symbols, symbol);
    }

    push_allocator(bucket_allocator, *_static_buckets);

    builtin_type_name(S64_SYMBOL, S64_TYPE);
    builtin_type_name(TYPE_SYMBOL, TYPE_TYPE);
    builtin_type_name(VOID_SYMBOL, VOID_TYPE);

    decl := New(DeclarationExpr);
    decl.kind = .COMPTIME_DECLARATION;
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
_types_array : [..] *TypeInfo;
types : struct {};
builtin_scope : Scope;

search_scope :: (_scope: *Scope, ident: s32) -> Result(*DeclarationIdent) {
    decl, success := table_find(builtin_scope.runtime_variables, ident);
    assert(!success); // @Todo should there be something here? Maybe the context?

    comptime_decl : Scope.ComptimeDecl;
    comptime_decl, success = table_find(builtin_scope.comptime_variables, ident);
    if success {
        decl_ident := comptime_decl.decl.idents[comptime_decl.index];
        return ok(decl_ident);
    }

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

const_proc :: (proc_expr: *ProcedureExpr, ty: LiuType) {
    assert(!is_typed(proc_expr));

    proc_expr.type = ty;
    proc_expr.type_flags |= .IS_TYPED;
    proc_expr.type_flags &= ~.CHECKING_IN_PROGRESS;
    proc_expr.type_flags |= .IS_CONST;
    proc_expr.const_value.as_proc_ptr = proc_expr;
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
    expr.type_flags |= .IS_TYPED;
    expr.type_flags |= .IS_CONST;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
    expr.const_value.as_type = value;
}

set_type :: inline (expr : *Expr, ty: LiuType) {
    assert(!is_typed(expr));
    assert(ty != UNSPECIFIED_TYPE);

    expr.type = ty;
    expr.type_flags |= .IS_TYPED;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
}

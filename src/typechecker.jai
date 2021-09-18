#import "Basic";
#import "Hash_Table";

#import "liu";
#import "ast";

Scope :: struct {
    comptime_variables : Table(s32, *DeclarationIdent);
    runtime_variables : Table(s32, *DeclarationIdent);
    parent: *Scope = null;

    make :: (parent : *Scope = null) -> Scope {
        scope : Scope;

        init(*scope.comptime_variables);
        init(*scope.runtime_variables);

        return scope;
    }
}

check_decl :: (decl_node: *DeclarationExpr, scope: *Scope) -> Result(void) {
    declared_type : LiuType = UNSPECIFIED_TYPE;
    type_decl := decl_node.type_declaration_nullable;
    if type_decl {
        unwrap(check_expr(type_decl, scope));
        declared_type = unwrap(as_type_expr(type_decl));
    }

    value_type : LiuType = UNSPECIFIED_TYPE;
    value := decl_node.value_nullable;
    assert(value != null); // @Todo this should probably be allowed
    unwrap(check_expr(value, scope, expected_type = declared_type));
    value_type = type_of_expr(value);

    assert(decl_node.idents.count == 1);

    declared_type = unwrap(check_type_transition(decl_node, declared_type, value_type));
    ident := *decl_node.idents[0];
    value_ptr := table_find_pointer(scope.runtime_variables, ident.symbol);
    if value_ptr
        throw(decl_node, "redeclared identifier");

    // @Todo this needs to change when i add supporting compile-time declarations
    set_type(ident, declared_type);
    table_add(*scope.runtime_variables, ident.symbol, ident);

    // for decl_node.idents {
    // }

    ret(decl_node, VOID_TYPE);
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
    if is_typed(file)       ret();
    use_tree(file);

    global_scope := Scope.make();
    unwrap(check_scope(file.statements, *global_scope));
    set_type(file, VOID_TYPE);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
    if is_typed(block)       ret();

    scope := Scope.make();
    unwrap(check_scope(block.statements, *scope));

    set_type(block, VOID_TYPE);
    ret();
}

check_scope :: (stmts: [] *Expr, scope: *Scope) -> Result(void) {
    for stmt: stmts {
        unwrap(check_expr(stmt, scope));
    }

    ret();
}

check_expr :: (expr: *Expr, scope: *Scope, expected_type := UNSPECIFIED_TYPE) -> Result(void) {
    if is_typed(expr)       ret();

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
        ret(literal, S64_TYPE);

    case .IDENT;
        ident := cast(*IdentExpr) expr;
        decl := search_scope(scope, ident.symbol);
        if !decl {
            throw(ident, "unrecognized identifier");
        }

        ident.declaration = decl;
        type_value_result := as_type_expr(decl);
        if type_value_result.did_succeed {
            ret_type(ident, type_value_result.value);
        }

        ret(ident, type_of_expr(decl));

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
        left_ty := type_of_expr(plus.left);
        right_ty := type_of_expr(plus.right);
        expr_type := unwrap(check_type_transition(plus.left, expected_type, left_ty));
        expr_type = unwrap(check_type_transition(plus.left, expr_type, right_ty));

        ret(plus, expr_type);

    case .DECLARATION;
        // @Todo the entire thing lmao
        decl := cast(*DeclarationExpr) expr;
        unwrap(check_decl(decl, scope));
        ret();
    }

    assert(false, "% expressions are unimplemented", expr.kind);
    ret(expr, UNSPECIFIED_TYPE); // for control flow warnings
}

as_type_expr :: (expr: *Expr) -> Result(LiuType) {
    assert((expr.type_flags & .IS_TYPED) != 0, "expr at [%,%] wasn't typed!", expr.begin, expr.end);

    if expr.type_flags & .TYPE_SLOT_IS_VALUE
        return ok(expr.type_slot);

    return error(expr, "the value here needs to be a type", success_type = LiuType);
}

typechecker_init :: () {
    builtin_scope = Scope.make();
    ident : *DeclarationIdent;

    ident = New(DeclarationIdent); // leak-gang
    ident.symbol = S64_SYMBOL;
    ident.begin = -1;
    ident.end = -1;
    set_type_as_value(ident, S64_TYPE);

    table_add(*builtin_scope.comptime_variables, S64_SYMBOL, ident);
}

#scope_file

// comptime builtins are things like s64
builtin_scope : Scope = ---;

search_scope :: (_scope: *Scope, ident: s32, search_runtime := true) -> *DeclarationIdent {
    decl, success := table_find(builtin_scope.runtime_variables, ident);
    assert(!success); // @Todo should there be something here?

    decl, success = table_find(builtin_scope.comptime_variables, ident);
    if success      return decl;

    scope := _scope;
    while scope {
        if search_runtime {
            decl, success := table_find(scope.runtime_variables, ident);
            if success      return decl;
        }

        decl, success := table_find(scope.comptime_variables, ident);
        if success      return decl;

        scope = scope.parent;
    }

    return null;
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

unwrap :: (result: Result(LiuType)) -> LiuType #expand {
    err, success := read(result);
    if err      `return error(err);

    return success;
}

unwrap :: (result: Result(void)) #expand {
    err := read(result);
    if err      `return error(err);
}

set_type :: inline (value : *Expr, ty: LiuType) {
    assert(!is_typed(value));
    assert(ty != UNSPECIFIED_TYPE);

    value.type_slot.type_id = ty.type_id;
    value.type_slot.pointer_count = ty.pointer_count;
    value.type_flags = value.type_flags | .IS_TYPED;
}

set_type_as_value :: inline (value : *Expr, ty: LiuType) {
    assert(!is_typed(value));
    assert(ty != UNSPECIFIED_TYPE, "set null as type value %", ty);

    value.type_slot.type_id = ty.type_id;
    value.type_slot.pointer_count = ty.pointer_count;
    value.type_flags = .IS_TYPED;
    value.type_flags |= .TYPE_SLOT_IS_VALUE;
}

#import "Basic";
#import "Hash_Table";

#import "buckets";
#import "liu";
#import "ast";

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

        if cased(declared_type) == {
        case CASED_TYPE_TYPE; #through;
        case CASED_S64_TYPE;
            set_type(ident, declared_type);
            ident.const_value = value.const_value;
            ident.type_flags |= .IS_CONST;
            ret(decl_node, VOID_TYPE);

        case;
            if Types[declared_type].kind == .PROC {
                set_type(ident, declared_type);
                ident.const_value = value.const_value;
                ident.type_flags |= .IS_CONST;
                ret(decl_node, VOID_TYPE);
            }

            message := sprint("declared type was %", declared_type);
            throw(decl_node, message);
        }
    }

    previous, found := table_find(scope.runtime_variables, ident.symbol);
    if found
        throw(decl_node, "redeclared identifier");

    // @Todo this needs to change when i add supporting compile-time declarations
    set_type(ident, declared_type);
    table_add(*scope.runtime_variables, ident.symbol, ident);

    ret(decl_node, VOID_TYPE);
}

// @Todo exact means the types must be semantically equivalent, and you're not allowed to generate
// a type transition
check_type_transition :: (node: *$T/Expr, target: LiuType, value_type: LiuType, $exact := false) -> Result(LiuType) {
    if value_type == UNSPECIFIED_TYPE && target == UNSPECIFIED_TYPE
        assert(false, "ya really don't know what type it is eh?");

    if target == value_type
        return ok(target);

    if target == UNSPECIFIED_TYPE
        return ok(value_type);
    if value_type == UNSPECIFIED_TYPE
        return ok(target);

    target_info := Types[target];
    value_info := Types[value_type];
    if target_info.kind == {
    case .VOID;
        if value_info.kind != .VOID {
            message := "wanted an expression of type 'void' here, didn't get it";
            return error(node, message, success_type = LiuType);
        }

        return ok(target);

    case .INTEGER;
        if value_info.kind != .INTEGER {
            message := "wanted an expression of type 's64' here, didn't get it";
            return error(node, message, success_type = LiuType);
        }

        return ok(target);

    case .TYPE;
        if value_info.kind != .TYPE {
            message := "wanted an expression of type 'type' here, didn't get it";
            return error(node, message, success_type = LiuType);
        }

        return ok(target);

    case .PROC;
        if value_info.kind != .PROC {
            message := "wanted an expression of type 'procedure' here, didn't get it";
            return error(node, message, success_type = LiuType);
        }

        target_info_proc := cast(*TypeInfoProcedure) target_info;
        value_info_proc := cast(*TypeInfoProcedure) value_info;

        output_ty_result := check_type_transition(node, target_info_proc.return_type,
                                                value_info_proc.return_type, exact = true);
        assert(unwrap(output_ty_result, success_type = LiuType) == target_info_proc.return_type);

        if target_info_proc.params.count != value_info_proc.params.count {
            message := "this expression is a procedure with the wrong number of arguments";
            return error(node, message, success_type = LiuType);
        }

        target_params, value_params := target_info_proc.params, value_info_proc.params;
        for index: 0..(target_params.count - 1) {
            output_ty_result = check_type_transition(node, target_params[index], value_params[index],
                                                     exact = true);
            assert(unwrap(output_ty_result, success_type = LiuType) == target_params[index]);
        }

        return ok(target);
    }


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
    param_types : [..] LiuType;
    defer array_free(param_types);

    for decl: proc_expr.params {
        for decl.idents {
            param_type := unwrap(type_of_expr(it));
            array_add(*param_types, param_type);
        }
    }

    // @Todo How do we do parameterized return types? Scan beforehand? Lazy errors?
    // probably scan beforehand.
    unwrap(check_expr(proc_expr.return_type, *params_scope));
    return_type := unwrap(as_type_expr(proc_expr.return_type));
    proc_type := Types.proc(..param_types, return_type = return_type);

    proc_scope : ProcScope;
    init_scoped(*proc_scope, *params_scope, return_type);
    unwrap(check_expr(proc_expr.body, *proc_scope));

    // @Todo idk man
    const_proc(proc_expr, proc_type);
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

    case .NONE;
        ret(expr, VOID_TYPE);

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
        ret(call, S64_TYPE);

    case .RETURN;
        return_type_ptr := scope_return_type(scope);
        if return_type_ptr == null
            throw(expr, "can't return in this context");

        return_expr := cast(*ReturnExpr) expr;
        to_return := return_expr.value;
        unwrap(check_expr(to_return, scope));

        return_type := << return_type_ptr;
        type_result := check_type_transition(to_return, return_type, to_return.type);
        inferred_type := unwrap(type_result);
        assert(inferred_type == return_type);

        ret(return_expr, VOID_TYPE);

    case .ADD;
        // @Todo this doesn't really scale, nor does it really check whether or
        // not the given type can take this operator. IDK man we'll see i guess.
        plus := cast(*BinaryExpr) expr;
        unwrap(check_expr(plus.left, scope));
        unwrap(check_expr(plus.right, scope));
        left, right := plus.left, plus.right;
        expr_type := unwrap(check_type_transition(left, expected_type, left.type));
        expr_type = unwrap(check_type_transition(left, expr_type, right.type));

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

#scope_file

scope_return_type :: (_scope: *Scope) -> *LiuType {
    scope := _scope;
    while scope {
        if scope.kind == .PROC {
            proc_scope := cast(*ProcScope) scope;
            return *proc_scope.return_type;
        }

        scope = scope.parent;
    }

    return null;
}

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

#import "Basic";
#import "Hash_Table";

#import "buckets";
#import "liu";
#import "ast";
#import "tir";

check_decl :: (decl_node: *DeclarationExpr, scope: *Scope) -> Result(s32) {
    comptime := decl_node.kind == .COMPTIME_DECLARATION;
    if comptime {
        for ident: decl_node.idents {
            ptr := table_find_pointer(scope.comptime_variables, ident.symbol);
            ptr.checking = true;
        }
    }

    declared_type := UNINITIALIZED_TYPE;
    type_decl := decl_node.type_declaration_nullable;
    if type_decl {
        type_scope : Scope;
        init_scoped(*type_scope, scope, comptime = true);

        type_idx := unwrap(check_expr(type_decl, *type_scope));
        type_op := index_to_op(*type_scope, type_idx);

        if type_op.kind != .CONST
            throw(type_decl, "type declaration wasn't constant");

        const_type_op := cast(*ConstOp) type_op;
        if const_type_op.expr_type != TYPE_TYPE
            throw(type_decl, "expected a type here");

        declared_type = const_type_op.value.as_type;
    }

    value_type := UNINITIALIZED_TYPE;
    value := decl_node.value_nullable;
    value_idx : s32 = -1;
    if value != null {
        value_scope : Scope;
        init_scoped(*value_scope, scope, comptime);
        value_idx = unwrap(check_expr(value, *value_scope, expected_type = declared_type));
        value_type = index_to_op(scope, value_idx).expr_type;
    }

    declared_type = unwrap(check_type_transition(decl_node, declared_type, value_type));

    assert(decl_node.idents.count == 1, "haven't implemented multiple variable decls yet");
    ident := decl_node.idents[0];

    if comptime {
        value_op := index_to_op(scope, value_idx);
        if value_op.kind != .CONST
            throw(value, "value used in constant context wasn't a constant");

        const_op := cast(*ConstOp) value_op;
        if Types[declared_type].kind == {
        case .TYPE; #through;
        case .INTEGER; #through;
        case .PROC;
            decl := const_decl_alloc(const_op, ident);
            decl.symbol = ident.symbol;

            ptr := table_find_pointer(scope.comptime_variables, ident.symbol);
            ptr.value = decl;
            ret();

        case .POINTER;
            throw(decl_node, "can't have constant value pointer");

        case;
            message := sprint("declared type was %", declared_type);
            throw(decl_node, message);
        }
    }

    previous, found := table_find(scope.runtime_variables, ident.symbol);
    if found
        throw(decl_node, "redeclared identifier");

    decl_op := alloc_op(scope, DeclOp, ident);
    decl_op.symbol = ident.symbol;
    decl_op.value = index_to_op(scope, value_idx);

    decl_info : Scope.DeclInfo;
    decl_info.decl_op = op_to_index(scope, decl_op);
    table_add(*scope.runtime_variables, ident.symbol, decl_info);

    ret();
}

// @Todo exact means the types must be semantically equivalent, and you're not allowed to generate
// a type transition
// @Todo eventually this'll probably have to output TIR to do the actual transition
check_type_transition :: (node: *$T/Expr, target: LiuType, value_type: LiuType, $exact := false) -> Result(LiuType) {
    // @Todo eventually this should probably be just "value_type == UNSPECIFIED"
    // and we'll use type variables to handle this stuff.
    if value_type == UNINITIALIZED_TYPE && target == UNINITIALIZED_TYPE
        assert(false, "ya really don't know what type it is eh?");

    if target == value_type
        return ok(target);

    if target == UNINITIALIZED_TYPE
        return ok(value_type);
    if value_type == UNINITIALIZED_TYPE
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
            message := sprint("wanted an expression of type 'type' here, got '%'", value_info.kind);
            return error(node, message, success_type = LiuType);
        }

        return ok(target);

    case .POINTER;
        if value_info.kind != .POINTER {
            message := "wanted an expression of type 'pointer' here, didn't get it";
            return error(node, message, success_type = LiuType);
        }

        target_info_ptr := cast(*LiuTypeInfoPointer) target_info;
        value_info_ptr := cast(*LiuTypeInfoPointer) value_info;

        type_result := check_type_transition(node, target_info_ptr.pointing_to,
                                          value_info_ptr.pointing_to, exact = true);
        inferred := unwrap(type_result, success_type = LiuType);

        if inferred != target_info_ptr.pointing_to
            return error(node, "pointer type mismatch", success_type = LiuType);

        return ok(target);

    case .PROC;
        if value_info.kind != .PROC {
            message := "wanted an expression of type 'procedure' here, didn't get it";
            return error(node, message, success_type = LiuType);
        }

        target_info_proc := cast(*LiuTypeInfoProcedure) target_info;
        value_info_proc := cast(*LiuTypeInfoProcedure) value_info;

        output_ty_result := check_type_transition(node, target_info_proc.return_type,
                                                value_info_proc.return_type, exact = true);
        output_ty := unwrap(output_ty_result, success_type = LiuType);
        if output_ty != target_info_proc.return_type
            return error(node, "return type mismatch", success_type = LiuType);

        if target_info_proc.params.count != value_info_proc.params.count {
            message := "this expression is a procedure with the wrong number of arguments";
            return error(node, message, success_type = LiuType);
        }

        target_params, value_params := target_info_proc.params, value_info_proc.params;
        for index: 0..(target_params.count - 1) {
            output_ty_result = check_type_transition(node, target_params[index], value_params[index],
                                                     exact = true);
            output_ty := unwrap(output_ty_result, success_type = LiuType);
            if output_ty != target_params[index]
                return error(node, "parameter type mismatch", success_type = LiuType);
        }

        return ok(target);
    }


    return error(node, "type mismatch", success_type = LiuType);
}

check_file :: (file: *FileExpr) -> Result(*TirProc) {
    global_scope : CodegenScope;
    init_scoped(*global_scope);
    unwrap(check_scope(file.statements, *global_scope), success_type = *TirProc);
    return ok(global_scope.tir_proc);
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(s32) {
    scope : Scope;
    init_scoped(*scope, parent_scope);
    unwrap(check_scope(block.statements, *scope));

    ret();
}

check_proc :: (proc_expr: *ProcedureExpr, parent_scope: *Scope) -> Result(s32) {
    params_scope : Scope;
    init_scoped(*params_scope, parent_scope, true); // @Todo get working closures
    unwrap(check_scope(cast([] *Expr) proc_expr.params, *params_scope));
    param_types : [..] LiuType;
    defer array_free(param_types);

    // for decl: proc_expr.params {
    //     for decl.idents {
    //         param_type := unwrap(type_of_expr(it));
    //         array_add(*param_types, param_type);
    //     }
    // }

    // @Todo How do we do parameterized return types? Scan beforehand? Lazy errors?
    // probably scan beforehand.
    // unwrap(check_expr(proc_expr.return_type, *params_scope));
    // return_type := unwrap(as_type_expr(proc_expr.return_type));
    // proc_type := Types.proc(..param_types, return_type = return_type);

    // proc_scope : ProcScope;
    // init_scoped(*proc_scope, *params_scope, return_type);
    // unwrap(check_expr(proc_expr.body, *proc_scope));

    // // @Todo idk man
    // const_proc(proc_expr, proc_type);
    ret();
}

check_scope :: (stmts: [] *Expr, scope: *Scope) -> Result(s32) {
    for stmt: stmts {
        if stmt.kind != .COMPTIME_DECLARATION       continue;

        // predeclare declaration
        decl := cast(*DeclarationExpr) stmt;

        assert(decl.idents.count == 1, "haven't implemented multiple variable decls yet");
        ident := decl.idents[0];

        previous, found := table_find(scope.comptime_variables, ident.symbol);
        if found
            throw(decl, "redeclared identifier");

        comptime_decl : Scope.ConstDecl;
        comptime_decl.decl = decl;
        table_add(*scope.comptime_variables, ident.symbol, comptime_decl);
    }

    for stmt: stmts { // Compile comptime values first
        if stmt.kind != .COMPTIME_DECLARATION       continue;

        decl := cast(*DeclarationExpr) stmt;
        unwrap(check_decl(decl, scope));
    }


    for stmt: stmts {
        unwrap(check_expr(stmt, scope));
    }

    ret();
}

check_expr :: (expr: *Expr, scope: *Scope, referenced := false, expected_type := UNINITIALIZED_TYPE) -> Result(s32) {
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
        // @Todo need to do type variables to support this well
        ret();

    case .INTEGER;
        literal := cast(*IntegerExpr) expr;
        int_op := alloc_op(scope, LiteralS64Op, literal);
        int_op.value = literal.value;

        ret(op_to_index(scope, int_op));

    case .IDENT;
        ident := cast(*IdentExpr) expr;
        decl := unwrap(search_scope(scope, ident.symbol));
        if decl < 0
            throw(ident, "unrecognized identifier");

        ret(decl);

    case .CALL;
        call := cast(*CallExpr) expr;
        callee_op := unwrap(check_expr(call.callee, scope));

        callee_type := index_to_op(scope, callee_op).expr_type;
        callee_info := Types[callee_type];
        if callee_info.kind != .PROC
            throw(call.callee, "you're calling something that's not a procedure");

        proc_info := cast(*LiuTypeInfoProcedure) callee_info;
        if proc_info.params.count != call.params.count // @Todo this doesn't handle optional arguments
            throw(call, "wrong number of arguments for this procedure call");

        params : [..] s32;
        array_reserve(*params, proc_info.params.count);
        defer array_free(params);

        for index: 0..(proc_info.params.count - 1) {
            expected_param_type := proc_info.params[index];
            param := call.params[index];
            param_op := unwrap(check_expr(param, scope));

            param_type := index_to_op(scope, param_op).expr_type;
            type_result := check_type_transition(param, expected_param_type, param_type);
            inferred_type := unwrap(type_result);
            assert(inferred_type == expected_param_type);
        }

        params_array := tir_array(scope, proc_info.params.count, *~s32 Opcode);
        for params
            params_array[it_index] = index_to_op(scope, it);

        // @Todo
        // call_op := alloc_op(scope, CallOp, call);
        // call_op.proc_ptr = index_to_op(scope, callee_op);
        // call_op.params = params_array;

        // ret(op_to_index(scope, call_op));
        ret();

    case .RETURN;
        return_type_ptr := scope_return_type(scope);
        if return_type_ptr == null
            throw(expr, "can't return in this context");

        return_expr := cast(*ReturnExpr) expr;
        value := return_expr.value;
        value_op := unwrap(check_expr(value, scope));
        value_type := index_to_op(scope, value_op).expr_type;

        return_type := << return_type_ptr;
        type_result := check_type_transition(value, return_type, value_type);
        inferred_type := unwrap(type_result);
        assert(inferred_type == return_type);

        // @Todo
        ret();

    case .REF;
        ref_expr := cast(*UnaryExpr) expr;
        referenced_idx := unwrap(check_expr(ref_expr.base, scope, referenced = true));
        referenced_op := index_to_op(scope, referenced_idx);
        referenced_type := referenced_op.expr_type;

        if referenced_op.kind == .CONST && referenced_type == TYPE_TYPE {
            const_op := cast(*ConstOp) referenced_op;
            expr_type := Types.pointer(const_op.value.as_type);
            const_op.value.as_type = expr_type;
            ret(referenced_idx);
        }

        expr_type := Types.pointer(referenced_type);
        ret();

    case .DEREF;
        deref_expr := cast(*UnaryExpr) expr;
        // unwrap(check_expr(deref_expr.base, scope));
        // pointer_type := unwrap(type_of_expr(deref_expr.base));
        // ty_info := Types[pointer_type];
        // if ty_info.kind != .POINTER
        //     throw(deref_expr.base, "can't dereference this, it's not a pointer");

        // pointer_ty_info := cast(*LiuTypeInfoPointer) ty_info;
        // base_type := pointer_ty_info.pointing_to;

        ret();

    case .ADD;
        // @Todo this doesn't really scale, nor does it really check whether or
        // not the given type can take this operator. IDK man we'll see i guess.
        plus := cast(*BinaryExpr) expr;
        // unwrap(check_expr(plus.left, scope));
        // unwrap(check_expr(plus.right, scope));
        // left, right := plus.left, plus.right;
        // l_ty, r_ty := unwrap(type_of_expr(left)), unwrap(type_of_expr(right));
        // expr_type := unwrap(check_type_transition(left, expected_type, l_ty));
        // expr_type = unwrap(check_type_transition(left, expr_type, r_ty));

        ret();

    case .PROCEDURE;
        proc_expr := cast(*ProcedureExpr) expr;
        unwrap(check_proc(proc_expr, scope));
        ret();

    case .COMPTIME_DECLARATION;
        ret();

    case .DECLARATION;
        decl := cast(*DeclarationExpr) expr;
        unwrap(check_decl(decl, scope));
        ret();

    case .ASSIGNMENT;
        assign_expr := cast(*AssignmentExpr) expr;
        tc_result := check_assignment(assign_expr.target, assign_expr.value, scope);
        unwrap(tc_result);
        ret();
    }


    message := sprint("% expressions are unimplemented", expr.kind);
    throw(expr, message);
    ret(); // for control flow warnings
}

check_assignment :: (target: *Expr, expr: *Expr, scope: *Scope) -> Result(s32) {
    if target.kind == {
    case .IDENT;
        ident := cast(*IdentExpr) target;
        decl_idx := unwrap(search_scope(scope, ident.symbol));
        if decl_idx < 0
            throw(ident, "unrecognized identifier");
        // @Todo we could declare the variable here instead, if we really wanted to

        decl_op := index_to_op(scope, decl_idx);
        if decl_op.kind == .CONST
            throw(ident, "can't assign to this, it was declared as constant");

        unwrap(check_expr(expr, scope, expected_type = decl_op.expr_type));
        // expr_ty := unwrap(type_of_expr(expr));
        // tc_result := check_type_transition(target, decl_type, expr_ty);
        // expr_type := unwrap(tc_result);
        // assert(decl_type == expr_type);
        ret();

    case .DEREF;
        deref_expr := cast(*UnaryExpr) target;

        // unwrap(check_expr(deref_expr.base, scope));
        // pointer_type := unwrap(type_of_expr(deref_expr.base));
        // ty_info := Types[pointer_type];
        // if ty_info.kind != .POINTER
        //     throw(deref_expr.base, "can't dereference this, it's not a pointer");

        // pointer_ty_info := cast(*LiuTypeInfoPointer) ty_info;
        // base_type := pointer_ty_info.pointing_to;

        // opcode := unwrap(check_expr(expr, scope, expected_type = base_type));
        // tc_result := check_type_transition(target, base_type, expr_ty);
        // expr_type := unwrap(tc_result);
        // assert(base_type == expr_type);

        ret();
    }
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

search_scope :: (_scope: *Scope, ident: s32) -> Result(s32) {
    decl, success := table_find(builtin_scope.runtime_variables, ident);
    assert(!success); // @Todo should there be something here? Maybe the context?

    copy_const_decl :: (tir: *TirProc, decl: *DeclarationExpr, decl_op: *ConstDeclOp) -> Result(s32) {
        const_op := alloc_op(tir, ConstOp, decl);
        const_op.value = decl_op.value;
        const_op.expr_type = decl_op.expr_type;
        return ok(op_to_index(tir, const_op));
    }

    scope := _scope;
    tir_proc := Scope.codegen(scope).tir_proc;
    comptime_decl : Scope.ConstDecl;
    comptime_decl, success = table_find(builtin_scope.comptime_variables, ident);
    if success {
        assert(comptime_decl.value != null);
        return copy_const_decl(tir_proc, comptime_decl.decl, comptime_decl.value);
    }

    only_comptime := false;
    while scope {
        if !only_comptime {
            decl, success := table_find(scope.runtime_variables, ident);
            if success      return ok(decl.decl_op);
        }

        comptime_decl := table_find_pointer(scope.comptime_variables, ident);
        if comptime_decl {
            decl_ast := comptime_decl.decl;
            if comptime_decl.value
                return copy_const_decl(tir_proc, comptime_decl.decl, comptime_decl.value);
            if comptime_decl.checking
                return error(comptime_decl.decl, "circular dependency detected", success_type = s32);

            comptime_decl.checking = true;
            result := check_decl(comptime_decl.decl, scope);
            unwrap(result, success_type = s32);
            assert(comptime_decl.value != null);

            return copy_const_decl(tir_proc, comptime_decl.decl, comptime_decl.value);
        }

        only_comptime = only_comptime || scope.comptime_capture;
        scope = scope.parent;
        tir_proc = Scope.codegen(scope).tir_proc;
    }

    ret();
}

ret :: () #expand {
    `return ok(cast(s32) -1);
}

ret :: (op: s32) #expand {
    `return ok(op);
}

throw :: (value: *$T/interface Span, message: string, loc := #caller_location) #expand {
    `return error(value, message, loc = loc, success_type = s32);
}

unwrap :: (result: Result($T), $success_type := s32) -> T #expand
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

unwrap :: (result: Result(void), $success_type := s32) #expand {
    err := read(result);
    if err      `return error(err, success_type = success_type);
}

#import "Basic";
#import "gone";
#import "parser";
#import "Hash_Table";

// Probably want this opcode stuff to mirror how basic blocks work. Since registers
// only reference registers within the same basic block, we can maybe worry a little
// less about things like branch opcodes.

// should probably include stuff about what file this came from
DeclInfo :: struct {
   ident_nullable : *DeclarationIdent; // if this is null, then its a builtin type
   constant_value_nullable : *Expr; // exists if the declaration was a constant declaration
   type : GoneType;
}

Scope :: struct {
    comptime_variables : Table(s32, DeclInfo);
    runtime_variables : Table(s32, DeclInfo);
    parent: *Scope = null;

    make :: (parent : *Scope = null) -> Scope {
        scope : Scope;

        init(*scope.comptime_variables);
        init(*scope.runtime_variables);

        return scope;
    }
}

check_decl :: (decl_node: *DeclarationExpr, scope: *Scope) -> Result(void) {
    declared_type : GoneType;
    type_decl := decl_node.type_declaration_nullable;
    if type_decl {
        unwrap(check_expr(type_decl, scope));
        declared_type = unwrap(as_type_expr(type_decl));
    }

    value_type : GoneType;
    if decl_node.value_nullable {
        unwrap(check_expr(decl_node.value_nullable, scope, expected_type = declared_type));
        value_type = type_of_expr(decl_node.value_nullable);
    }

    if decl_node.ident_symbols.count == 1 {
        // @Todo add to the current scope my guy
        ret(decl_node, VOID_TYPE);
    }

    assert(false);

    // for decl_node.ident_symbols {
    // }

    ret(decl_node, VOID_TYPE);
}

type_of_expr :: (expr: *Expr) -> GoneType {
    if expr.type_flags & .TYPE_SLOT_IS_VALUE
        return TYPE_TYPE;

    return success(expr.type_slot);
}

check_file :: (file: *FileExpr) -> Result(void) {
    if type_of_expr(file) != UNSPECIFIED_TYPE
        ret();

    assert(context.current_tree == null, "a file should not be inside another file");
    context.current_tree = file;
    defer context.current_tree = null;

    global_scope := Scope.make();
    unwrap(check_statements(file.statements, *global_scope));
    set_type(file, VOID_TYPE);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
    if type_of_expr(block) != UNSPECIFIED_TYPE
        ret();

    scope := Scope.make();
    unwrap(check_statements(block.statements, *scope));

    set_type(block, VOID_TYPE);
    ret();
}

check_statements :: (stmts: [] *Expr, scope: *Scope) -> Result(void) {
    for stmt: stmts {
        unwrap(check_expr(stmt, scope));
    }

    ret();
}

check_expr :: (expr: *Expr, scope: *Scope, expected_type := UNSPECIFIED_TYPE) -> Result(void) {
    if type_of_expr(expr) != UNSPECIFIED_TYPE
        ret();

    if expr.kind == {
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
        success, decl_info := search_scope(scope, ident.ident_symbol);
        if !success
            throw(ident, "unrecognized identifier");

        value := decl_info.constant_value_nullable;
        if decl_info.type == TYPE_TYPE && value {
            type_value := unwrap(as_type_expr(value));
            ret_type(ident, type_value);
        }

        ret(ident, decl_info.type);

    case .CALL;
        // @Todo lmao this is totally wrong
        call := cast(*CallExpr) expr;
        ret(call, VOID_TYPE);

    case .PLUS;
        // @Todo lmao this is totally wrong
        plus := cast(*BinaryExpr) expr;
        left_ty := unwrap(check_expr(plus.left, scope));
        right_ty := unwrap(check_expr(plus.right, scope));
        if left_ty != right_ty {
            throw(plus, "added two values that aren't the same type");
        }

        ret(plus, S64_TYPE);

    case .DECLARATION;
        // @Todo the entire thing lmao
        decl := cast(*DeclarationExpr) expr;
        unwrap(check_decl(decl, scope));
        ret();
    }

    assert(false, "% expressions are unimplemented", expr.kind);
    ret(expr, UNSPECIFIED_TYPE); // for control flow warnings
}

as_type_expr :: (expr: *Expr) -> Result(GoneType) {
    assert((expr.type_flags & .IS_TYPED) != 0);

    if expr.type_flags & .TYPE_SLOT_IS_VALUE
        return success(expr.type_slot);

    return error(expr, "the value here needs to be a type", success_type = GoneType);
}

typechecker_init :: () {
    builtin_scope = Scope.make();
    info : DeclInfo;
    expr : *Expr;

    info.ident_nullable = null;
    expr = New(Expr); // leak-gang
    expr.kind = .EMPTY_PAREN;
    expr.begin = -1;
    expr.end = -1;
    expr.type_slot = S64_TYPE;
    expr.type_flags = .IS_TYPED;
    expr.type_flags |= .TYPE_SLOT_IS_VALUE;
    info.constant_value_nullable = expr;
    info.type = TYPE_TYPE;

    table_add(*builtin_scope.comptime_variables, S64_SYMBOL, info);
}

#scope_file

builtin_scope : Scope = ---;

search_scope :: (scope: *Scope, ident: s32, search_builtin := true) -> bool, DeclInfo {
    if search_builtin {
        decl_info, success := table_find(builtin_scope.runtime_variables, ident);
        if success
            return true, decl_info;

        decl_info, success = table_find(builtin_scope.comptime_variables, ident);
        if success
            return true, decl_info;
    }

    decl_info, success := table_find(scope.runtime_variables, ident);
    if success
        return true, decl_info;

    decl_info, success = table_find(scope.comptime_variables, ident);
    if success
        return true, decl_info;

    if scope.parent {
        success, decl_info = search_scope(scope.parent, ident, search_builtin = false);
        return success, decl_info;
    }

    return false, decl_info;
}

success :: () -> Result(void) {
    result : Result(void);
    result.did_succeed = true;
    result.begin = -1;
    result.end = -1;

    return result;
}

success :: (value: $T) -> Result(T) {
    result : Result(T);
    result.did_succeed = true;
    result.value = value;
    result.begin = -1;
    result.end = -1;

    return result;
}

error :: (value: *$T/interface Spanned, message: string, loc := #caller_location, $success_type := void) -> Result(success_type) {
    result : Result(success_type);
    result.begin = value.begin;
    result.end = value.end;
    result.did_succeed = false;
    result.error = message;
    #if GONE_DEBUG && #run has_member(T, "stack_trace", [] Stack_Trace_Node) {
        result.stack_trace = value.stack_trace;
    } else #if GONE_DEBUG {
        result.stack_trace = pack_stack_trace();
        result.stack_trace[0] = result.stack_trace[1];
        result.stack_trace[0].line_number = cast(u32) loc.line_number;
    }

    return result;
}

ret :: () #expand {
    `return success();
}

ret :: (expr: *Expr, type: GoneType) #expand {
    set_type(expr, type);

    `return success();
}

ret_type :: (expr: *Expr, type: GoneType) #expand {
    set_type_as_value(expr, type);

    `return success();
}

throw :: (value: *$T/interface Spanned, message: string, loc := #caller_location) #expand {
    `return error(value, message, loc = loc);
}

unwrap :: (result: Result(GoneType)) -> GoneType #expand {
    if !result.did_succeed {
        res := result;
        `return error(*res, result.error);
    }

    return result.value;
}

unwrap :: (result: Result(void)) #expand {
    if !result.did_succeed {
        res := result;
        `return error(*res, result.error);
    }
}

set_type :: inline (value : *Expr, ty: GoneType) {
    assert(type_of_expr(value) == UNSPECIFIED_TYPE);
    assert(ty != UNSPECIFIED_TYPE);

    value.type_slot.type_id = ty.type_id;
    value.type_slot.pointer_count = ty.pointer_count;
    value.type_flags = value.type_flags | .IS_TYPED;
}

set_type_as_value :: inline (value : *Expr, ty: GoneType) {
    assert(type_of_expr(value) == UNSPECIFIED_TYPE);
    assert(ty != UNSPECIFIED_TYPE, "set null as type value %", ty);

    value.type_slot.type_id = ty.type_id;
    value.type_slot.pointer_count = ty.pointer_count;
    value.type_flags = value.type_flags | .IS_TYPED | .TYPE_SLOT_IS_VALUE;
}

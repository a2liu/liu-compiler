#import "Basic";
#import "gone";
#import "parser";
#import "hashmap";

// Probably want this opcode stuff to mirror how basic blocks work. Since registers
// only reference registers within the same basic block, we can maybe worry a little
// less about things like branch opcodes.

Scope :: struct {
    DeclInfo :: struct {
        decl : *DeclarationExpr;
        index : s32;
    }

    comptime_variables : Map(s32, DeclInfo);
    runtime_variables : Map(s32, DeclInfo);
}


check_file :: (file: *FileExpr) -> Result(void) {
    if file.type != UNSPECIFIED_TYPE
        ret();

    assert(context.current_tree_buckets == null, "a file should not be inside another file");
    context.current_tree_buckets = *file.buckets;
    defer context.current_tree_buckets = null;

    global_scope : Scope;
    unwrap(check_statements(file.statements, *global_scope), return_type = void);
    set_type(file, VOID_TYPE);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
    if block.type != UNSPECIFIED_TYPE
        ret();

    scope : Scope;
    unwrap(check_statements(block.statements, *scope), return_type = void);

    set_type(block, VOID_TYPE);
    ret();
}

check_statements :: (stmts: [] *Expr, scope: *Scope) -> Result(void) {
    for stmt: stmts {
        unwrap(check_expr(stmt, scope), return_type = void);
    }

    ret();
}

check_expr :: (expr: *Expr, scope: *Scope, expected_type := UNSPECIFIED_TYPE) -> Result(GoneType) {
    if expr.type != UNSPECIFIED_TYPE
        ret(expr);

    if expr.kind == {
    case .FILE;
        assert(false, "files within other expressions doesn't make any sense.");

    case .BLOCK;
        block := cast(*BlockExpr) expr;
        unwrap(check_block(block, scope));
        ret(block);

    case .INTEGER;
        literal := cast(*IntegerExpr) expr;
        ret(literal, S64_TYPE);

    case .IDENT;
        // @Todo lmao this is totally wrong
        ident := cast(*IdentExpr) expr;
        ret(ident, S64_TYPE);

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

        declared_type : GoneType;
        if decl.type_declaration_nullable {
            declared_type = check_expr(decl.type_declaration_nullable, scope);
        }

        value_type : GoneType;
        if decl.value_nullable {
            value_type = check_expr(decl.value_nullable, scope, expected_type = declared_type);
        }

        ret(decl, VOID_TYPE);
    }

    assert(false, "% expressions are unimplemented", expr.kind);
    ret(expr, UNSPECIFIED_TYPE); // for control flow warnings
}

get_type_value :: (expr: *Expr) -> GoneType {
    return VOID_TYPE;
}

#scope_file

ret :: () #expand {
    result : Result(void);
    result.did_succeed = true;
    result.begin = -1;
    result.end = -1;

    `return result;
}

ret :: (expr: *Expr) #expand {
    assert(expr.type != UNSPECIFIED_TYPE);

    result : Result(GoneType);
    result.did_succeed = true;
    result.value = expr.type;
    result.begin = -1;
    result.end = -1;

    `return result;
}

ret :: (expr: *Expr, type: GoneType) #expand {
    result : Result(GoneType);
    result.did_succeed = true;
    result.value = type;
    result.begin = -1;
    result.end = -1;
    set_type(expr, type);

    `return result;
}

throw :: (value: *$T/interface Spanned, message: string, loc := #caller_location, $return_type := GoneType) #expand {
    result : Result(return_type);
    result.begin = value.begin;
    result.end = value.end;
    result.did_succeed = false;
    result.error = message;
    #if GONE_DEBUG {
        result.stack_trace = pack_stack_trace();
        result.stack_trace[0].line_number = cast(u32) loc.line_number;
    }

    `return result;
}

unwrap :: (result: Result(GoneType), $return_type := GoneType) -> GoneType #expand {
    if !result.did_succeed {
        outer_result : Result(return_type);
        outer_result.did_succeed = false;
        outer_result.begin = result.begin;
        outer_result.end = result.end;
        outer_result.error = result.error;
        #if GONE_DEBUG      outer_result.stack_trace = result.stack_trace;
        `return outer_result;
    }

    return result.value;
}

unwrap :: (result: Result(void), $return_type := GoneType) #expand {
    if !result.did_succeed {
        outer_result : Result(return_type);
        outer_result.did_succeed = false;
        outer_result.begin = result.begin;
        outer_result.end = result.end;
        outer_result.error = result.error;
        #if GONE_DEBUG      outer_result.stack_trace = result.stack_trace;
        `return outer_result;
    }
}

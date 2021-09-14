#import "Basic";
#import "gone";
#import "parser";
#import "hashmap";

// Probably want this opcode stuff to mirror how basic blocks work. Since registers
// only reference registers within the same basic block, we can maybe worry a little
// less about things like branch opcodes.

Scope :: struct {
    comptime_values : Map(s32, *Expr);
    runtime_values : Map(s32, *Expr);
}

check_module :: (module: *ModuleExpr) -> Result(void) {
    assert(module.type == UNSPECIFIED_TYPE);

    global_scope : Scope;
    unwrap(check_statements(module.statements, *global_scope), return_type = void);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
    if block.type != UNSPECIFIED_TYPE {
        ret();
    }

    scope : Scope;
    unwrap(check_statements(block.statements, *scope), return_type = void);
    ret();
}

check_statements :: (stmts: [] *Expr, scope: *Scope) -> Result(void) {
    for stmt: stmts {
        unwrap(check_expr(stmt, scope), return_type = void);
    }

    ret();
}

check_expr :: (expr: *Expr, scope: *Scope, expected_type := UNSPECIFIED_TYPE) -> Result(GoneType) {
    print("Hullo\n");

    if expr.kind == {
    case .MODULE;
        // @Todo eventually we should support this. Not now, but eventually.
        assert(false, "modules within other expressions is currently unsupported.");

    case .BLOCK;
        block := cast(*BlockExpr) expr;
        unwrap(check_block(block, scope));
        ret(VOID_TYPE);

    case .N64;
        literal := cast(*N64Expr) expr;

        if cased(expected_type) == {
        case CASED_UNSPECIFIED_TYPE;
        }
        ret(N64_TYPE);

    case .PLUS;

    case .DECLARATION;
        decl := cast(*DeclarationExpr) expr;

        declared_type : GoneType;
        if decl.type_declaration_nullable {
            declared_type := check_expr(decl.type_declaration_nullable, scope);
        }

        value_type : GoneType;
        if decl.value_nullable {
            value_type = check_expr(decl.value_nullable, scope, expected_type = declared_type);
        }

    }

    ret(VOID_TYPE);
}

#scope_file

ret :: () #expand {
    result : Result(void);
    result.did_succeed = true;
    result.begin = -1;
    result.end = -1;

    `return result;
}

ret :: (type: GoneType) #expand {
    result : Result(GoneType);
    result.did_succeed = true;
    result.begin = -1;
    result.end = -1;

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

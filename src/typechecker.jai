#import "Basic";
#import "gone";
#import "parser";
#import "hashmap";

// Probably want this opcode stuff to mirror how basic blocks work. Since registers
// only reference registers within the same basic block, we can maybe worry a little
// less about things like branch opcodes.

VOID_TYPE_ID : s32 : 0;
S64_TYPE_ID : s32 : 1;

VOID_TYPE :: GoneType.{ type_id = VOID_TYPE_ID, pointer_count = 0 };

Scope :: struct {
    comptime_values : Map(s32, *Expr);
    runtime_values : Map(s32, *Expr);
}

check_module :: (module: *ModuleExpr) -> Result(void) {
    global_scope : Scope;
    unwrap(check_statements(module.statements, *global_scope), return_type = void);
    ret();
}

check_block :: (block: *BlockExpr, parent_scope: *Scope) -> Result(void) {
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

check_expr :: (expr: *Expr, scope: *Scope) -> Result(GoneType) {
    if expr.kind == {
    case .MODULE;
        // @Todo eventually we should support this. Not now, but eventually.
        assert(false, "modules within other expressions is currently unsupported.");

    case .BLOCK;
        block := cast(*BlockExpr) expr;
        unwrap(check_block(block, scope));
        ret(VOID_TYPE);

    case .PLUS;

    case .DECLARATION;

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

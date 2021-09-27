#import "Basic";
#import "Hash_Table";
#import "liu";
#import "ast";

// @Todo replace BasicBlock with actual module object or whatever when it comes time
bytecode_file :: (file: *FileExpr) -> BasicBlock {
    bb := BasicBlock.make();

    bytecode_scope(*bb, file.statements);

    return bb;
}

bytecode_block :: (bb: *BasicBlock, block: *BlockExpr) {
    bytecode_scope(bb, block.statements);
}

bytecode_scope :: (bb: *BasicBlock, stmts: [] *Expr) {
    for stmts {
        bytecode_expr(bb, it);
    }
}

bytecode_proc :: (proc_expr: *ProcedureExpr) {
    proc_expr.bytecode = BasicBlock.make();
}

bytecode_expr :: (bb: *BasicBlock, expr: *Expr) -> s32 {
    if expr.kind == {
    case .UNINITIALIZED;
        assert(false);

    case .FILE;
        assert(false, "files within other expressions doesn't make any sense.");

    case .IDENT;
        ident := cast(*IdentExpr) expr;
        if is_const(ident) {
            err, expr_type := read(type_of_expr(ident));
            assert(err == null);
            if expr_type == S64_TYPE {
                op := alloc_op(bb, LiteralS64Op, ident);
                op.value = ident.const_value.as_s64;
                ret(bb, op);
            } else if Types[expr_type].kind == .PROC {
                op := alloc_op(bb, ProcPtrOp, ident);
                proc_ptr := ident.const_value.as_proc_ptr;
                bytecode_proc(proc_ptr);
                op.value = *proc_ptr.bytecode;
                ret(bb, op);
            }
            assert(expr_type == S64_TYPE);
        }

        return ident.declaration.bytecode_register;

    case .INTEGER;
        integer := cast(*IntegerExpr) expr;
        err, expr_type := read(type_of_expr(integer));
        assert(err == null);
        assert(expr_type == S64_TYPE);
        op := alloc_op(bb, LiteralS64Op, integer);
        op.value = integer.const_value.as_s64;
        ret(bb, op);

    case .BLOCK;
        block := cast(*BlockExpr) expr;
        bytecode_block(bb, block);

    case .RETURN;
        return_expr := cast(*ReturnExpr) expr;
        register := bytecode_expr(bb, return_expr.value);
        op := alloc_op(bb, RetOp, return_expr, new_register = false);
        op.register = register;
        ret();

    case .COMPTIME_DECLARATION;
        // @Todo What do we do here?
        decl := cast(*DeclarationExpr) expr;
        ret();

    case .DECLARATION;
        decl := cast(*DeclarationExpr) expr;
        assert(decl.value_nullable != null);
        assert(decl.idents.count == 1);
        decl.idents[0].bytecode_register = bytecode_expr(bb, decl.value_nullable);

    case .ADD;
        add := cast(*BinaryExpr) expr;
        left := bytecode_expr(bb, add.left);
        right := bytecode_expr(bb, add.right);
        op := alloc_op(bb, BinaryOp, add);
        op.kind = .ADD;
        op.left = index_to_op(bb, left);
        op.right = index_to_op(bb, right);
        ret(bb, op);

    case;
        assert(false, "% expressions are unimplemented", expr.kind);
    }

    ret();
}

StackFrame :: struct {
    register_offset: s64;
    current_proc: *BasicBlock;
    opcode: *Opcode;
}

Interpreter :: struct {

    registers : [..] s64; // @Todo change s64 to u64 when we start supporting more types
    stack : [..] StackFrame;

    make :: () -> Interpreter {
        interp : Interpreter;
        array_reserve(*interp.registers, 200);
        array_reserve(*interp.stack, 20);

        return interp;
    }
}

interp_file :: (interp: *Interpreter, bb: *BasicBlock) -> s64 {
    frame : StackFrame;
    frame.register_offset = 0;
    frame.current_proc = bb;

    for op: bb {
        frame.opcode = op;

        if op.kind == {
        case .UNINITIALIZED;
            assert(false);

        case .ADD;
            add := cast(*BinaryOp) op;
            left := get(interp, *frame, add.left.register, s64);
            right := get(interp, *frame, add.right.register, s64);
            set(interp, *frame, add.register, left + right);

        case .LITERAL_S64;
            literal := cast(*LiteralS64Op) op;
            set(interp, *frame, literal.register, literal.value);
        }
    }

    if interp.registers.count == 0
        return 0;

    return interp.registers[interp.registers.count - 1];
}

get :: (interp: *Interpreter, frame: *StackFrame, register: s64, $T: Type) -> T {
    physical_id := frame.register_offset + register;
    return cast(T) interp.registers[physical_id];
}

set :: (interp: *Interpreter, frame: *StackFrame, register: s64, value: s64) {
    physical_id := frame.register_offset + register;
    array_reserve(*interp.registers, physical_id + 1); // this reserves enough space for register to be a valid index
    interp.registers.count = physical_id + 1;
    assert(interp.registers.count <= interp.registers.allocated);
    interp.registers[physical_id] = value;
}

#scope_file

ret :: () #expand {
    `return -1;
}

ret :: (bb: *BasicBlock, op: *Opcode) #expand {
    `return op_to_index(bb, op);
}

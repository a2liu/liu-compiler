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
    if is_valid(*proc_expr.bytecode)
        return;

    proc_expr.bytecode = BasicBlock.make();
    bb := *proc_expr.bytecode;
    count : s32 = 0;
    for decl: proc_expr.params {
        for ident: decl.idents {
            ident.bytecode_register = count;
            count += 1;
        }
    }

    // @Todo context and object pointer or whatever
    proc_expr.bytecode.next_register = cast(s32) count;
    bytecode_expr(bb, proc_expr.body);
    alloc_op(bb, RetOp, proc_expr.body, new_register = false);
}

// @Todo what should bytecode generate for void stuffs? Like do we just pass a dummy register?
bytecode_expr :: (bb: *BasicBlock, expr: *Expr) -> s32 {
    if expr.kind == {
    case .UNINITIALIZED;
        assert(false);

    case .FILE;
        assert(false, "files within other expressions doesn't make any sense.");

    case .IDENT;
        ident := cast(*IdentExpr) expr;
        if !is_const(ident)
            return ident.declaration.bytecode_register;

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
        } else {
            assert(false, "unhandled const value");
        }

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
        ret();

    case .RETURN;
        return_expr := cast(*ReturnExpr) expr;
        register := bytecode_expr(bb, return_expr.value);
        if register == -1 {
            op := alloc_op(bb, RetOp, return_expr, new_register = false);
            ret();
        } else {
            op := alloc_op(bb, RetValOp, return_expr, new_register = false);
            op.register = register;
            ret();
        }

    case .CALL;
        call := cast(*CallExpr) expr;
        proc_register := bytecode_expr(bb, call.callee);
        param_registers : [..] s32;
        array_reserve(*param_registers, call.params.count);

        for call.params {
            register := bytecode_expr(bb, it);
            assert(register >= 0, "register was %: failed for %", register, it.kind);
            array_add(*param_registers, register);
        }

        op := alloc_op(bb, CallOp, call);
        op.proc_ptr = proc_register;
        op.params = param_registers;

        ret(bb, op);

    case .COMPTIME_DECLARATION;
        // @Todo What do we do here?
        decl := cast(*DeclarationExpr) expr;
        ret();

    case .DECLARATION;
        decl := cast(*DeclarationExpr) expr;
        assert(decl.value_nullable != null);
        assert(decl.idents.count == 1);
        decl.idents[0].bytecode_register = bytecode_expr(bb, decl.value_nullable);
        ret();

    case .ADD;
        add := cast(*BinaryExpr) expr;
        left := bytecode_expr(bb, add.left);
        right := bytecode_expr(bb, add.right);
        op := alloc_op(bb, BinaryOp, add);
        op.kind = .ADD;
        op.left = left;
        op.right = right;
        ret(bb, op);

    case;
        assert(false, "% expressions are unimplemented", expr.kind);
    }

    assert(false, "case fell through");
    ret();
}

StackFrame :: struct {
    register_offset: s64;
    current_proc: *BasicBlock;
    pc: *Opcode;
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
    using frame : StackFrame;
    register_offset = 0;
    current_proc = bb;
    pc = index_to_op(bb, bb.first); // jump to function block

    while pc {
        if pc.kind == {
        case .UNINITIALIZED;
            assert(false);

        case .ADD;
            add := cast(*BinaryOp) pc;
            left := get(interp, *frame, add.left, s64);
            right := get(interp, *frame, add.right, s64);
            set(interp, *frame, add.register, left + right);

        case .LITERAL_S64;
            literal := cast(*LiteralS64Op) pc;
            set(interp, *frame, literal.register, literal.value);

        case .PROC_PTR;
            proc_ptr := cast(*ProcPtrOp) pc;
            set(interp, *frame, proc_ptr.register, proc_ptr.value);

        case .CALL;
            call := cast(*CallOp) pc;
            callee := get(interp, *frame, call.proc_ptr, *BasicBlock);
            frame_begin := push_args(interp, *frame, call.params);
            array_add(*interp.stack, frame);
            register_offset = frame_begin;
            current_proc = callee;
            pc = index_to_op(callee, callee.first); // jump to function block
            continue;

        case .RET_VAL;
            ret_val := cast(*RetValOp) pc;
            value := get(interp, *frame, ret_val.register, s64);
            interp.registers.count = frame.register_offset;
            frame = pop(*interp.stack);
            assert(pc.kind == .CALL);
            set(interp, *frame, pc.register, value);

        case;
            assert(false, "INTERP: % ops are unimplemented", pc.kind);
        }

        pc = pc.next;
    }

    if interp.registers.count == 0
        return 0;

    return interp.registers[interp.registers.count - 1];
}

get :: (interp: *Interpreter, frame: *StackFrame, register: s32, $T: Type) -> T {
    physical_id := frame.register_offset + register;
    return cast(T) interp.registers[physical_id];
}

push_args :: (interp: *Interpreter, frame: *StackFrame, param_registers: [] s32) -> s32 {
    frame_begin := cast(s32) interp.registers.count;

    array_reserve(*interp.registers, interp.registers.count + param_registers.count);
    for register: param_registers {
        value := get(interp, frame, register, s64);
        array_add(*interp.registers, value);
    }

    return frame_begin;
}

set :: (interp: *Interpreter, frame: *StackFrame, register: s32, value: *$T) {
    set(interp, frame, register, cast(s64) value);
}

set :: (interp: *Interpreter, frame: *StackFrame, register: s32, value: s64) {
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
    `return op.register;
}

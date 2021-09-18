#import "Basic";
#import "liu";
#import "bytecode";

Interpreter :: struct {
    registers : [..] s64; // @Todo change s64 to u64 when we start supporting more types

    make :: () -> Interpreter {
        interp : Interpreter;
        array_reserve(*interp.registers, 20);
        return interp;
    }
}

interp_file :: (interp: *Interpreter, bb: *BasicBlock) -> s64 {
    for op: bb {
        if op.kind == {
        case .ADD;
            add := cast(*BinaryOp) op;
            left := interp.registers[add.left.register];
            right := interp.registers[add.right.register];
            set_register(interp, add.register, left + right);

        case .LITERAL_S64;
            literal := cast(*LiteralS64Op) op;
            set_register(interp, literal.register, literal.value);

        }
        print("%\n", op);
    }

    if interp.registers.count == 0
        return 0;

    return interp.registers[interp.registers.count - 1];
}

set_register :: (interp: *Interpreter, register: s64, value: s64) {
    array_reserve(*interp.registers, register + 1); // this reserves enough space for register to be a valid index
    interp.registers.count = register + 1;
    assert(interp.registers.count <= interp.registers.allocated);
    interp.registers[register] = value;
}


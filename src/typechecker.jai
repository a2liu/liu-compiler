#import "Basic";
Gone :: #import "gone";
#import "parser";

// Probably want this opcode stuff to mirror how basic blocks work. Since registers
// only reference registers within the same basic block, we can maybe worry a little
// less about things like branch opcodes.

TCResult :: struct {
    using _base : Gone.Result(*Opcode, string, insert_fields = false);
}

using enum s32 {
    S64 :: 1;
};

Type :: struct {
    pointer_count: s32;
    type_id: s32;
}

Variable :: struct {
    Flags :: enum_flags u8 {
        GOT_ADDRESS_OF;
        REFERENCED_IN_CLOSURE;
        MUTATED;
    }

    flags : Flags = 0;
    variable_stack_offset : u32;
    variable_type : Type;
}

Opcode :: struct {
    Kind :: enum u16 {
        UNINITIALIZED :: 0;

        WRITE_VARIABLE;

        SCRATCH_NOP;

        ADD_S64;

        LITERAL_S64;
    }

    kind : Kind = .UNINITIALIZED;
    span_length : u16;
    span_begin : s32;

    // Opcodes might not be tightly packed.
    // This field contains the actual size of this opcode in memory.
    scratch_size : s32;
}

LiteralS64Op :: struct {
    using _base : Opcode;
    _base.kind = .LITERAL_S64;
    register_id : s32;
    value : s64;
}

WriteVariableOp :: struct {
    using _base : Opcode;
    _base.kind = .WRITE_VARIABLE;
    variable_id : s32;
    value : *~s32 Opcode;
}

BinaryOp :: struct {
    using _base : Opcode;
    left: *~s32 Opcode;
    right: *~s32 Opcode;
}

// This doesn't actually define a new register, so register_id is used
CallArg :: struct {
    using _base : Opcode;
    register_definition : *~s32 Opcode;
}

FunctionBlocks :: struct {
    blocks: [..] [..] u8;
}

TypeChecker :: struct {
}

Scope :: struct {
}


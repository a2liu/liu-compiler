#import "Basic";
#import "gone";
#import "parser";

// Probably want this opcode stuff to mirror how basic blocks work. Since registers
// only reference registers within the same basic block, we can maybe worry a little
// less about things like branch opcodes.

TCResult :: struct {
    using _base : Result(*Opcode, string, insert_fields = false);
}

using enum s32 {
    S64 :: 1;
};

Variable :: struct {
    Flags :: enum_flags u8 {
        GOT_ADDRESS_OF;
        REFERENCED_IN_CLOSURE;
        MUTATED;
    }

    flags : Flags = 0;
    variable_stack_offset : u32;
    variable_type : GoneType;
}

Opcode :: struct {
    Kind :: enum u16 {
        UNINITIALIZED :: 0;

        WRITE_VARIABLE;

        SCRATCH_NOP;

        ADD;

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

BasicBlock :: struct {
    data : [..] u8;

    make :: () -> BasicBlock {
        block : BasicBlock;
        array_reserve(*block.data, size_of(Opcode) * 100);
        return block;
    }
}

alloc_op :: (block: *BasicBlock, $T: Type) -> *T {
    #assert(inherits_from(T, Opcode));

    type_size := size_of(T);
    array_reserve(*block.data, type_size);
    memory_index := block.data.count;
    block.data.count += type_size;
    assert(block.data.count <= block.data.allocated);
    memory : *void = *block.data[memory_index];

    ini :: initializer_of(T);

    #if ini {
        inline ini(memory);
    } else {
        memset(memory, 0, size_of(T));
    }

    return cast(*T) memory;
}

TypeChecker :: struct {
    ops : BasicBlock;

    make :: () -> TypeChecker {
        checker : TypeChecker;
        checker.ops = BasicBlock.make();

        return checker;
    }
}

Scope :: struct {
}

typecheck_module :: (module: *Module) {
    checker := TypeChecker.make();
}


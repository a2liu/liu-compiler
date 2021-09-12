#import "Basic";
#import "gone";
#import "parser";

// Probably want this opcode stuff to mirror how basic blocks work. Since registers
// only reference registers within the same basic block, we can maybe worry a little
// less about things like branch opcodes.

S64 : s32 : 1;

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

TypeChecker :: struct {

    make :: () -> TypeChecker {
        checker : TypeChecker;

        return checker;
    }
}

Scope :: struct {
}

typecheck_module :: (module: *ModuleExpr) {
    checker := TypeChecker.make();
}


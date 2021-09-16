#import "Basic";
#import "parser";
#import "gone";

// Blocks can read registers from their guaranteed predecessors.
// If a block has multiple predecessors, each predecessor that calls into that block
// needs to pass the register values it uses.

Opcode :: struct {
    Kind :: enum u16 {
        UNINITIALIZED :: 0;

        ADD;

        LITERAL_S64;
    }

    kind : Kind = .UNINITIALIZED;
    span_length : u16 = 0;
    span_begin : s32;

    // Opcodes might not be tightly packed.
    // This field contains the actual size of this opcode in memory.
    next : *~s32 Opcode = ---;
    previous : *~s32 Opcode = ---;

    register_id : s32;
}

LiteralS64Op :: struct {
    using _base : Opcode;
    _base.kind = .LITERAL_S64;
    value : s64;
}

BinaryOp :: struct {
    using _base : Opcode;
    left: *~s32 Opcode;
    right: *~s32 Opcode;
}

BasicBlock :: struct {
    bytes : [..] u8;
    first: *Opcode = null;
    last : *Opcode = null;

    make :: () -> BasicBlock {
        bb : BasicBlock;
        array_reserve(*bb.bytes, size_of(Opcode) * 50);
        return bb;
    }
}


for_expansion :: (iter: *BasicBlock, body: Code, flags: For_Flags) #expand {
    if iter.first == null        return;

    next_op :: (pointer: *Opcode) -> *Opcode { return pointer.next; }
    prev_op :: (pointer: *Opcode) -> *Opcode { return pointer.next; }

    next := ifx (flags & .REVERSE) then prev_op else next_op;
    pointer := ifx (flags & .REVERSE) then iter.last else iter.first;

    while pointer {
        `it := pointer;
        `it_index : void;

        #insert body;

        pointer = next(pointer);
    }
}

// @Todo replace BasicBlock with actual thingy when it comes time
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

bytecode_expr :: (bb: *BasicBlock, expr: *Expr) {
    if expr.kind == {
    case .UNINITIALIZED;
        assert(false);

    case .FILE;
        assert(false, "files within other expressions doesn't make any sense.");

    case .BLOCK;
        block := cast(*BlockExpr) expr;
        bytecode_block(bb, block);

    case .ADD;
    }
}

#scope_file

alloc_array :: (bb: *BasicBlock, count: s64, $T: Type) -> [] T {
    alloc_size := size_of(T) * count;
    array_reserve(*bb.bytes, alloc_size);
    memory_index := bb.bytes.count;
    bb.bytes.count += alloc_size;
    assert(bb.bytes.count <= bb.bytes.allocated);

    array : [] T = ---;
    array.data = cast(*T) *bb.bytes[memory_index];
    array.count = count;

    return array;
}

alloc :: (bb: *BasicBlock, $T: Type) -> *T {
    pointer := alloc_array(bb, 1, T).data;

    ini :: initializer_of(T);
    inline ini(pointer);

    return pointer;
}

alloc_op :: (bb: *BasicBlock, $T: Type) -> *T {
    #assert(inherits_from(T, Opcode));

    pointer := alloc(bb, T);

    pointer.next = null;
    if block.last {
        pointer.previous = bb.last;
        bb.last = pointer;
    } else {
        pointer.previous = null;
        bb.first = pointer;
        bb.last = pointer;
    }

    return pointer;
}

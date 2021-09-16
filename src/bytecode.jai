#import "Basic";
#import "parser";
#import "gone";

// Yeah so we're just gonna flagrantly copy LLVM IR for the most part. No SSA or whatever,
// and block parameters instead of phi stuff. Blocks can read registers from their
// guaranteed predecessors. If a block has multiple predecessors, each predecessor
// that calls into that block needs to pass the register values it uses. We probably
// also wanna include some data about higher level constructs in the IR, so we can
// output some reasonably readable C code as a backend.

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
    REVERSE :: (flags & .REVERSE) != 0;
    #if REVERSE {
    pointer := iter.last;
    } else {
    pointer := iter.first;
    }

    `it : *Opcode = ---;
    `it_index : void;

    for <=REVERSE op, _unused: pointer {
        it = op;

        #insert body;
    }

}

for_expansion :: (iter: *Opcode, body: Code, flags: For_Flags) #expand {
    `it := iter;
    `it_index : void;

    while it {
        #insert body;

        #if flags & .REVERSE {
            it = it.previous;
        } else {
            it = it.next;
        }
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

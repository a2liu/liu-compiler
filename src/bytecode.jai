#import "Basic";
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
    next : *~s32 Opcode = null;
    previous : *~s32 Opcode = null;

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
    first: s32 = -1;
    last : s32 = -1;
    next_register : s32 = 0;

    make :: () -> BasicBlock {
        bb : BasicBlock;
        array_reserve(*bb.bytes, size_of(Opcode) * 50);
        return bb;
    }
}

for_expansion :: (iter: *BasicBlock, body: Code, flags: For_Flags) #expand {
    if iter.last == -1      return;

    REVERSE :: (flags & .REVERSE) != 0;
    #if REVERSE {
    index := iter.last;
    } else {
    index := iter.first;
    }

    pointer := index_to_op(iter, index);
    `it : *Opcode = ---;
    `it_index : void;

    for <=REVERSE op, _unused: pointer {
        op_to_index(iter, op);
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

bytecode_expr :: (bb: *BasicBlock, expr: *Expr) -> s32 {
    if expr.kind == {
    case .UNINITIALIZED;
        assert(false);

    case .FILE;
        assert(false, "files within other expressions doesn't make any sense.");

    case .BLOCK;
        block := cast(*BlockExpr) expr;
        bytecode_block(bb, block);

    case .DECLARATION;
        decl := cast(*DeclarationExpr) expr;
        assert(decl.value_nullable != null);
        bytecode_expr(bb, decl.value_nullable);

    case .ADD;
        add := cast(*BinaryExpr) expr;
        left := bytecode_expr(bb, add.left);
        right := bytecode_expr(bb, add.right);
        op := alloc_op(bb, BinaryOp, add);
        op.kind = .ADD;
        op.left = index_to_op(bb, left);
        op.right = index_to_op(bb, right);
        ret(bb, op);

    case .INTEGER;
        integer := cast(*IntegerExpr) expr;
        assert(type_of_expr(integer) == S64_TYPE);
        op := alloc_op(bb, LiteralS64Op, integer);
        op.value = integer.value;
        ret(bb, op);
    }

    ret();
}

alloc_op :: (bb: *BasicBlock, $T: Type, spanned: *$B/interface Spanned) -> *T {
    #assert(inherits_from(T, Opcode));

    output := bb_alloc(bb, T);
    pointer : *Opcode = output;
    relative_to_base := op_to_index(bb, pointer);

    pointer.register_id = bb.next_register;
    bb.next_register += 1;

    pointer.span_begin = spanned.begin;
    pointer.span_length = cast(u16) (spanned.end - spanned.begin);

    pointer.next = null;


    if bb.last >= 0 {
        last := index_to_op(bb, bb.last);
        last.next = pointer;
        pointer.previous = last;
        bb.last = relative_to_base;
    } else {
        assert(relative_to_base == 0);
        pointer.previous = null;
        bb.first = 0;
        bb.last = 0;
    }

    assert(bb.last >= -1); // overflow happened probably
    return output;
}

#scope_file

ret :: () #expand {
    `return -1;
}

ret :: (bb: *BasicBlock, op: *Opcode) #expand {
    `return op_to_index(bb, op);
}

index_to_op :: (bb: *BasicBlock, idx: s32) -> *Opcode {
    assert(idx >= -1);
    if idx == -1 {
        return null;
    }

    return cast(*Opcode) *bb.bytes[idx];
}

op_to_index :: (bb: *BasicBlock, op: *Opcode) -> s32 {
    if op == null {
        return -1;
    }

    index := cast(s32) ((cast(*u8) op) - bb.bytes.data);
    assert(*bb.bytes[index] == cast(*u8) op);
    return index;
}

bb_alloc_array :: (bb: *BasicBlock, count: s64, $T: Type) -> [] T {
    alloc_size := size_of(T) * count;
    array_reserve(*bb.bytes, bb.bytes.count + alloc_size);
    memory_index := bb.bytes.count;
    bb.bytes.count += alloc_size;
    assert(bb.bytes.count <= bb.bytes.allocated);

    array : [] T = ---;
    array.data = cast(*T) *bb.bytes[memory_index];
    array.count = count;

    return array;
}

bb_alloc :: (bb: *BasicBlock, $T: Type) -> *T {
    pointer := bb_alloc_array(bb, 1, T).data;

    ini :: initializer_of(T);
    inline ini(pointer);

    return pointer;
}

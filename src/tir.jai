#import "Basic";
#import "Hash_Table";

#import "buckets";
#import "liu";
#import "ast";

// @Todo maybe everything under 0 should be a type variable
UNINITIALIZED_TYPE : LiuType : 0;
VOID_TYPE : LiuType : 1;
S64_TYPE : LiuType : 2;
TYPE_TYPE : LiuType : 3;

LiuType :: #type,distinct s32;

LiuTypeInfo :: struct {
    Kind :: enum u8 {
        UNINITIALIZED;
        VOID;
        TYPE;
        INTEGER;
        POINTER;
        PROC;
    }

    kind := Kind.UNINITIALIZED;
    defn_file : s32 = -1;
    defn_begin : s32 = -1;
    defn_end : s32 = -1;
}

// @Rename ProcedureLiuTypeInfo?
LiuTypeInfoProcedure :: struct {
    using _base : LiuTypeInfo;
    _base.kind = .PROC;
    return_type : LiuType;
    // @Todo this should probably be DeclarationIdent
    params : [] LiuType;
}

LiuTypeInfoPointer :: struct {
    using _base : LiuTypeInfo;
    _base.kind = .POINTER;
    pointing_to : LiuType;
}

// -----------------------------------------------------------------------------
//
//                                  BYTECODE
//
// -----------------------------------------------------------------------------

// Yeah so we're just gonna flagrantly copy LLVM IR for the most part. No SSA or whatever,
// and block parameters instead of phi stuff. Blocks can read registers from their
// guaranteed predecessors. If a block has multiple predecessors, each predecessor
// that calls into that block needs to pass the register values it uses. We probably
// also wanna include some data about higher level constructs in the IR, so we can
// output some reasonably readable C code as a backend.

Opcode :: struct {
    Kind :: enum u16 {
        UNINITIALIZED :: 0;

        CONST;
        CONST_DECLARE;
        DECLARE;
        CALL;
        RET;
        RET_VAL;
        PROC_PTR;
        ALLOC;

        ADD;

        LITERAL_S64;
    }

    Flags :: enum_flags u8 {
        // REF_ONCE; // This is used at least once, and can't be dead code elminated
        // REF_TWICE; // This is used at least twice, so it can't be compressed
    }

    kind : Kind = .UNINITIALIZED;
    flags : Flags = 0;
    span_length : u16 = 0;
    span_begin : s32;

    next : *~s32 Opcode = null;
    expr_type : LiuType;
}

ConstOp :: struct {
    using __base : Opcode;
    __base.kind = .CONST;
    value : ConstantValue;

    ConstantValue :: union {
        as_s64 : s64 = 0;
        as_type : LiuType = ---;

        // @Note this is a bit weird, but it seems fine. Like if it's constant,
        // You should be able to use it just like a function pointer in C, and
        // its runtime value should be generate-able from the AST.
        as_proc_ptr : *TirProc = ---;
    }
}

// This isn't a real op. Maybe it shouldn't even inherit from opcode, idk
ConstDeclOp :: struct {
    using _base : ConstOp;
    _base.kind = .CONST_DECLARE;
    symbol : s32;
}

// This is a no-op; it saves information about declarations
DeclOp :: struct {
    using _base : Opcode;
    _base.kind = .DECLARE;
    symbol : s32;
    value : *~s32 Opcode;
    // file_id : s32;
    // @Todo need to have info about the TirProc its on so that captures can happen
}

CallOp :: struct {
    using _base : Opcode;
    _base.kind = .CALL;
    proc_ptr : *~s32 Opcode;
    params : [] *~s32 Opcode;
}

ProcPtrOp :: struct {
    using _base : Opcode;
    _base.kind = .PROC_PTR;
    value : *TirProc; // @Todo LMAO we gotta change this later but whatevs
}

LiteralS64Op :: struct {
    using _base : Opcode;
    _base.kind = .LITERAL_S64;
    value : s64;
}

BinaryOp :: struct {
    using _base : Opcode;
    left: s32;
    right: s32;
}

RetOp :: struct {
    using _base : Opcode;
    _base.kind = .RET;
}

AllocOp :: struct {
    using _base : Opcode;
    _base.kind = .ALLOC;

    size : s32;
}

TirProc :: struct {
    bytes : [..] u8;
    first: s32 = -1;
    last : s32 = -1;
    next_register : s32 = 0;

    make :: () -> TirProc {
        bb : TirProc;
        array_reserve(*bb.bytes, size_of(Opcode) * 50);
        return bb;
    }
}

tir_array :: (bb: *Scope, count: s64, $T: Type) -> [] T {
    return tir_array(Scope.codegen(bb), count, T);
}

tir_array :: (bb: *TirProc, count: s64, $T: Type) -> [] T {
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

bb_alloc :: (bb: *TirProc, $T: Type) -> *T {
    pointer := bb_alloc_array(bb, 1, T).data;

    ini :: initializer_of(T);
    inline ini(pointer);

    return pointer;
}

alloc_op :: (bb: *Scope, $T: Type, spanned: *$B/interface Span) -> *T {
    return alloc_op(Scope.codegen(bb).tir_proc, T, spanned);
}

alloc_op :: (bb: *TirProc, $T: Type, spanned: *$B/interface Span) -> *T {
    #assert(inherits_from(T, Opcode));

    output := bb_alloc(bb, T);
    pointer : *Opcode = output; // @Workaround repro/relative_pointers.jai
    relative_to_base := op_to_index(bb, pointer);

    pointer.span_begin = spanned.begin;
    pointer.span_length = cast(u16) (spanned.end - spanned.begin);

    pointer.next = null;

    if bb.last >= 0 {
        last := index_to_op(bb, bb.last);
        last.next = pointer;
        bb.last = relative_to_base;
    } else {
        assert(relative_to_base == 0);
        bb.first = 0;
        bb.last = 0;
    }

    assert(bb.last >= -1); // overflow happened probably
    return output;
}

index_to_op :: (bb: *Scope, idx: s32) -> *Opcode {
    return index_to_op(Scope.codegen(bb).tir_proc, idx);
}

index_to_op :: (bb: *TirProc, idx: s32) -> *Opcode {
    assert(idx >= -1);
    if idx == -1 {
        return null;
    }

    return cast(*Opcode) *bb.bytes[idx];
}

op_to_index :: (bb: *Scope, op: *Opcode) -> s32 {
    return op_to_index(Scope.codegen(bb).tir_proc, op);
}

op_to_index :: (bb: *TirProc, op: *Opcode) -> s32 {
    if op == null {
        return -1;
    }

    index := cast(s32) ((cast(*u8) op) - bb.bytes.data);
    assert(*bb.bytes[index] == cast(*u8) op);
    return index;
}

for_expansion :: (iter: *TirProc, body: Code, flags: For_Flags) #expand {
    #assert(!flags);
    if iter.last == -1      return;

    index := iter.first;

    pointer := index_to_op(iter, index);
    `it : *Opcode = ---;
    `it_index : void;

    for op, _unused: pointer {
        op_to_index(iter, op);
        it = op;

        #insert body;
    }

}

for_expansion :: (iter: *Opcode, body: Code, flags: For_Flags) #expand {
    #assert(!flags);
    `it := iter;
    `it_index : void;

    while it {
        #insert body;

        it = it.next;
    }
}

tir_init :: () {
    // We really need memory debuggers. Use-after-free should be an obvious bug
    // to catch in debug builds, honestly. Like what the fuck. Just uncommit the
    // range and set the reserved block to illegal. Like how can this not be solved.
    // I don't need malloc to be fast in GODDAMN DEBUG BUILDS. FOR FUCKS SAKE
    // OPERATING SYSTEMS HAVE SUPPORTED THIS SINCE THIS FUCKING INCEPTION OF
    // VIRTUAL MEMORY. STOP TELLING ME THESE THINGS ARE UNSAFE AND ACTUALLY DO THE
    // THINGS THAT WOULD MAKE IT SAFE.
    //
    // Apparently this is a thing that ASAN solves, but unfortunately such luxuries
    // are not available in Jai. Alternatively, why can't we just use OS syscalls
    // to do this without a fucking compiler plugin?
    Scope.init(*builtin_scope, null, true);

    _static_buckets = BucketList.make();
    remember_allocators(*_types_array);

    idents : [..] *ConstDeclOp;
    defer array_free(idents);

    remember_allocators(*idents);

    builtin_type_name :: (symbol: s32, ty: LiuType) #expand {
        ident := New(ConstDeclOp);
        ident.symbol = symbol;
        ident.span_begin = -1;
        ident.span_length = 0;
        ident.expr_type = TYPE_TYPE;
        ident.value.as_type = ty;
        array_add(*idents, ident);
    }

    push_allocator(bucket_allocator, *_static_buckets);

    builtin_type_name(S64_SYMBOL, S64_TYPE);
    builtin_type_name(TYPE_SYMBOL, TYPE_TYPE);
    builtin_type_name(VOID_SYMBOL, VOID_TYPE);

    const_decl : Scope.ConstDecl;
    for idents {
        const_decl.value = it;
        table_add(*builtin_scope.comptime_variables, it.symbol, const_decl);
    }

    builtin_type :: (expected_type: LiuType, $T: Type) -> *T {
        actual_type, ptr := type_alloc(T);
        assert(expected_type == actual_type);
        return ptr;
    }

    none_type := builtin_type(VOID_TYPE, LiuTypeInfo);
    none_type.kind = .VOID;

    int_type := builtin_type(S64_TYPE, LiuTypeInfo);
    int_type.kind = .INTEGER;

    type_type := builtin_type(TYPE_TYPE, LiuTypeInfo);
    type_type.kind = .TYPE;
}

Scope :: struct {
    Kind :: enum u8 {
        BASE;
        CODEGEN;
        PROC;
    }

    // @Todo This doesn't update correctly after a decl is checked. It's fine for now
    // because we only support singular declarations, but like, dis ain't good chief.
    ConstDecl :: struct {
        checking : bool = false;
        decl : *DeclarationExpr = null;
        value: *ConstDeclOp = null;
    }

    DeclInfo :: struct {
        // tir: *TirProc; // @Todo will eventually need to track this too
        decl_op: s32;
    }

    kind : Kind = .BASE;
    comptime_variables : Table(s32, ConstDecl);
    runtime_variables : Table(s32, DeclInfo);
    parent: *Scope = null;
    codegen_parent : *CodegenScope = null;
    comptime_capture := false;

    codegen :: (scope: *Scope) -> *CodegenScope {
        assert(scope != null);

        if scope.kind == {
        case .CODEGEN; #through;
        case .PROC;
            return cast(*CodegenScope) scope;

        case;
            return scope.codegen_parent;
        }
    }

    init :: (scope: *Scope, parent : *Scope, comptime : bool) {
        init(*scope.comptime_variables);
        init(*scope.runtime_variables);
        scope.parent = parent;
        scope.comptime_capture = comptime;

        if parent == null       return;
        scope.codegen_parent = Scope.codegen(parent);
    }

    uninit :: (scope: *Scope) {
        uninit(*scope.comptime_variables);
        uninit(*scope.runtime_variables);
    }
}

init_scoped :: (scope: *Scope, parent : *Scope = null, comptime := false) #expand {
    Scope.init(scope, parent, comptime);

    `defer Scope.uninit(scope);
}

CodegenScope :: struct {
    using __base : Scope;
    __base.kind = .CODEGEN;
    tir_proc : *TirProc; // @Todo this guy leaks big time
    deferred_procs : [..] *TirProc;
}

init_scoped :: (scope: *CodegenScope, parent: *Scope, return_type: LiuType) #expand {
    Scope.init(*scope._base, parent, false);
    scope.tir_proc = New(TirProc, initialized = false);
    << scope.tir_proc = TirProc.make();
    remember_allocators(*scope.deferred_procs);

    `defer Scope.uninit(scope);
    `defer array_free(scope.deferred_procs);
}

ProcScope :: struct {
    using _base : CodegenScope;
    _base.kind = .PROC;
    return_type : LiuType;
}

init_scoped :: (scope: *ProcScope, parent: *Scope, return_type: LiuType) #expand {
    Scope.init(*scope._base, parent, false);
    scope.tir_proc = New(TirProc, initialized = false);
    << scope.tir_proc = TirProc.make();
    remember_allocators(*scope.deferred_procs);
    scope.return_type = return_type;

    `defer Scope.uninit(scope);
    `defer array_free(scope.deferred_procs);
}

builtin_scope : Scope;
Types : struct {
    proc :: (params: .. LiuType, return_type : LiuType) -> LiuType {
        push_allocator(bucket_allocator, *_static_buckets);

        proc_type, ty_info := type_alloc(LiuTypeInfoProcedure);
        ty_info.params = array_copy(params);
        ty_info.return_type = return_type;

        return proc_type;
    }

    pointer :: (pointing_to: LiuType) -> LiuType {
        push_allocator(bucket_allocator, *_static_buckets);

        pointer_type, ty_info := type_alloc(LiuTypeInfoPointer);
        ty_info.pointing_to = pointing_to;

        return pointer_type;
    }
};

operator [] :: (db: type_of(Types), ty: LiuType) -> *LiuTypeInfo {
    assert(ty > 0);
    return _types_array[cast(s32)(ty - 1)];
}

const_decl_alloc :: (const_value: *ConstOp, spanned: *$B/interface Span) -> *ConstDeclOp {
    push_allocator(bucket_allocator, *_static_buckets);

    ptr := New(ConstDeclOp);
    ptr.expr_type = const_value.expr_type;
    ptr.value = const_value.value;
    ptr.span_begin = spanned.begin;
    ptr.span_length = cast(u16) (spanned.end - spanned.begin);

    return ptr;
}

#scope_file

// comptime builtins are things like s64
_static_buckets : BucketList = ---;
_types_array : [..] *LiuTypeInfo;

type_alloc :: ($T: Type) -> LiuType, *T {
    push_allocator(bucket_allocator, *_static_buckets);
    #assert(inherits_from(T, LiuTypeInfo));
    ptr := New(T);
    array_add(*_types_array, ptr);

    liu_type := cast(LiuType) _types_array.count;

    return liu_type, ptr;
}

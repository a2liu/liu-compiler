#import "Basic";
#import "Hash_Table";

#import "buckets";
#import "liu";

// @Todo maybe everything under 0 should be a type variable
UNSPECIFIED_TYPE :: LiuType.{ type_id = 0 };
VOID_TYPE :: LiuType.{ type_id = 1 };
S64_TYPE :: LiuType.{ type_id = 2 };
TYPE_TYPE :: LiuType.{ type_id = 3 };

CASED_UNSPECIFIED_TYPE :: #run cased(UNSPECIFIED_TYPE);
CASED_VOID_TYPE :: #run cased(VOID_TYPE);
CASED_S64_TYPE :: #run cased(S64_TYPE);
CASED_TYPE_TYPE :: #run cased(TYPE_TYPE);

LiuType :: struct {
    type_id : s32;
}

cased :: (liu_type: LiuType) -> s32 {
    return liu_type.type_id;
}

operator == :: inline (left: LiuType, right: LiuType) -> bool {
    // @Todo this only checks for ID equality; will that be a problem in the future?
    return left.type_id == right.type_id;
}

TypeInfo :: struct {
    Kind :: enum u8 {
        UNINITIALIZED;
        VOID;
        TYPE;
        INTEGER;
        PROC;
    }

    kind := Kind.UNINITIALIZED;
    defn_file : s32 = -1;
    defn_begin : s32 = -1;
    defn_end : s32 = -1;
}

// @Rename ProcedureTypeInfo?
TypeInfoProcedure :: struct {
    using _base : TypeInfo;
    _base.kind = .PROC;
    return_type : LiuType;
    // @Todo this should probably be DeclarationIdent
    params : [] LiuType;
}

Expr :: struct {
    Kind :: enum u8 {
        UNINITIALIZED :: 0;

        FILE;

        // statement expression
        COMPTIME_DECLARATION;
        DECLARATION;
        DECLARATION_IDENT;
        ASSIGNMENT;
        // a, b, c := 12, 13, 14

        // complete expression
        BLOCK;
        TUPLE;
        PROCEDURE;
        RETURN;

        // binary expression
        ADD;
        MINUS;
        MULTIPLY;
        DIVIDE;

        KEYWORD_ARG;
        NOT_EQUAL;
        CHECK_EQUAL;
        LESS_THAN;
        LEQ_THAN;
        GREATER_THAN;
        GEQ_THAN;

        OR;
        AND;
        NOT;
        BIT_OR;
        BIT_XOR;
        BIT_AND;
        BIT_NOT;

        // unary expression
        REF;
        DEREF;
        SUBSCRIPT;
        DOT_ACCESS;
        CALL;

        // atom
        IDENT;
        EMPTY_PAREN;
        PAREN;
        INTEGER;
        NONE;
    }

    SyntaxFlags :: enum_flags u8 {
        PARENTHESIZED;
        // LOCKED; // This node is not thread safe and has someone operating on it.
    }

    // Flags for when the exprs become typed
    TypeFlags :: enum_flags u8 {
        // this prevents circular dependencies for single-threaded comptime
        // execution. Could it also prevent deadlocking for multi-threaded
        // execution?
        CHECKING_IN_PROGRESS;

        IS_TYPED; // for expressions that are done with type checking.
        IS_CONST; // for expressions that have a valid constant value
    }

    ConstantValue :: union {
        as_s64 : s64 = 0;
        as_type : LiuType = ---;

        // @Note this is a bit weird, but it seems fine. Like if it's constant,
        // You should be able to use it just like a function pointer in C, and
        // its runtime value should be generate-able from the AST.
        as_proc_ptr : *ProcedureExpr = ---;
    }
    #assert(size_of(ConstantValue) == 8);

    kind : Kind = .UNINITIALIZED;
    syntax_flags : SyntaxFlags = 0;
    type_flags : TypeFlags = 0;
    begin : s32;
    end : s32;
    type := UNSPECIFIED_TYPE;
    const_value : ConstantValue;
}

is_typed :: (expr: *Expr, loc := #caller_location) -> bool {
    assert(expr != null, "expression was null", loc = loc);

    if (expr.type_flags & .IS_TYPED) != 0 {
        assert(expr.type != UNSPECIFIED_TYPE);
        assert((expr.type_flags & .CHECKING_IN_PROGRESS) == 0);

        return true;
    }

    return false;
}

is_const :: (expr: *Expr, loc := #caller_location) -> bool {
    assert(expr != null, "expression was null", loc = loc);
    if !is_typed(expr)
        return false;

    return (expr.type_flags & .IS_CONST) != 0;
}

type_of_expr :: (expr: *Expr, loc := #caller_location) -> Result(LiuType) {
    if !is_typed(expr) {
        message := sprint("type_of_expr requires expression to be typed (type_flags=%)", expr.type_flags);
        return error(expr, message, loc = loc, success_type = LiuType);
    }

    return ok(expr.type);
}

set_value :: (expr: *Expr, value: s64) {
    assert(!is_typed(expr));

    expr.type = S64_TYPE;
    expr.type_flags |= .IS_TYPED;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
    expr.type_flags |= .IS_CONST;
    expr.const_value.as_s64 = value;
}

set_value :: (expr : *Expr, value: LiuType) {
    assert(!is_typed(expr));
    assert(value != UNSPECIFIED_TYPE, "set null as type expr %", value);

    expr.type = TYPE_TYPE;
    expr.type_flags |= .IS_TYPED;
    expr.type_flags |= .IS_CONST;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
    expr.const_value.as_type = value;
}

set_type :: inline (expr : *Expr, ty: LiuType) {
    assert(!is_typed(expr));
    assert(ty != UNSPECIFIED_TYPE);

    expr.type = ty;
    expr.type_flags |= .IS_TYPED;
    expr.type_flags &= ~.CHECKING_IN_PROGRESS;
}

BinaryExpr :: struct {
    using _base : Expr;
    left : *Expr;
    right : *Expr;
}

UnaryExpr :: struct {
    using _base : Expr;
    base : *Expr;
}

TupleExpr :: struct {
    using _base : Expr;
    _base.kind = .TUPLE;
    members : [] *Expr; // members allocated right after tuple struct
}

BlockExpr :: struct {
    using _base : Expr;
    _base.kind = .BLOCK;
    statements : [] *Expr; // statements allocated right after block struct
}

ParenExpr :: struct {
    using _base : Expr;
    _base.kind = .PAREN;
    statements : [] *Expr; // statements allocated right after paren struct
}

FileExpr :: struct {
    using __base : BlockExpr;
    __base.kind = .FILE;
    file_id : s32;
    buckets : BucketList;
}

CallExpr :: struct {
    using _base : Expr;
    _base.kind = .CALL;
    callee : *Expr;
    params : [] *Expr; // params allocated right after call struct
}

SubscriptExpr :: struct {
    using _base : Expr;
    _base.kind = .SUBSCRIPT;
    callee : *Expr;
    params : [] *Expr; // params allocated right after subscript struct
}

IntegerExpr :: struct {
    using _base : Expr;
    _base.kind = .INTEGER;
}

DotAccessExpr :: struct {
    using _base : Expr;
    _base.kind = .DOT_ACCESS;
    field_symbol : s32;
    base_object : *Expr;
}

IdentExprBase :: struct {
    using __base : Expr;
    symbol : s32;
}

IdentExpr :: struct {
    using _base : IdentExprBase;
    _base.kind = .IDENT;
    declaration : *DeclarationIdent = null;
}

ProcedureExpr :: struct {
    using _base : IdentExprBase;
    _base.kind = .PROCEDURE;
    params : [] *DeclarationExpr;
    return_type : *Expr;
    body : *Expr;
    bytecode : BasicBlock; // this probably needs to change eventually?
}

#assert(size_of(IdentExpr) == size_of(DeclarationIdent));
DeclarationIdent :: struct {
    using _base : IdentExprBase;
    _base.kind = .DECLARATION_IDENT;
    file_id : s32 = -1;
    bytecode_register : s32 = -1;
}

DeclarationExpr :: struct {
    using _base : Expr;
    _base.kind = .DECLARATION;
    type_declaration_nullable : *Expr = null;
    value_nullable : *Expr = null;
    idents : [] *DeclarationIdent;
}

AssignmentExpr :: struct {
    using _base : Expr;
    _base.kind = .ASSIGNMENT;
    target : *Expr;
    value : *Expr;
}

ReturnExpr :: struct {
    using _base : Expr;
    _base.kind = .RETURN;
    value : *Expr;
}

#add_context current_tree : *FileExpr = null;

use_tree :: (file: *FileExpr) #expand {
    assert(file != null);
    previous := context.current_tree;
    // @Note compiler should switch the value of context.current_tree by switching
    // contexts during job execution.
    assert(previous == null);

    context.current_tree = file;
    `defer context.current_tree = previous;
}

Buck :: ($T: Type, buckets : *BucketList = null) -> *T {
    bucketlist := buckets;
    if bucketlist == null {
        assert(context.current_tree != null);
        bucketlist = *context.current_tree.buckets;
    }

    push_allocator(bucket_allocator, bucketlist);
    value := New(T, initialized = true);

    return value;
}

BuckArray :: (array: [] $T) -> [] T {
    assert(context.current_tree != null);
    push_allocator(bucket_allocator, *context.current_tree.buckets);
    return array_copy(array);
}

for_expansion :: (iter: *Expr, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    `it : *Expr;
    `it_index : s64;
    for expr, level: ast_dfs(iter) {
        it = expr;
        it_index = level;

        #insert body;
    }
}

ast_dfs :: (iter: *Expr, insertion_style : AstDfs.InsertionStyle = .NO_INSERT) -> AstDfs {
    ast_dfs : AstDfs;
    ast_dfs.begin = iter;
    ast_dfs.insertion_style = insertion_style;

    return ast_dfs;
}

AstDfs :: struct {
    begin : *Expr = null;
    insertion_style : InsertionStyle = .NO_INSERT;

    InsertionStyle :: enum {
        NO_INSERT;
        INSERT_AND_VISIT_ORIGINAL;
        INSERT_AND_VISIT_INSERTED;
    }
}


// it_index is the level in the tree you're at
for_expansion :: (iter: *AstDfs, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    // @Todo Eventually do we want to use this stuff for like, visitor pattern whatevers?
    Node :: struct {
        expr: *Expr = null;
        explored_from: **Expr = null;
        level: s64;
    }

    push_stack :: (nodes: *[..] Node, _node: Node, exprs: .. Any) {
        node := _node;
        for < arg: exprs {
            if arg.value_pointer == null       continue;
            info := arg.type;
            assert(info != type_info(Any));

            if info == type_info(*Expr) {
                node.explored_from = cast(**Expr) arg.value_pointer;
                node.expr = << node.explored_from;
                if node.expr == null    continue;
                array_add(nodes, node);
                continue;
            }

            if info == type_info([] *Expr) {
                exprs := << cast(*[] *Expr) arg.value_pointer;
                for * < exprs {
                    node.explored_from = it;
                    node.expr = << it;
                    if node.expr == null    continue;
                    array_add(nodes, node);
                }
            }
        }
    }

    visit_child :: (exprs: .. Any) #expand {
        `defer push_stack(*`nodes, `node, ..exprs);
    }

    visit_non_child :: (exprs: .. Any) #expand {
        node := `node;
        node.level = -1;
        `defer push_stack(*`nodes, node, ..exprs);
    }

    nodes : [..] Node;
    node : Node;
    node.expr = iter.begin;
    node.level = 0;
    array_add(*nodes, node);

    while nodes.count > 0 {
        node = pop(*nodes);
        `it := node.expr;
        `it_index := node.level;

        #insert body;

        if (iter.insertion_style != .NO_INSERT) && node.explored_from {
            << node.explored_from = it;
        }

        if node.level == -1
            continue;

        expr := node.expr;
        if iter.insertion_style == .INSERT_AND_VISIT_INSERTED {
            expr = it;
        }

        node.level += 1;
        if expr.kind == { // @Todo add #complete to this
        case .UNINITIALIZED;
            assert(false, "found uninitialized node");

        case .FILE;
            file := cast(*FileExpr) expr;
            visit_child(file.statements);

        case .BLOCK;
            block := cast(*BlockExpr) expr;
            visit_child(block.statements);

        case .TUPLE;
            tuple := cast(*TupleExpr) expr;
            visit_child(tuple.members);

        case .COMPTIME_DECLARATION;
            decl := cast(*DeclarationExpr) expr;
            visit_child(cast([] *Expr) decl.idents, decl.type_declaration_nullable, decl.value_nullable);

        case .DECLARATION;
            decl := cast(*DeclarationExpr) expr;
            visit_child(cast([] *Expr) decl.idents, decl.type_declaration_nullable, decl.value_nullable);

        case .PROCEDURE;
            proc_expr := cast(*ProcedureExpr) expr;
            visit_child(cast([] *Expr) proc_expr.params, proc_expr.return_type, proc_expr.body);

        case .RETURN;
            return_expr := cast(*ReturnExpr) expr;
            visit_child(return_expr.value);

        case .CALL;
            call := cast(*CallExpr) expr;
            visit_child(call.callee, call.params);

        case .SUBSCRIPT;
            subscript := cast(*SubscriptExpr) expr;
            visit_child(subscript.callee, subscript.params);

        // Binary op
        case .ADD;             #through;
        case .MINUS;            #through;
        case .MULTIPLY;         #through;
        case .DIVIDE;           #through;
        case .KEYWORD_ARG;      #through;
        case .NOT_EQUAL;        #through;
        case .CHECK_EQUAL;      #through;
        case .LESS_THAN;        #through;
        case .LEQ_THAN;         #through;
        case .GREATER_THAN;     #through;
        case .GEQ_THAN;         #through;
        case .OR;               #through;
        case .AND;              #through;
        case .BIT_OR;           #through;
        case .BIT_XOR;          #through;
        case .BIT_AND;
            binary := cast(*BinaryExpr) expr;
            visit_child(binary.left, binary.right);
        }
    }
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

        CALL;
        RET;
        RET_VAL;
        PROC_PTR;

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

    register : s32 = -1;
}

CallOp :: struct {
    using _base : Opcode;
    _base.kind = .CALL;
    proc_ptr : s32; // Maybe this stuff should be absolute instead of relative. IDK.
    params : [] s32;
}

ProcPtrOp :: struct {
    using _base : Opcode;
    _base.kind = .PROC_PTR;
    value : *BasicBlock; // @Todo LMAO we gotta change this later but whatevs
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

is_valid :: (bb: *BasicBlock) -> bool {
    return bb.first != -1;
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

Target :: struct {
    register : s32; // if this is -1, then we're just making a new thingy
    // offset is unused
    offset : s32 = -1; // if this is -1, then we're just assigning to a register
    // size : s32; // @TODO how do we handle register sizes?

    reg :: (register: s32) -> Target {
        to_ret : Target;
        to_ret.register = register;
        return to_ret;
    }
}

// Not even writing to the target
VOID_TARGET :: Target.{ register = -1, offset = -1 };
// Making a new register
NEW_TARGET :: Target.{ register = -2, offset = -1 };

alloc_op :: (bb: *BasicBlock, $T: Type, spanned: *$B/interface Span, target := NEW_TARGET) -> *T {
    #assert(inherits_from(T, Opcode));

    output := bb_alloc(bb, T);
    pointer : *Opcode = output; // @Workaround repro/relative_pointers.jai
    relative_to_base := op_to_index(bb, pointer);

    if target.register == VOID_TARGET.register {
        pointer.register = -1;
    } else if target.register == NEW_TARGET.register {
        pointer.register = bb.next_register;
        bb.next_register += 1;
    } else {
        pointer.register = target.register;
    }

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

ast_init :: () {
    // We really need memory debuggers. Use-after-free should be an obvious bug
    // to catch in debug builds, honestly. Like what the fuck. Just uncommit the
    // range and set the reserved block to illegal. Like how can this not be solved.
    // I don't need malloc to be fast in GODDAMN DEBUG BUILDS. FOR FUCKS SAKE
    // OPERATING SYSTEMS HAVE SUPPORTED THIS SINCE THIS FUCKING INCEPTION OF
    // VIRTUAL MEMORY. STOP TELLING ME THESE THINGS ARE UNSAFE AND ACTUALLY DO THE
    // THINGS THAT WOULD MAKE IT SAFE.
    Scope.init(*builtin_scope, null, true);

    _static_buckets = BucketList.make();
    remember_allocators(*_types_array);

    idents : [..] *DeclarationIdent;
    symbols : [..] s32;
    defer array_free(idents);
    defer array_free(symbols);

    remember_allocators(*idents);
    remember_allocators(*symbols);

    builtin_type_name :: (symbol: s32, ty: LiuType) #expand {
        ident := New(DeclarationIdent);
        ident.symbol = symbol;
        ident.begin = -1;
        ident.end = -1;
        set_value(ident, ty);
        assert(is_typed(ident));
        array_add(*idents, ident);
        array_add(*symbols, symbol);
    }

    push_allocator(bucket_allocator, *_static_buckets);

    builtin_type_name(S64_SYMBOL, S64_TYPE);
    builtin_type_name(TYPE_SYMBOL, TYPE_TYPE);
    builtin_type_name(VOID_SYMBOL, VOID_TYPE);

    decl := New(DeclarationExpr);
    decl.kind = .COMPTIME_DECLARATION;
    decl.idents = array_copy(idents);
    decl.begin = -1;
    decl.end = -1;
    set_type(decl, VOID_TYPE);

    comptime_decl : Scope.ComptimeDecl;
    comptime_decl.decl = decl;
    for symbols {
        comptime_decl.index = it_index;
        table_add(*builtin_scope.comptime_variables, it, comptime_decl);
    }

    builtin_type :: (expected_type: LiuType, $T: Type) -> *T {
        actual_type, ptr := type_alloc(T);
        assert(expected_type == actual_type);
        return ptr;
    }

    none_type := builtin_type(VOID_TYPE, TypeInfo);
    none_type.kind = .VOID;

    int_type := builtin_type(S64_TYPE, TypeInfo);
    int_type.kind = .INTEGER;

    type_type := builtin_type(TYPE_TYPE, TypeInfo);
    type_type.kind = .TYPE;

}

Scope :: struct {
    ComptimeDecl :: struct {
        decl: *DeclarationExpr;
        index: s64;
    }
    Kind :: enum u8 {
        BASE;
        PROC;
    }

    kind : Kind = .BASE;
    comptime_variables : Table(s32, ComptimeDecl);
    runtime_variables : Table(s32, *DeclarationIdent);
    parent: *Scope = null;
    comptime_capture := false;

    init :: (scope: *Scope, parent : *Scope, comptime : bool) {
        init(*scope.comptime_variables);
        init(*scope.runtime_variables);
        scope.parent = parent;
        scope.comptime_capture = comptime;
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

ProcScope :: struct {
    using _base : Scope;
    _base.kind = .PROC;
    return_type : LiuType;
}

init_scoped :: (scope: *ProcScope, parent: *Scope, return_type: LiuType) #expand {
    Scope.init(*scope._base, parent, false);
    scope.return_type = return_type;

    `defer Scope.uninit(scope);
}

builtin_scope : Scope;
Types : struct {
    proc :: (params: .. LiuType, return_type := VOID_TYPE) -> LiuType {
        push_allocator(bucket_allocator, *_static_buckets);

        proc_type, ty_info := type_alloc(TypeInfoProcedure);
        ty_info.params = array_copy(params);
        ty_info.return_type = return_type;

        return proc_type;
    }
};

operator [] :: (db: type_of(Types), ty: LiuType) -> *TypeInfo {
    assert(ty.type_id > 0);
    return _types_array[ty.type_id - 1];
}

#scope_file

// comptime builtins are things like s64
_static_buckets : BucketList = ---;
_types_array : [..] *TypeInfo;

type_alloc :: ($T: Type) -> LiuType, *T {
    push_allocator(bucket_allocator, *_static_buckets);
    #assert(inherits_from(T, TypeInfo));
    ptr := New(T);
    array_add(*_types_array, ptr);

    liu_type : LiuType;
    liu_type.type_id = cast(s32) _types_array.count;

    return liu_type, ptr;
}

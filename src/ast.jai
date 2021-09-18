#import "Basic";
#import "buckets";
#import "liu";

// @Todo maybe everything under 0 should be a type variable
// UN_TYPE :: LiuType.{ type_id = -2, pointer_count = 0 };
// SN_TYPE :: LiuType.{ type_id = -1, pointer_count = 0 };
UNSPECIFIED_TYPE :: LiuType.{ type_id = 0, pointer_count = 0 };
NONE_TYPE :: LiuType.{ type_id = 1, pointer_count = 0 };
S64_TYPE :: LiuType.{ type_id = 2, pointer_count = 0 };
TYPE_TYPE :: LiuType.{ type_id = 3, pointer_count = 0 };

// CASED_UN_TYPE :: #run cased(UN_TYPE);
// CASED_SN_TYPE :: #run cased(SN_TYPE);
CASED_UNSPECIFIED_TYPE :: #run cased(UNSPECIFIED_TYPE);
CASED_NONE_TYPE :: #run cased(NONE_TYPE);
CASED_S64_TYPE :: #run cased(S64_TYPE);
CASED_TYPE_TYPE :: #run cased(TYPE_TYPE);

LiuType :: struct {
    type_id : s32 = 0;
    pointer_count : u8 = 0;
}

cased :: (liu_type: LiuType) -> s64 {
    out : union { ty: LiuType; value: s64; } = ---;
    out.value = 0;
    out.ty.type_id = liu_type.type_id;
    out.ty.pointer_count = liu_type.pointer_count;

    return out.value;
}

operator == :: inline (left: LiuType, right: LiuType) -> bool {
    return (left.type_id == right.type_id) & (left.pointer_count == right.pointer_count);
}

Expr :: struct {
    Kind :: enum u8 {
        UNINITIALIZED :: 0;

        FILE;

        // statement expression
        DECLARATION;
        DECLARATION_IDENT;
        // a, b, c := 12, 13, 14

        // complete expression
        BLOCK;
        TUPLE;

        // binary expression
        ADD;
        MINUS;
        MULTIPLY;
        DIVIDE;

        ASSIGN;
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
        DEREF; // *ptr
        SUBSCRIPT;
        DOT_ACCESS;
        CALL;

        // atom
        IDENT;
        EMPTY_PAREN;
        PAREN;
        INTEGER;
    }

    SyntaxFlags :: enum_flags u8 {
        // COMPTIME_DECLARATION;
        PARENTHESIZED;
    }

    kind : Kind = .UNINITIALIZED;
    syntax_flags : SyntaxFlags = 0;
    begin : s32;
    end : s32;

    // Flags for when the exprs become typed
    TypeFlags :: enum_flags u16 {
        IS_TYPED; // for expressions that are done with type checking.
        TYPE_SLOT_IS_VALUE;
    }

    // @Todo we could potentially try to pack in a pointer to a constant value
    // well. Although maybe at that point its not worth it.
    type_slot : LiuType = UNSPECIFIED_TYPE;
    #place type_slot;
    do_not_used_s32 : s32 = ---;
    do_not_used_u8 : u8 = ---;
    padding_u8 : u8 = ---; // @Todo we can use these for flags
    type_flags : TypeFlags = 0;

    // These bois make sure that nothing fishy happens to LiuType, because we use its padding for data
    #assert(size_of(LiuType) == 8);
    #assert(type_info(LiuType).members.count == 2);
    #assert(has_field_at_index(LiuType, s32, 0));
    #assert(has_field_at_index(LiuType, u8, 1));
}

is_typed :: (expr: *Expr) -> bool {
    assert(expr != null);
    return ((expr.type_flags & .IS_TYPED) != 0) && (expr.type_slot != UNSPECIFIED_TYPE);
}

type_of_expr :: (expr: *Expr) -> LiuType {
    assert(is_typed(expr));
    if expr.type_flags & .TYPE_SLOT_IS_VALUE
        return TYPE_TYPE;

    return expr.type_slot;
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
    arguments : [] *Expr; // arguments allocated right after call struct
}

SubscriptExpr :: struct {
    using _base : Expr;
    _base.kind = .SUBSCRIPT;
    callee : *Expr;
    arguments : [] *Expr; // arguments allocated right after subscript struct
}

IntegerExpr :: struct {
    using _base : Expr;
    _base.kind = .INTEGER;
    value : s64;
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
    declaration : *DeclarationIdent = null; // @Todo what if the reference is in a different file?
}

#assert(size_of(IdentExpr) == size_of(DeclarationIdent));
DeclarationIdent :: struct {
    using _base : IdentExprBase;
    _base.kind = .DECLARATION_IDENT;
    file_id : s32;
    bytecode_register : s32 = -1;
}

DeclarationExpr :: struct {
    using _base : Expr;
    _base.kind = .DECLARATION;
    type_declaration_nullable : *Expr = null;
    value_nullable : *Expr = null;
    idents : [] *DeclarationIdent;
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
    out : [] T = NewArray(array.count, T, initialized = false);
    memcpy(out.data, array.data, array.count * size_of(T));
    return out;
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
        VISIT_ORIGINAL;
        VISIT_INSERTED;
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

    visit :: (exprs: .. Any) #expand {
        node := `node;
        nodes := *`nodes;
        for < arg: exprs {
            if arg.value_pointer == null       continue;
            info := arg.type;

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
        if iter.insertion_style == .VISIT_INSERTED {
            expr = it;
        }

        node.level += 1;
        if expr.kind == { // @Todo add #complete to this
        case .UNINITIALIZED;
            assert(false, "found uninitialized node");

        case .FILE;
            file := cast(*FileExpr) expr;
            visit(file.statements);

        case .BLOCK;
            block := cast(*BlockExpr) expr;
            visit(block.statements);

        case .TUPLE;
            tuple := cast(*TupleExpr) expr;
            visit(tuple.members);

        case .DECLARATION;
            decl := cast(*DeclarationExpr) expr;
            visit(decl.idents, decl.type_declaration_nullable, decl.value_nullable);

        case .CALL;
            call := cast(*CallExpr) expr;
            visit(call.callee, call.arguments);

        case .SUBSCRIPT;
            subscript := cast(*SubscriptExpr) expr;
            visit(subscript.callee, subscript.arguments);

        // Binary op
        case .ADD;             #through;
        case .MINUS;            #through;
        case .MULTIPLY;         #through;
        case .DIVIDE;           #through;
        case .ASSIGN;           #through;
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
            visit(binary.left, binary.right);
        }
    }
}




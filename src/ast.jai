#import "Basic";
#import "buckets";
#import "liu";

// @Todo maybe everything under 0 should be a type variable
// UN_TYPE :: LiuType.{ type_id = -2, pointer_count = 0 };
// SN_TYPE :: LiuType.{ type_id = -1, pointer_count = 0 };
UNSPECIFIED_TYPE :: LiuType.{ type_id = 0};
NONE_TYPE :: LiuType.{ type_id = 1 };
S64_TYPE :: LiuType.{ type_id = 2 };
TYPE_TYPE :: LiuType.{ type_id = 3 };

// CASED_UN_TYPE :: #run cased(UN_TYPE);
// CASED_SN_TYPE :: #run cased(SN_TYPE);
CASED_UNSPECIFIED_TYPE :: #run cased(UNSPECIFIED_TYPE);
CASED_NONE_TYPE :: #run cased(NONE_TYPE);
CASED_S64_TYPE :: #run cased(S64_TYPE);
CASED_TYPE_TYPE :: #run cased(TYPE_TYPE);

LiuType :: struct {
    type_id : s32;
}

cased :: (liu_type: LiuType) -> s32 {
    return liu_type.type_id;
}

operator == :: inline (left: LiuType, right: LiuType) -> bool {
    return left.type_id == right.type_id;
}

Expr :: struct {
    Kind :: enum u8 {
        UNINITIALIZED :: 0;

        FILE;

        // statement expression
        COMPTIME_DECLARATION;
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

type_of_expr :: (expr: *Expr, loc := #caller_location) -> LiuType {
    assert(is_typed(expr), "type_of_expr requires expression to be typed (type_flags=%)", expr.type_flags, loc = loc);

    return expr.type;
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
            visit_child(decl.idents, decl.type_declaration_nullable, decl.value_nullable);

        case .DECLARATION;
            decl := cast(*DeclarationExpr) expr;
            visit_child(decl.idents, decl.type_declaration_nullable, decl.value_nullable);

        case .CALL;
            call := cast(*CallExpr) expr;
            visit_child(call.callee, call.arguments);

        case .SUBSCRIPT;
            subscript := cast(*SubscriptExpr) expr;
            visit_child(subscript.callee, subscript.arguments);

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
            visit_child(binary.left, binary.right);
        }
    }
}




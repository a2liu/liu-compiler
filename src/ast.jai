#import "Basic";
#import "Hash_Table";

#import "buckets";
#import "liu";

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


    kind : Kind = .UNINITIALIZED;
    syntax_flags : SyntaxFlags = 0;
    begin : s32;
    end : s32;
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
    _unused_padding : s32 = ---;
}

ProcedureExpr :: struct {
    using _base : IdentExprBase;
    _base.kind = .PROCEDURE;
    params : [] *DeclarationExpr;
    return_type : *Expr;
    body : *Expr;
}

#assert(size_of(IdentExpr) == size_of(DeclarationIdent));
DeclarationIdent :: struct {
    using _base : IdentExprBase;
    _base.kind = .DECLARATION_IDENT;
    file_id : s32 = -1;
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

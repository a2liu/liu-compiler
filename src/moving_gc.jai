#import "Basic";
#import "Hash_Table";

#import "buckets";
#import "liu";
#import "ast";

run_gc :: (file: *FileExpr) -> *FileExpr {
    // u64 is the bits of the pointer
    translations : Table(u64, *Expr);
    init(*translations);

    buckets := BucketList.make();

    // allocate the new tree's nodes, marking when something in from-space goes to
    // something in to-space
    for file {
        Copy :: (original: *$T) -> *T #expand {
            new_obj := New(T, initialized = false);
            memcpy(new_obj, original, size_of(T));
            table_set(*translations, cast(u64) original, new_obj);
            return new_obj;
        }

        push_allocator(bucket_allocator, *buckets);
        if it.kind == {
        case .UNINITIALIZED;
            assert(false, "found uninitialized node");

        case .FILE;
            file := cast(*FileExpr) it;
            new_file := Copy(file);
            new_file.statements = array_copy(file.statements);

        case .BLOCK;
            block := cast(*BlockExpr) it;
            new_block := Copy(block);
            new_block.statements = array_copy(block.statements);

        case .TUPLE;
            tuple := cast(*TupleExpr) it;
            new_tuple := Copy(tuple);
            new_tuple.members = array_copy(tuple.members);

        case .DECLARATION;
            decl := cast(*DeclarationExpr) it;
            new_decl := Copy(decl);
            new_decl.idents = array_copy(decl.idents);

        case .CALL;
            call := cast(*CallExpr) it;
            new_call := Copy(call);
            new_call.arguments = array_copy(call.arguments);

        case .SUBSCRIPT;
            subscript := cast(*SubscriptExpr) it;
            new_subscript := Copy(subscript);
            new_subscript.arguments = array_copy(subscript.arguments);

        // Binary op
        case .ADD;              #through;
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
            binary := cast(*BinaryExpr) it;
            new_binary := Copy(binary);

        case .IDENT;
            ident := cast(*IdentExpr) it;
            new_ident := Copy(ident);

        case .INTEGER;
            integer := cast(*IntegerExpr) it;
            new_integer := Copy(integer);
        }
    }

    // fix up references
    for ast_dfs(file, insertion_style = .INSERT_AND_VISIT_INSERTED) {
        new_pointer, success := table_find(translations, cast(u64) it);
        assert(success, "we missed a node (kind=%)", it.kind);
        assert(new_pointer != null, "we allocated a null pointer?");
        it = new_pointer;
    }

    file_expr, success := table_find(translations, cast(u64) file);
    assert(success);
    assert(file_expr.kind == .FILE);
    to_file := cast(*FileExpr) file_expr;
    to_file.buckets = buckets;
    return to_file;
}

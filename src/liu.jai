#import "Basic";
#import "buckets";
#import "hashmap";

LIU_DEBUG :: true;

liu_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%] %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

UNDERSCORE_SYMBOL : s32 : 0;
IT_SYMBOL : s32 : 1;
IDX_SYMBOL : s32 : 2;
KEYWORD_ARGS_SYMBOL : s32 : 3;
TRUE_SYMBOL : s32 : 4;
FALSE_SYMBOL : s32 : 5;
NONE_SYMBOL : s32 : 6;
STRING_SYMBOL : s32 : 7;
ANY_SYMBOL : s32 : 8;
BOOL_SYMBOL : s32 : 9;
S64_SYMBOL : s32 : 10;

Symbols :: struct {
    symbol_to_name : [..] string;
    name_to_symbol : Map(string, s32);

    make :: () -> Symbols {
        syms : Symbols;
        syms.name_to_symbol = empty_map(string, s32, capacity = 64);
        array_reserve(*syms.symbol_to_name, 64);

        assert(UNDERSCORE_SYMBOL == add_symbol(*syms, "_"));
        assert(IT_SYMBOL == add_symbol(*syms, "it"));
        assert(IDX_SYMBOL == add_symbol(*syms, "idx"));
        assert(KEYWORD_ARGS_SYMBOL == add_symbol(*syms, "keyword_args"));

        assert(TRUE_SYMBOL == add_symbol(*syms, "true"));
        assert(FALSE_SYMBOL == add_symbol(*syms, "false"));
        assert(NONE_SYMBOL == add_symbol(*syms, "none"));
        assert(STRING_SYMBOL == add_symbol(*syms, "string"));
        assert(ANY_SYMBOL == add_symbol(*syms, "any"));
        assert(BOOL_SYMBOL == add_symbol(*syms, "bool"));
        assert(S64_SYMBOL == add_symbol(*syms, "s64"));

        return syms;
    }
}

add_symbol :: (syms: *Symbols, ident: string) -> s32 {
    found, sym := map_find(*syms.name_to_symbol, ident);
    if found    return sym;

    sym = cast,trunc(s32) syms.symbol_to_name.count;
    array_add(*syms.symbol_to_name, ident);
    map_set(*syms.name_to_symbol, ident, sym);

    return sym;
}

// @Todo maybe everything under 0 should be a type variable
// UN_TYPE :: LiuType.{ type_id = -2, pointer_count = 0 };
// SN_TYPE :: LiuType.{ type_id = -1, pointer_count = 0 };
UNSPECIFIED_TYPE :: LiuType.{ type_id = 0, pointer_count = 0 };
VOID_TYPE :: LiuType.{ type_id = 1, pointer_count = 0 };
S64_TYPE :: LiuType.{ type_id = 2, pointer_count = 0 };
TYPE_TYPE :: LiuType.{ type_id = 3, pointer_count = 0 };

// CASED_UN_TYPE :: #run cased(UN_TYPE);
// CASED_SN_TYPE :: #run cased(SN_TYPE);
CASED_UNSPECIFIED_TYPE :: #run cased(UNSPECIFIED_TYPE);
CASED_VOID_TYPE :: #run cased(VOID_TYPE);
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

    return success(expr.type_slot);
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
    idents : [] DeclarationIdent;
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

// it_index is the level in the tree you're at
for_expansion :: (iter: *Expr, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    // @Todo Eventually do we want to use this stuff for like, visitor pattern whatevers?
    Node :: struct {
        expr: *Expr;
        level: s64;
    }

    visit :: (exprs: .. Any) #expand {
        node := `node;
        nodes := *`nodes;
        for < exprs {
            if it.value_pointer == null       continue;
            info := it.type;

            if info == type_info(*Expr) {
                node.expr = << cast(**Expr) it.value_pointer;
                if node.expr == null    continue;
                array_add(nodes, node);
            }

            if info == type_info([] *Expr) {
                exprs := << cast(*[] *Expr) it.value_pointer;
                for < exprs {
                    node.expr = it;
                    array_add(nodes, node);
                }
            }
        }
    }

    nodes : [..] Node;
    node : Node;
    node.expr = iter;
    node.level = 0;
    array_add(*nodes, node);

    prev_index := -1;
    while nodes.count > 0 {
        node = pop(*nodes);
        `it := node.expr;
        `it_index := node.level;
        `it_motion := it_index - prev_index;
        prev_index = it_index;

        #insert body;

        node.level += 1;
        if it.kind == { // @Todo add #complete to this
        case .UNINITIALIZED;
            assert(false, "found uninitialized node");

        case .FILE;
            file := cast(*FileExpr) it;
            visit(file.statements);

        case .BLOCK;
            block := cast(*BlockExpr) it;
            visit(block.statements);

        case .TUPLE;
            tuple := cast(*TupleExpr) it;
            visit(tuple.members);

        case .DECLARATION;
            decl := cast(*DeclarationExpr) it;
            visit(decl.type_declaration_nullable, decl.value_nullable);

        case .CALL;
            call := cast(*CallExpr) it;
            visit(call.callee, call.arguments);

        case .SUBSCRIPT;
            subscript := cast(*SubscriptExpr) it;
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
            binary := cast(*BinaryExpr) it;
            visit(binary.left, binary.right);
        }
    }
}

Spanned :: struct {
    begin: s32;
    end: s32;
}


Result :: struct(Value: Type, Error: Type = string, insert_fields := true) {
    #if insert_fields {
        #if #run type_info(Value).type == .STRUCT {
            using value: Value;

            #if #run !has_member(Value, "begin", s32)   begin: s32;
            #if #run !has_member(Value, "end", s32)  end: s32;
        } else {
            value: Value;
            begin: s32;
            end: s32;
        }
    } else #if #run type_info(Value).type == .STRUCT {
        using value: Value;
    } else {
        value: Value;
    }

    did_succeed: bool = true;
    error: Error;
    stack_trace : [] Stack_Trace_Node;
}

success :: () -> Result(void) {
    result : Result(void);
    result.did_succeed = true;
    result.begin = -1;
    result.end = -1;

    return result;
}

success :: (value: $T) -> Result(T) {
    result : Result(T);
    result.did_succeed = true;
    result.value = value;
    result.begin = -1;
    result.end = -1;

    return result;
}

error :: (value: *$T/interface Spanned, message: string, loc := #caller_location, $success_type := void) -> Result(success_type) {
    result : Result(success_type);
    result.begin = value.begin;
    result.end = value.end;
    result.did_succeed = false;
    result.error = message;
    #if LIU_DEBUG && #run has_member(T, "stack_trace", [] Stack_Trace_Node) {
        result.stack_trace = value.stack_trace;
    } else #if LIU_DEBUG {
        result.stack_trace = pack_stack_trace();
        result.stack_trace[0] = result.stack_trace[1];
        result.stack_trace[0].line_number = cast(u32) loc.line_number;
    }

    return result;
}

has_member :: ($T: Type, member_name: string, $ty: Type) -> bool {
    info := type_info(T);

    member := get_field(info, member_name);
    if !member      return false;
    if member.type != type_info(ty)    return false;

    return true;
}

inherits_from :: ($ty: Type, $base: Type) -> bool {
    ty_info := type_info(ty);
    base_info := type_info(base);
    if ty_info == base_info     return true;

    if ty_info.type != .STRUCT    return false;
    struct_info := cast(*Type_Info_Struct) ty_info;

    if struct_info.members.count < 1            return false;
    if struct_info.members[0].type != base_info      return false;

    return true;
}

has_field_at_index :: ($base: Type, $field: Type, $index: s64) -> bool {
    ty_info := type_info(base);
    field_info := type_info(field);

    assert(ty_info.type == .STRUCT);
    if index < ty_info.members.count {
        return ty_info.members[index].type == field_info;
    }

    return false;
}

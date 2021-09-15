#import "Basic";
#import "hashmap";

GONE_DEBUG :: true;

gone_logger :: (message: string, data: *void, info: Log_Info) {
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
VOID_SYMBOL : s32 : 9;
BOOL_SYMBOL : s32 : 10;
S64_SYMBOL : s32 : 11;

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
        assert(VOID_SYMBOL == add_symbol(*syms, "void"));
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
// UN_TYPE :: GoneType.{ type_id = -2, pointer_count = 0 };
// SN_TYPE :: GoneType.{ type_id = -1, pointer_count = 0 };
UNSPECIFIED_TYPE :: GoneType.{ type_id = 0, pointer_count = 0 };
VOID_TYPE :: GoneType.{ type_id = 1, pointer_count = 0 };
S64_TYPE :: GoneType.{ type_id = 2, pointer_count = 0 };
TYPE_TYPE :: GoneType.{ type_id = 3, pointer_count = 0 };

// CASED_UN_TYPE :: #run cased(UN_TYPE);
// CASED_SN_TYPE :: #run cased(SN_TYPE);
CASED_UNSPECIFIED_TYPE :: #run cased(UNSPECIFIED_TYPE);
CASED_VOID_TYPE :: #run cased(VOID_TYPE);
CASED_S64_TYPE :: #run cased(S64_TYPE);
CASED_TYPE_TYPE :: #run cased(TYPE_TYPE);

GoneType :: struct {
    type_id : s32 = 0;
    pointer_count : u8 = 0;
}

Expr :: struct {
    Kind :: enum u8 {
        UNINITIALIZED :: 0;

        FILE;

        // statement expression
        DECLARATION;
        // a, b, c := 12, 13, 14

        // complete expression
        BLOCK;
        TUPLE;

        // binary expression
        PLUS;
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
        COMPTIME_DECLARATION;
        PARENTHESIZED;
    }

    kind : Kind = .UNINITIALIZED;
    syntax_flags : SyntaxFlags = 0;
    begin : s32;
    end : s32;

    // Flags for when the exprs become typed
    TypeFlags :: enum_flags u16 {
        IS_TYPED;
        TYPE_SLOT_IS_VALUE;
    }

    type_slot : GoneType = UNSPECIFIED_TYPE;
    #place type_slot;
    do_not_used_s32 : s32 = ---;
    do_not_used_u8 : u8 = ---;
    padding_u8 : u8 = ---; // @Todo we can use these for flags
    type_flags : TypeFlags = 0;

    // These bois make sure that nothing fishy happens to GoneType, because we use its padding for data
    #assert(size_of(GoneType) == 8);
    #assert(type_info(GoneType).members.count == 2);
    #assert(has_field_at_index(GoneType, s32, 0));
    #assert(has_field_at_index(GoneType, u8, 1));
}

cased :: (gone_type: GoneType) -> s64 {
    out : union { ty: GoneType; value: s64; } = ---;
    out.value = 0;
    out.ty.type_id = gone_type.type_id;
    out.ty.pointer_count = gone_type.pointer_count;

    return out.value;
}

operator == :: inline (left: GoneType, right: GoneType) -> bool {
    return (left.type_id == right.type_id) & (left.pointer_count == right.pointer_count);
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

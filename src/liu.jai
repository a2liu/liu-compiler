#import "Basic";
#import "hashmap";

LIU_DEBUG :: true;

liu_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%] %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

UNDERSCORE_SYMBOL : s32 : 0;
IT_SYMBOL : s32 : 1;
IDX_SYMBOL : s32 : 2;
TYPE_SYMBOL : s32 : 3;
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
        assert(TYPE_SYMBOL == add_symbol(*syms, "type"));

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

Error :: struct {
    message : string;
    begin : s32;
    end : s32;
    #if LIU_DEBUG {
    stack_trace : [] Stack_Trace_Node;
    }
}

Span :: struct {
    begin: s32;
    end: s32;
}

new_span :: (begin: s32, end: s32) -> Span {
    span : Span = ---;
    span.begin = begin;
    span.end = end;
    return span;
}

Result :: struct(Value: Type) {
    did_succeed : bool = true;
    value : Value;
    #place value; error : *Error = ---;
}

read :: inline (result: Result(void)) -> *Error {
    if result.did_succeed {
        return null;
    }

    return result.error;
}

read :: inline (result: Result($T)) -> *Error, T {
    if result.did_succeed {
        return null, result.value;
    }

    value : T;
    return result.error, value;
}

ok :: () -> Result(void) {
    result : Result(void);
    result.did_succeed = true;

    return result;
}

ok :: (value: $T) -> Result(T) {
    result : Result(T);
    result.did_succeed = true;
    result.value = value;

    return result;
}

error :: (err: *Error, $success_type := void) -> Result(success_type) {
    result : Result(success_type);
    result.did_succeed = false;
    result.error = err;

    return result;
}

error :: (value: *$T/interface Span, message: string, loc := #caller_location, $success_type := void) -> Result(success_type) {
    result : Result(success_type);
    result.did_succeed = false;
    error := New(Error);
    error.message = message;
    error.begin = value.begin;
    error.end = value.end;
    #if LIU_DEBUG && #run has_member(T, "stack_trace", [] Stack_Trace_Node) {
        error.stack_trace = value.stack_trace;
    } else #if LIU_DEBUG {
        error.stack_trace = pack_stack_trace();
        error.stack_trace[0] = error.stack_trace[1];
        error.stack_trace[0].line_number = cast(u32) loc.line_number;
    }

    result.error = error;

    return result;
}

has_member :: ($T: Type, member_name: string, $ty: Type) -> bool {
    info := type_info(T);

    #if type_of(<< info) == Type_Info_Struct {
    member := get_field(info, member_name);
    if !member      return false;
    if member.type != type_info(ty)    return false;

    return true;
    } else {
    return false;
    }

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

#import "Basic";
#import "hashmap";

UNDERSCORE_SYMBOL : s32 : 0;
IT_SYMBOL : s32 : 1;
IDX_SYMBOL : s32 : 2;
KEYWORDS_SYMBOL : s32 : 3;

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
        assert(KEYWORDS_SYMBOL == add_symbol(*syms, "keywords"));

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

GoneType :: struct {
    type_id: s32 = -1;
    pointer_count: u8 = 0;
}

Result :: struct(Value: Type, Error: Type = string, insert_fields := true) {
    #if insert_fields {
        #if #run type_info(Value).type == .STRUCT {
            using value: Value;

            #if #run !has_members(Value, "begin")   begin: s32;
            #if #run !has_members(Value, "end")  end: s32;
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
}

has_members :: ($T: Type, members: .. string) -> bool {
    info := type_info(T);

    for member_name: members {
        member := get_field(info, member_name);
        if !member      return false;
        if member.type != type_info(s32)    return false;
    }

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

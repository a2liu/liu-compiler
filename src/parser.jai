#import "Basic";
#import "hashmap";

Symbols :: struct {
    symbol_to_name: [..] string;
    name_to_symbol: Map(string, s64);
}

symbol_table :: () -> Symbols {
    syms : Symbols;
    array_reserve(*syms.symbol_to_name, 64);
    map_reserve(*syms.name_to_symbol, 64);

    return syms;
}

Parser :: struct {

}


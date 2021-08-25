#import "Basic";
#import "lexer";
#import "utils";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%]: %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

main :: () {
    lexer_init();

    lexer := Lexer.make("hello");
    token := lex_token(*lexer);
    print("%\n", token);
    if token.kind == .IDENT {
        print("ident_symbol: %\n", token.ident_symbol);
    }
}

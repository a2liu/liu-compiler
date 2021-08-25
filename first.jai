#import "Basic";
#import "lexer";
#import "utils";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%] %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

main :: () {
    lexer_init();

    context.logger = albert_logger;

    lexer := Lexer.make("hello");
    token := lex_token(*lexer);
    log("%", token);
    if token.kind == .IDENT {
        log("ident_symbol: %", token.ident_symbol);
    }
}

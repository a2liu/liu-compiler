#import "lexer";
#import "parser";
#import "utils";
#import "hello";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%] %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

main :: () {
    lexer_init();

    context.logger = albert_logger;

    lexer := Lexer.make("hello");
    token := lex_token(*lexer);
    while token.kind != .EOF {
        log("%", token.kind);
        token = lex_token(*lexer);
    }
}

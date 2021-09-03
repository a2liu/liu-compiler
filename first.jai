#import "Basic";
#import "lexer";
#import "parser";
#import "utils";
#import "parser";
#import "buckets";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%] %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

main :: () {
    context.logger = albert_logger;
    context.allocator = bucket_allocator;
    context.allocator_data = BucketList.make();

    lexer_init();

    lexer := Lexer.make("hello");
    token := lex_token(*lexer);
    while token.kind != .EOF {
        log("%", token.kind);
        token = lex_token(*lexer);
    }

    parse_complete_expr();
}

#run main();

#import "Basic";
#import "lexer";
#import "parser";
#import "utils";
#import "parser";
#import "buckets";
#import "dynamic_dispatch";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%] %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

Hello1 :: struct {
    internal :: () {}
}

Hello2 :: struct {
    internal :: () {}
}

Hello :: struct @dd_interface {
    internal :: () {}
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

    a : Hello1;
    b : Hello2;
    try := Dyn(Hello).make(*a);
}

// #run main();

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
    context.buckets = BucketList.make();

    lexer_init();

    lexer := Lexer.make("build + asdf");
    parser := Parser.consume_lexer_and_make(*lexer);

    for parser.tokens
        print("% ", it.kind);
    print("\n");

    result := parse_statement_expr(*parser);
    if result.did_succeed {
        for result.value {
            log("%", << it);
        }
    } else {
        log("%", result.error);
    }
}

#run main();

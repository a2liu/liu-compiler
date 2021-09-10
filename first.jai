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

    lexer := Lexer.make("build + asdf * fdsa");
    parser := Parser.consume_lexer_and_make(*lexer);

    print("Tokens: ");
    for parser.tokens
        print("% ", it.kind);
    print("\n\n");

    for result: parser {
        if result.did_succeed {
            for result.value {
                print("%", << it);
            }
            print("\n");
        } else {
            log("%", result.error);
        }
    }
    print("\n");
}



#run main();

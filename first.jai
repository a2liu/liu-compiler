#import "Basic";
#import "lexer";
#import "utils";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%]: %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

main :: () {
    lexer := Lexer.make("Hello");
    parse_number(*lexer);

    i := 0;
    for Cond(#code i < 10).{} {
        print("%\n", i);
        i += 1;
    }
}

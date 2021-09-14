#import "gone";
#import "Basic";
#import "lexer";
#import "parser";
#import "utils";
#import "parser";
#import "buckets";
#import "typechecker";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%] %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

main :: () {
    context.logger = albert_logger;

    lexer_init();

    symbols := Symbols.make();
    program_text := "build + asdf * fdsa";
    file_id : s32 = 0;
    file_result := parse_file(*symbols, file_id, program_text);
    if !file_result.did_succeed {
        log("%", file_result.error);
        exit(1);
    }
    file := file_result.value;

    for stmt: file.statements {
        for stmt {
            print("%", << it);
        }
        print("\n");
    }
    print("\n");

    check_file(file);
}

#run main();

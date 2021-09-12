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
    module_result := parse_file(*symbols, file_id, program_text);
    if !module_result.did_succeed {
        log("%", module_result.error);
        exit(1);
    }
    module := module_result.value;

    for stmt: module.statements {
        for stmt {
            print("%", << it);
        }
        print("\n");
    }
    print("\n");

    typecheck_module(module);
}

#run main();

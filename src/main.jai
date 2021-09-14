#import "Basic";
#import "File";
#import "gone";
#import "lexer";
#import "parser";
#import "utils";
#import "parser";
#import "buckets";
#import "typechecker";
#import "files";

run :: () {
    context.logger = gone_logger;
    lexer_init();
    compile(0, "hello : s64 = 12;");
}

test :: () {
    context.logger = gone_logger;
    lexer_init();

    for f_info: bfs_visit_files("test", recursive = false) {
        text := read_entire_file(f_info.full_name);
        compile(0, text);
    }

    print("Tests completed successfully!\n");
}

compile :: (file_id: s32, text: string) {
    symbols := Symbols.make();
    file_result := parse_file(*symbols, file_id, text);
    if !file_result.did_succeed {
        log("[%,%]: %", file_result.begin, file_result.end, file_result.error);
        #if GONE_DEBUG {
        print_stack_trace(*file_result.stack_trace[0]);
        }
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

    result := check_file(file);
    if !result.did_succeed {
        log("%", result.error);
        exit(1);
    }
}

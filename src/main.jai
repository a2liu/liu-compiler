#import "Basic";
#import "File";

#import "files";

#import "liu";
#import "ast";
#import "lexer";
#import "parser";
#import "typechecker";
#import "bytecode";
#import "utils";
#import "moving_gc";

init :: () {
    context.logger = liu_logger;

    lexer_init();
    typechecker_init();
}

main :: () {
    init();

    run("hello : s64 = 12;");
}

test :: () {
    init();

    for f_info: bfs_visit_files("test", recursive = false) {
        text := read_entire_file(f_info.full_name);
        print("Running test '%' ...\n", f_info.full_name);
        result := run(text);
        print("test '%' completed with result=%\n", f_info.full_name, result);
    }

    print("Tests completed successfully!\n");
}

run :: (text: string) -> s64 {
    symbols := Symbols.make();
    file := assert_result(parse_file(*symbols, 0, text), text);

    print("ast:\n");
    for stmt: file.statements {
        assert(stmt != null);
        previous_level := -1;
        for it, level: stmt {
            for level..previous_level {
                print("} ");
            }

            print("% { ", it.kind);
            previous_level = level;
        }
        for 0..previous_level {
            print("} ");
        }
        print("\n");
    }
    print("\n");

    assert_result(check_file(file), text);

    block := bytecode_file(file);

    print("basic block:\n");
    for block {
        print("kind: %, next: %, prev: %\n", it.kind, it.next, it.previous);
    }
    print("\n");

    print("running code...\n");
    interp := Interpreter.make();
    return interp_file(*interp, *block);
}

assert_result :: (res: Result($T), text: string) -> T {
    err, value := read(res);
    if err {
        line := 1;
        char_index := 1;
        for index: 0..(err.begin - 1) {
            char_index += 1;

            if text[index] == #char "\n" {
                line += 1;
                char_index = 1;
            }
        }

        log("[%,%]: %", line, char_index, err.message);
        #if LIU_DEBUG { print_stack_trace(*err.stack_trace[0]); }
        exit(1);
    }

    return value;
}

assert_result :: (res: Result(void), text: string) {
    err := read(res);
    if err {
        line := 1;
        char_index := 1;
        for index: 0..(err.begin - 1) {
            char_index += 1;

            if text[index] == #char "\n" {
                line += 1;
                char_index = 1;
            }
        }

        log("[%,%]: %", line, char_index, err.message);
        #if LIU_DEBUG { print_stack_trace(*err.stack_trace[0]); }
        exit(1);
    }
}

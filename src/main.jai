#import "Basic";
#import "File";
#import "String";

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
    ast_init();
}

main :: () {
    init();

    run("<anonymous>", "hello : s64 = 12;");
}

test :: () {
    init();

    for f_info: bfs_visit_files("test", recursive = false) {
        if begins_with(f_info.short_name, "ignored")
            continue;

        text := read_entire_file(f_info.full_name);
        result := run(f_info.full_name, text);
        print("'%' completed with result=%\n", f_info.full_name, result);
    }

    print("Tests completed successfully!\n");
}

run :: (test_name: string, text: string) -> s64 {
    symbols := Symbols.make();
    debug_output : String_Builder;
    init_string_builder(*debug_output);
    file := assert_result(parse_file(*symbols, 0, text), test_name, text, *debug_output);

    print_to_builder(*debug_output, "ast:\n");
    for stmt: file.statements {
        assert(stmt != null);
        previous_level := -1;
        for it, level: stmt {
            for level..previous_level {
                print_to_builder(*debug_output, "} ");
            }

            print_to_builder(*debug_output, "% { ", it.kind);
            previous_level = level;
        }
        for 0..previous_level {
            print_to_builder(*debug_output, "} ");
        }
        print_to_builder(*debug_output, "\n");
    }
    print_to_builder(*debug_output, "\n");

    assert_result(check_file(file), test_name, text, *debug_output);

    block := bytecode_file(file);

    print_to_builder(*debug_output, "basic block:\n");
    for block {
        print_to_builder(*debug_output, "kind: %, next: %, prev: %\n", it.kind, it.next, it.previous);
    }
    print_to_builder(*debug_output, "\n");

    interp := Interpreter.make();
    return interp_file(*interp, *block);
}

assert_result :: (res: Result($T), test_name: string, text: string, builder: *String_Builder) -> T {
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

        write_builder(builder);
        print("\n% [%,%]: %\n", test_name, line, char_index, err.message);
        #if LIU_DEBUG { print_stack_trace(*err.stack_trace[0]); }
        exit(1);
    }

    return value;
}

assert_result :: (res: Result(void), test_name: string, text: string, builder: *String_Builder) {
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

        write_builder(builder);
        print("\n% [%,%]: %\n", test_name, line, char_index, err.message);
        #if LIU_DEBUG { print_stack_trace(*err.stack_trace[0]); }
        exit(1);
    }
}

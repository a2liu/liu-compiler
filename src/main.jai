#import "Basic";
#import "File";

#import "files";

#import "liu";
#import "lexer";
#import "parser";
#import "typechecker";
#import "bytecode";
#import "interpreter";
#import "utils";

init :: () {
    context.logger = liu_logger;
    lexer_init();
    typechecker_init();
}

main :: () {
    init();

    compile(0, "hello : s64 = 12;");
}

test :: () {
    init();

    for f_info: bfs_visit_files("test", recursive = false) {
        text := read_entire_file(f_info.full_name);
        result := run(0, text);
        print("test '%' completed with result=%\n", f_info.full_name, result);
    }

    print("Tests completed successfully!\n");
}

run :: (file_id: s32, text: string) -> s64 {
    symbols := Symbols.make();
    file := assert_result(parse_file(*symbols, file_id, text));

    for stmt: file.statements {
        for stmt {
            print("%", << it);
        }
        print("\n");
    }
    print("\n");

    assert_result(check_file(file));

    block := bytecode_file(file);

    print("basic block:\n");
    for block {
        print("%\n", it);
        print("kind: %, next: %, prev: %\n", it.kind, it.next, it.previous);
    }
    print("\n");

    print("running code...\n");
    interp := Interpreter.make();
    return interp_file(*interp, *block);
}

assert_result :: (res: Result($T)) -> T {
    if res.did_succeed
        return res.value;

    log("[%,%]: %", res.begin, res.end, res.error);
    #if LIU_DEBUG { print_stack_trace(*res.stack_trace[0]); }
    exit(1);
    return res.value;
}

assert_result :: (res: Result(void)) {
    if res.did_succeed
        return;

    log("[%,%]: %", res.begin, res.end, res.error);
    #if LIU_DEBUG { print_stack_trace(*res.stack_trace[0]); }
    exit(1);
}

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

init :: () {
    context.logger = gone_logger;
    lexer_init();
    typechecker_init();
}

run :: () {
    init();

    compile(0, "hello : s64 = 12;");
}

test :: () {
    init();

    for f_info: bfs_visit_files("test", recursive = false) {
        text := read_entire_file(f_info.full_name);
        compile(0, text);
    }

    print("Tests completed successfully!\n");
}

compile :: (file_id: s32, text: string) {
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
}

assert_result :: (res: Result($T)) -> T {
    if res.did_succeed
        return res.value;

    log("[%,%]: %", res.begin, res.end, res.error);
    #if GONE_DEBUG { print_stack_trace(*res.stack_trace[0]); }
    exit(1);
    return res.value;
}

assert_result :: (res: Result(void)) {
    if res.did_succeed
        return;

    log("[%,%]: %", res.begin, res.end, res.error);
    #if GONE_DEBUG { print_stack_trace(*res.stack_trace[0]); }
    exit(1);
}

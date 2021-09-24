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
        result := run(text);
        print("test '%' completed with result=%\n", f_info.full_name, result);
    }

    print("Tests completed successfully!\n");
}

run :: (text: string) -> s64 {
    symbols := Symbols.make();
    file := assert_result(parse_file(*symbols, 0, text));

    print("ast:\n");
    for stmt: file.statements {
        assert(stmt != null);
        for stmt {
            print("% ", it.kind);
        }
        print("\n");
    }
    print("\n");

    assert_result(check_file(file));

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

assert_eq :: inline (left: $T, right: T, message := "left and right are not equal", args: .. Any, loc := #caller_location) {
    if left == right        return;

    if context.handling_assertion_failure  return;  // Avoid infinite loops.
    context.handling_assertion_failure = true;

    // We provide 'loc' in case _STACK_TRACE is turned off, but assertion_failed may well
    // look at the stack trace if it is available.
    context.assertion_failed(loc, tprint("% != %, %", left, right, tprint(message, ..args)));
    context.handling_assertion_failure = false;
} @NoProfile @NoDebug

assert_result :: (res: Result($T)) -> T {
    err, value := read(res);
    if err {
        log("[%,%]: %", err.begin, err.end, err.message);
        #if LIU_DEBUG { print_stack_trace(*err.stack_trace[0]); }
        exit(1);
    }

    return value;
}

assert_result :: (res: Result(void)) {
    err := read(res);
    if err {
        log("[%,%]: %", err.begin, err.end, err.message);
        #if LIU_DEBUG { print_stack_trace(*err.stack_trace[0]); }
        exit(1);
    }
}

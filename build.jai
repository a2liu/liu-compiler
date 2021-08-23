#import "Compiler";
#import "Basic";

#load "src/files/module.jai";

main :: () {
    w := compiler_create_workspace("Output Executable");
    assert(w != 0, "Workspace creation failed.\n");

    out_options := get_build_options(w);
    out_options.output_path = join(#filepath, ".build/");
    out_options.output_executable_name = "silly";
    out_options.output_type = .EXECUTABLE;
    import_path : [..] string;
    for out_options.import_path array_add(*import_path, it);
    array_add(*import_path, "src");
    out_options.import_path = import_path;
    set_build_options(out_options, w);

    compiler_begin_intercept(w);

    add_build_file("first.jai", w);

    while true {
        message := compiler_wait_for_message();
        if !message break;
        if message.kind == {
        case .COMPLETE;
            break;
        }
    }

    compiler_end_intercept(w);

    // None of the code in this file is intended to end up in an executable
    // of any kind. So, we tell the compiler not to make an executable for us:
    options := get_build_options();
    options.output_type = .NO_OUTPUT;  // No executable for the primary workspace.
    set_build_options(options);
}

#run main();

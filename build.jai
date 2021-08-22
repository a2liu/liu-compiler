#import "Compiler";
#import "Basic";

#load "src/files.jai";

// TODO do we need a real metaprogram?
main :: () {
    // Create a workspace to contain the program we want to compile.
    // We can pass a name to compiler_create_workspace that gets reported
    // back to us in error messages:
    //
    w := compiler_create_workspace("Silly Meta");
    if !w {
        print("Workspace creation failed.\n");
        return;
    }

    out_options := get_build_options(w);
    // out_options.output_executable_name = "silly";
    out_options.output_type = .NO_OUTPUT;
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

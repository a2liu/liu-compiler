#import "Compiler";
#import "Basic";

// TODO do we need a real metaprogram?
metaprogram :: () {
    // Create a workspace to contain the program we want to compile.
    // We can pass a name to compiler_create_workspace that gets reported
    // back to us in error messages:
    //
    w := compiler_create_workspace("Target Program");
    if !w {
        print("Workspace creation failed.\n");
        return;
    }

    out_options := get_build_options(w);
    out_options.output_executable_name = "silly";
    set_build_options(out_options, w);

    files, run_strings := compiler_get_source_files();
    compiler_begin_intercept(w);

    for files        add_build_file(it, w);

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

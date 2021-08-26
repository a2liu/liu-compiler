#import "Compiler";
#import "Basic";
#import "File_Utilities";
#import "Hash_Table";

#load "build.jai";

#run {
    if !is_initial_file()       return;

    options := get_build_options();
    options.output_type = .NO_OUTPUT;  // No executable for the primary workspace.
    set_build_options(options);

    w, out_options, import_path := init_build("Test Runner");

    out_options.output_path = join(#filepath, ".build/");
    out_options.output_executable_name = "test";
    out_options.output_type = .EXECUTABLE;
    out_options.import_path = import_path;
    out_options.array_bounds_check = .ALWAYS;
    out_options.cast_bounds_check = .FATAL;
    out_options.math_bounds_check = .NONFATAL;

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
}

#import "Compiler";
#import "Basic";
#import "File_Utilities";
#import "Hash_Table";

#load "libs/files/module.jai";

main :: () {
    w := compiler_create_workspace("Output Executable");
    assert(w != 0, "Workspace creation failed.\n");

    out_options := get_build_options(w);

    import_path : [..] string;
    array_reserve(*import_path, out_options.import_path.count + 2);
    for out_options.import_path array_add(*import_path, it);
    array_add(*import_path, join(#filepath, "src"));
    array_add(*import_path, join(#filepath, "libs"));

    modules : Table(string, string);
    init(*modules);

    for path: import_path {
        for f_info: bfs_visit_files(path, recursive = false) {
            _path, basename, _ext, _name := path_decomp(f_info.full_name);
            previous := table_find_pointer(modules, basename);
            if previous {
                message := sprint("module defined at `%` conflicts with module with same import name at `%`",
                                    << previous, f_info.full_name);
                compiler_report(message);
            }

            table_set(*modules, basename, f_info.full_name);
        }
    }

    out_options.output_path = join(#filepath, ".build/");
    out_options.output_executable_name = "gone";
    out_options.output_type = .EXECUTABLE;
    out_options.import_path = import_path;
    out_options.array_bounds_check = .ALWAYS;
    out_options.cast_bounds_check = .FATAL;
    out_options.math_bounds_check = .NONFATAL;
    // out_options.backend = .X64;
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

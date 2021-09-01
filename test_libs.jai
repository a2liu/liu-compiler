#import "Compiler";
#import "Basic";
#import "File_Utilities";
#import "Hash_Table";
#import "String";

#load "build.jai";

#run {
    options := get_build_options();
    options.output_type = .NO_OUTPUT;  // No executable for the primary workspace.
    set_build_options(options);

    w, out_options, import_path := init_build("Library Tests");
    out_options.output_type = .NO_OUTPUT;
    out_options.import_path = import_path;
    set_build_options(out_options, w);

    libs_folder := join(#filepath, "libs");
    defer free(libs_folder);

    builder : String_Builder;
    init_string_builder(*builder);
    print_to_builder(*builder, "test :: () {\n");

    for info : bfs_visit_files(libs_folder, recursive = false) {
        _path, basename, _ext, _name := path_decomp(info.full_name);

        import_line := tprint("    Mod%1 :: #import \"%1\";\n    Mod%1.test();\n", basename);
        print_to_builder(*builder, import_line);
    }
    print_to_builder(*builder, "}\n#run test();\n");

    str := builder_to_string(*builder);
    print("%", str);
    free_buffers(*builder);

    compiler_begin_intercept(w);

    add_build_string(str, w);

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

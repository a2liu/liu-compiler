#import "Compiler";
#import "Basic";
#import "File_Utilities";
#import "Hash_Table";
#import "String";

#load "libs/files/module.jai";

init_build :: (workspace_name: string) -> Workspace, Build_Options, [..] string {
    w := compiler_create_workspace(workspace_name);
    assert(w != 0, "Workspace creation failed.\n");

    out_options := get_build_options(w);

    import_path : [..] string;
    array_reserve(*import_path, out_options.import_path.count + 2);
    for out_options.import_path array_add(*import_path, it);
    array_add(*import_path, join(#filepath, "src"));
    array_add(*import_path, join(#filepath, "libs"));

    modules : Table(string, string);
    init(*modules);

    success := true;
    for path: import_path {
        for f_info: bfs_visit_files(path, visit_directories = true, recursive = false) {
            full_name := copy_string(f_info.full_name);
            _path, _basename, _ext, _name := path_decomp(full_name);
            basename := copy_string(_basename);
            to_lower(basename);

            previous := table_find_pointer(modules, basename);
            if previous {
                message := sprint("module defined at `%` conflicts with module with same import name at `%`",
                                    << previous, full_name);
                compiler_report(message);
                success = false;
            }

            table_set(*modules, basename, full_name);
        }
    }

    uninit(*modules);

    return w, out_options, import_path;
}

get_cwd :: () -> string {
    #if OS == .WINDOWS {
        result, success := get_working_directory();
        assert(success);
        return result;
    } else {
        result := get_working_directory();
        return result;
    }
}

is_initial_file :: (loc := #caller_location) -> bool {
    files, run_strings := compiler_get_source_files();
    max_len := 0;
    for files   max_len = max(it.count, max_len);

    result := get_cwd();

    result_data : [] u8 = ---;
    result_data.data = result.data;
    result_data.count = result.count;

    directory : [..] u8;
    array_reserve(*directory, result.count + 1 + max_len);
    add_final_slash := true;
    for result_data {
        if it == {
        case #char "\\";    #through;
        case #char "/";
            array_add(*directory, #char "/");
            add_final_slash = false;
        case;
            array_add(*directory, it);
            add_final_slash = true;
        }
    }
    if add_final_slash      array_add(*directory, #char "/");

    parent_len := directory.count;
    file := loc.fully_pathed_filename;
    for files {
        if is_absolute_path(it) && it == file   return true;

        directory.count = parent_len;
        path_data : [] u8 = ---;
        path_data.data = it.data;
        path_data.count = it.count;

        for path_data   array_add(*directory, it);

        abs_path : string = ---;
        abs_path.data = directory.data;
        abs_path.count = directory.count;

        if abs_path == file     return true;
    }

    return false;
}

#run {
    if !is_initial_file()       return;

    options := get_build_options();
    options.output_type = .NO_OUTPUT;  // No executable for the primary workspace.
    set_build_options(options);

    w, out_options, import_path := init_build("Output Executable");
    user, system := compiler_get_command_line_arguments();

    mode : enum { EXE; TEST; TEST_LIBS; } = .EXE;

    for user {
        if it == "test" {
            mode = .TEST;
        }
        if it == "libs" {
            mode = .TEST_LIBS;
        }
    }

    out_options.output_path = join(#filepath, ".build/");
    out_options.array_bounds_check = .ALWAYS;
    out_options.cast_bounds_check = .FATAL;
    out_options.math_bounds_check = .FATAL;
    out_options.import_path = import_path;

    if mode == {
    case .EXE;
        out_options.output_executable_name = "gone";
        out_options.output_type = .EXECUTABLE;
    case .TEST;
        out_options.output_type = .NO_OUTPUT;
    case .TEST_LIBS;
        out_options.output_type = .NO_OUTPUT;
    }

    set_build_options(out_options, w);
    compiler_begin_intercept(w);

    if mode == {
    case .EXE;
        add_build_string("Main :: #import \"main\";\nmain :: () { Main.run(); }\n", w);

    case .TEST;
        add_build_string("Main :: #import \"main\";\n#run Main.test();\n", w);

    case .TEST_LIBS;
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
        add_build_string(str, w);
    }

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

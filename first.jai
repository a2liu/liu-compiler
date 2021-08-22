#import "File_Utilities";
#import "Basic";
#import "String";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%]: %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

main :: () -> string {
    InStrings :: #import "strings";
    InWrite :: #import "write";
    InFiles :: #import "files";
    for_expansion :: InFiles.for_expansion;

    context.logger = albert_logger;

    builder := InStrings.StringBuilder.make();

    InWrite.write(*builder, path_strip_filename(#file));
    InWrite.write(*builder, "src");
    src_dir := InStrings.to_string(*builder);
    InStrings.clear_contents(*builder);

    for info : InFiles.bfs_visit_files(src_dir, recursive = true) {
        _path, basename, _ext, _name := path_decomp(info.full_name);

        import_and_run_line := tprint("Src%1 :: #import \"%1\";\n#run Src%1.test();\n", basename);
        InWrite.write(*builder, import_and_run_line);
    }

    free(src_dir);
    str := InStrings.to_string(*builder);
    print("%", str);
    InStrings.free_buffers(*builder);
    return str;
}

#insert #run main();

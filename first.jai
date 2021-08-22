#import "File_Utilities";
#import "Basic";
#import "String";

#load "src/hash.jai";
#load "src/write.jai";
#load "src/strings.jai";
#load "src/files.jai";
#load "src/utils.jai";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%]: %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

#run main();
main :: () {
    context.logger = albert_logger;

    builder : StringBuilder;
    init(*builder);

    write(*builder, path_strip_filename(#file));
    write(*builder, "src");
    src_dir := to_string(*builder);
    clear_contents(*builder);

    for info : bfs_visit_files(src_dir, recursive = true) {
        write(*builder, "#load \"");
        write(*builder, info.full_name);
        write(*builder, "\";\n");
    }

    free(src_dir);
    str := to_string(*builder);
    print("%", str);
    free_buffers(*builder);
    free(str);
}

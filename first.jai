#import "File_Utilities";
#import "Basic";
#import "String";

albert_logger :: (message: string, data: *void, info: Log_Info) {
    loc := info.location;
    print("[%:%,%]: %\n", loc.fully_pathed_filename, loc.line_number, loc.character_number, message);
}

// generate :: () -> string {
//     InStrings :: #import "strings";
//     InWrite :: #import "write";
//     InFiles :: #import "files";
//     for_expansion :: InFiles.for_expansion;
// 
//     context.logger = albert_logger;
// 
//     builder := InStrings.StringBuilder.make();
//     InWrite.write(*builder, path_strip_filename(#file));
//     InWrite.write(*builder, "src");
//     src_dir := InStrings.to_string(*builder);
//     InStrings.clear_contents(*builder);
// 
//     InWrite.write(*builder, "main :: () {\n");
// 
//     for info : InFiles.bfs_visit_files(src_dir, recursive = false) {
//         _path, basename, _ext, _name := path_decomp(info.full_name);
// 
//         import_line := tprint("    Src%1 :: #import \"%1\";\n    Src%1.test();\n", basename);
//         InWrite.write(*builder, import_line);
//     }
//     InWrite.write(*builder, "}\n");
// 
//     free(src_dir);
//     str := InStrings.to_string(*builder);
//     print("%", str);
//     InStrings.free_buffers(*builder);
//     return str;
// }
// 
// #insert #run generate();

main :: () {
    hasher :: #import "hasher";
    hasher.test();
    hashmap :: #import "hashmap";
    hashmap.test();
    strings :: #import "strings";
    strings.test();
    utils :: #import "utils";
    utils.test();
    write :: #import "write";
    write.test();
}

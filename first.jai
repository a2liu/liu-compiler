#import "File_Utilities";
#import "Basic"()(MEMORY_DEBUGGER=true);
#import "File";
#import "String";

#load "src/write.jai";
#load "src/strings.jai";
#load "src/files.jai";
#load "src/utils.jai";

already_logging := false;

albert_logger :: (message: string, data: *void, info: Log_Info) {
    if already_logging {
        << cast(*u8)null;
    }

    already_logging = true;
    print("%: %\n", info.location, message);
    already_logging = false;
}

generate_runs :: () {
    context.logger = albert_logger;

    builder : StringBuilder;
    init(*builder);

    write(*builder, path_strip_filename(#file));
    write(*builder, "src");
    src_dir := to_string(*builder);
    clear_contents(*builder);

    succeeded := visit_files(src_dir, recursive = true, user_data = *builder, proc = visitor);
    assert(succeeded);

    visitor :: (info: *File_Visit_Info, builder: *StringBuilder) {
      write(builder, "#load \"");
      write(builder, info.full_name);
      write(builder, "\";\n");
    }

    free(src_dir);
    str := to_string(*builder);
    print("%", str);
    free_buffers(*builder);
    free(str);
}

#run generate_runs();

main :: () {}

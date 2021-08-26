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
}

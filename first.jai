#import "File_Utilities";
#import "File";
#import "String";
#import "Basic";

generate_runs :: () -> string {
  builder : String_Builder;
  init_string_builder(*builder);

  append(*builder, path_strip_filename(#file));
  append(*builder, "src");
  src_dir := builder_to_string(*builder);
  reset(*builder);

  failed := visit_files(src_dir, recursive = true, user_data = *builder, proc = visitor);
  // assert(!failed);

  visitor :: (info: *File_Visit_Info, builder: *String_Builder) {
    append(builder, "#load \"");
    append(builder, info.full_name);
    append(builder, "\";");
  }


  return builder_to_string(*builder);
}

#insert #run generate_runs();

main :: () {}

#import "Compiler";
#import "Basic";
#import "strings";
#import "String";

tagged_union :: ($types: .. string) -> string {
    ty_builder := StringBuilder.make();
    defer free_buffers(*ty_builder);

    write(*ty_builder, "struct {\n");
    write(*ty_builder, "  Kind :: enum {\n");

    for ty: types {
        data : [] u8 = ---;
        data.data = ty.data;
        data.count = ty.count;

        kind_builder := StringBuilder.make();
        defer free_buffers(*builder);

        has_underscore := true;
        for data {
            if (#char "A" <= it && it <= #char "Z") {
                if !has_underscore    write(*kind_builder, #char "_");
                write(*kind_builder, it);
                has_underscore = false;
            } else if #char "a" <= it && it <= #char "z" {
                write(*kind_builder, it - 32);
                has_underscore = false;
            } else if it != #char "_" {
                write(*kind_builder, it);
                has_underscore = false;
            } else if !has_underscore {
                write(*kind_builder, #char "_");
                has_underscore = true;
            }
        }

        enum_name := to_string(kind_builder);
        defer free(enum_name);

        write_builder(*ty_builder, "    ");
        write_builder(*ty_builder, enum_name);
    }

    return to_string(ty_builder);
}

test :: () {}

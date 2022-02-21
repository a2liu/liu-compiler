#import "Compiler";
#import "Basic";
#import "File_Utilities";
#import "Hash_Table";
#import "String";

#load "../libs/files/module.jai";

MyType :: struct {}

for_expansion :: (iter: *MyType, body: Code, flags: For_Flags) #expand {
  frumbolias := true;
  donglebopper := false;

  `it := 0;
  `it_index := 0;

  for i: 0..9 {
    `it_index = i;

    #insert body;
  }

  if donglebopper {
    #insert body;
  }
}

my_macro :: (body: Code) #expand {
  for i: 0..9 {
    #insert body;
  }

  #insert body;
}

main :: () {
  collection := MyType.{};

  /*

  // This prints the warning 3 times

  for collection {
    a := copy_string("Hello, world!");
    to_lower(a);
  }

  */

  // This prints the warning 2 times
  my_macro(#code {
    a := copy_string("Hello, world!");
    to_lower(a);
  });
}

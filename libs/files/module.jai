#import "File_Utilities";
#import "Basic";
#import "String";
#import "Time";

VisitFileIter :: struct {
  dir_name: string;
  recursive: bool;
  visit_files: bool;
  visit_directories: bool;
  follow_symlinks : bool;
}


#if OS == .LINUX || OS == .MACOS {
    #load "posix.jai";
} else {
    #load "windows.jai";
}

bfs_visit_files :: (dir_name: string, recursive: bool, visit_files := true,
visit_directories := false, follow_symlinks := true) -> VisitFileIter {
  iter : VisitFileIter;
  iter.dir_name = dir_name;
  iter.recursive = recursive;
  iter.visit_files = visit_files;
  iter.visit_directories = visit_directories;
  iter.follow_symlinks = follow_symlinks;

  return iter;
}

test :: () {
    for bfs_visit_files(join(#filepath), true) {
        print("it = %, it_index = %\n", it, it_index);
    }

    print("file tests passed\n");
}

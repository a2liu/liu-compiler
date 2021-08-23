#scope_file

#import "Basic";
#import "String";
#import "Time";
#import "Time";
#import "File_Utilities";

#scope_export

VisitFileIter :: struct {
  dir_name: string;
  recursive: bool;
  visit_files: bool;
  visit_directories: bool;
  follow_symlinks : bool;
}

bfs_visit_files :: (dir_name: string, recursive: bool, visit_files := true, visit_directories := false,
                    follow_symlinks := true) -> VisitFileIter {
  iter : VisitFileIter;
  iter.dir_name = dir_name;
  iter.recursive = recursive;
  iter.visit_files = visit_files;
  iter.visit_directories = visit_directories;
  iter.follow_symlinks = follow_symlinks;

  return iter;
}

#if (OS == .LINUX) || (OS == .MACOS) {
    #load "unix.jai";
} else #if OS == .WINDOWS  {
    #load "windows.jai";
}


test :: () {
    for bfs_visit_files(join(#filepath), true) {
        print("it = %, it_index = %\n", it, it_index);
    }

    print("file tests passed\n");
}

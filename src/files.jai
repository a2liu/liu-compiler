#scope_file

Basic :: #import "Basic";
String :: #import "String";
Posix :: #import "POSIX";
Time :: #import "Time";
Files :: #import "File_Utilities";

#scope_export

#if OS == .WINDOWS {
  PATH_SEP_STRING :: "\\";
} else {
  PATH_SEP_STRING :: "/";
}

VisitFileIter :: struct {
  dir_name: string;
  recursive: bool;
  visit_files: bool;
  visit_directories: bool;
  follow_symlinks : bool;
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

for_expansion :: (using iter: *VisitFileIter, body: Code, flags: For_Flags) #expand {
    #assert(!flags);
    directories: [..] string;
    Basic.array_add(*directories, Basic.copy_string(dir_name));

    defer {
        for directories Basic.free(it);
        Basic.array_reset(*directories);
    };

    `it : Files.File_Visit_Info = ---;
    `it_index : void;

    //            for 0..directories.count-1 {
    // dir_name := directories[it];
    cursor := 0;
    while cursor < directories.count {
        dir_name := directories[cursor];
        cursor += 1;

        dirp := Posix.opendir(Basic.temp_c_string(dir_name));
        if !dirp {
            if cursor != 1  continue;

            error := Posix.errno();
            Basic.log_error("Unable to open directory'%': %.\n", dir_name, error);
            break; // FAILURE
        }
        defer Posix.closedir(dirp);

        entry := Posix.readdir(dirp);
        while entry != null {
            it.is_symlink = (entry.d_type == Posix.DT_LNK);
            if follow_symlinks || !it.is_symlink {
                name := Basic.to_string(entry.d_name.data);

                full_name := String.join(dir_name, "/", name);
                defer Basic.free(full_name);

                it.had_error = false;
                stats: Posix.stat_t;
                ret := Posix.stat(Basic.temp_c_string(full_name), *stats);
                if ret != 0 {
                    error := Posix.errno();
                    Basic.log_error("Unable to stat file '%': %.\n", full_name, error);
                    // ENOENT happens for symlinks that point to a missing file
                    // We still might want to visit those symlinks, so we report them
                    // It might also happen due to a race if the file is deleted between readdir and stat, but we let the user decide what to do with that information
                    // EACCES happens if we don’t have enought permissions for that file/dir. We still report it and let the user handle access errors
                    // ELOOP happens if we try to follow a symlink loop for too long
                    if error != Posix.ENOENT && error != Posix.EACCES && error != Posix.ELOOP {
                        cursor = directories.count;
                        break; // FAILURE
                    }
                    it.had_error = true;
                }

                it.short_name = name;
                it.full_name  = full_name;
                it.descend_into_directory = false;

                is_dir := Posix.S_ISDIR(stats.st_mode);
                if is_dir {
                    if (name != ".") && (name != "..") {
                        it.descend_into_directory = recursive;
                        if visit_directories  {
                            it.is_directory = true;
                            it.filetime = Time.timespec_to_filetime(stats.st_mtime);
                            #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                        }
                    }

                    if it.descend_into_directory  Basic.array_add(*directories, Basic.copy_string(full_name));
                } else {
                    if visit_files {
                        it.is_directory = false;
                        it.filetime = Time.timespec_to_filetime(stats.st_mtime);

                        #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                    }
                }
            }

            entry = Posix.readdir(dirp);
        }
    }
}

test :: () {
    for bfs_visit_files(String.join(#filepath), true) {
        Basic.print("it = %, it_index = %\n", it, it_index);
    }

    Basic.print("file tests passed\n");
}

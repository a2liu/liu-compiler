#import "String";
#import "POSIX";
#import "Time";

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
    array_add(*directories, copy_string(dir_name));

    defer {
        for directories free(it);
        array_reset(*directories);
    };

    `it : File_Visit_Info = ---;
    `it_index := 0;

    //            for 0..directories.count-1 {
    // dir_name := directories[it];
    cursor := 0;
    while cursor < directories.count {
        dir_name := directories[cursor];
        cursor += 1;

        dirp := opendir(temp_c_string(dir_name));
        if !dirp {
            if cursor != 1  continue;

            error := errno();
            log_error("Unable to open directory'%': %.\n", dir_name, error);
            return; // FAILURE
        }
        defer closedir(dirp);

        entry := readdir(dirp);
        while entry != null {
            it.is_symlink = (entry.d_type == DT_LNK);
            if follow_symlinks || !it.is_symlink {
                name := to_string(entry.d_name.data);

                full_name := join(dir_name, "/", name);
                defer free(full_name);

                it.had_error = false;
                stats: stat_t;
                ret := stat(temp_c_string(full_name), *stats);
                if ret != 0 {
                    error := errno();
                    log_error("Unable to stat file '%': %.\n", full_name, error);
                    // ENOENT happens for symlinks that point to a missing file
                    // We still might want to visit those symlinks, so we report them
                    // It might also happen due to a race if the file is deleted between readdir and stat, but we let the user decide what to do with that information
                    // EACCES happens if we don’t have enought permissions for that file/dir. We still report it and let the user handle access errors
                    // ELOOP happens if we try to follow a symlink loop for too long
                    if error != ENOENT && error != EACCES && error != ELOOP {
                        cursor = directories.count;
                        break;
                    }
                    it.had_error = true;
                }

                it.short_name = name;
                it.full_name  = full_name;
                it.descend_into_directory = false;

                is_dir := S_ISDIR(stats.st_mode);
                if is_dir {
                    if (name != ".") && (name != "..") {
                        it.descend_into_directory = recursive;
                        if visit_directories  {
                            it.is_directory = true;
                            it.filetime = timespec_to_filetime(stats.st_mtime);
                            #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                            `it_index += 1;
                        }
                    }

                    if it.descend_into_directory  array_add(*directories, copy_string(full_name));
                } else {
                    if visit_files {
                        it.is_directory = false;
                        it.filetime = timespec_to_filetime(stats.st_mtime);

                        #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                        `it_index += 1;
                    }
                }
            }

            entry = readdir(dirp);
        }
    }
}

#scope_file

test :: () {
    context.logger = albert_logger;

    for bfs_visit_files(join(#filepath), true) {
        print("it = %, it_index = %\n", it, it_index);
        log("Hello");
    }

    print("file tests passed\n");
}

#run test();

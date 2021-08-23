#scope_file
Posix :: #import "POSIX";
#scope_export

for_expansion :: (using iter: *VisitFileIter, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    directories: [..] string;
    array_add(*directories, copy_string(dir_name));

    defer {
        for directories free(it);
        array_reset(*directories);
    };

    `it : File_Visit_Info = ---;
    `it_index : void;

    cursor := 0;
    while cursor < directories.count {
        dir_name := directories[cursor];
        cursor += 1;

        dirp := Posix.opendir(temp_c_string(dir_name));
        if !dirp {
            if cursor != 1  continue;

            error := Posix.errno();
            log_error("Unable to open directory'%': %.\n", dir_name, error);
            break; // FAILURE
        }
        defer Posix.closedir(dirp);

        entry := Posix.readdir(dirp);
        while entry != null {
            it.is_symlink = (entry.d_type == Posix.DT_LNK);
            if follow_symlinks || !it.is_symlink {
                name := to_string(entry.d_name.data);

                full_name := join(dir_name, "/", name);
                defer free(full_name);

                it.had_error = false;
                stats: Posix.stat_t;
                ret := Posix.stat(temp_c_string(full_name), *stats);
                if ret != 0 {
                    error := Posix.errno();
                    log_error("Unable to stat file '%': %.\n", full_name, error);
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
                            it.filetime = timespec_to_filetime(stats.st_mtime);
                            #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                        }
                    }

                    if it.descend_into_directory  array_add(*directories, copy_string(full_name));
                } else {
                    if visit_files {
                        it.is_directory = false;
                        it.filetime = timespec_to_filetime(stats.st_mtime);

                        #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                    }
                }
            }

            entry = Posix.readdir(dirp);
        }
    }
}

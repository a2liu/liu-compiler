for_expansion :: (using iter: *VisitFileIter, body: Code, flags: For_Flags) #expand {
    #assert(!flags);

    directories: [..] string;
    array_add(*directories, copy_string(dir_name));
    defer {
        for directories free(it);
        array_reset(*directories);
    }

    `it: File_Visit_Info = ---;
    `it_index : void;
    it.is_symlink = false;
    it.had_error = false;

    cursor := 0;
    while cursor < directories.count {
        dir_name := directories[cursor];
        cursor += 1;

        mark := get_temporary_storage_mark();
        wildcard_name := utf8_to_wide(tprint("%/*", dir_name));

        find_data: WIN32_FIND_DATAW = ---;
        handle := FindFirstFileW(wildcard_name, *find_data);

        set_temporary_storage_mark(mark);

        if handle == INVALID_HANDLE_VALUE {
            if cursor != 1  continue;

            error := GetLastError();
            log_error("Unable to open directory'%': %.\n", dir_name, error);
            break;
        }

        while true {
            // Using temp storage here might break user code in surprising ways
            // if they also try to use temp storage in the procedure.
            name := wide_to_utf8(find_data.cFileName.data, allocator = null, null);
            full_name := join(dir_name, "/", name);
            defer { free(name); free(full_name); }

            it.short_name             = name;
            it.full_name              = full_name;
            it.descend_into_directory = false;

            if find_data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY {
                if (name != ".") && (name != "..") {
                    it.descend_into_directory = recursive;
                    if visit_directories {
                        it.is_directory = true;
                        it.filetime = FILETIME_to_filetime(find_data.ftLastWriteTime);

                        #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                    }

                    if it.descend_into_directory  array_add(*directories, copy_string(full_name));
                }
            } else {
                if visit_files {
                    it.is_directory = false;
                    it.filetime = FILETIME_to_filetime(find_data.ftLastWriteTime);

                    #insert (break = { cursor = directories.count; break; }, continue = continue) body;
                }
            }

            success := FindNextFileW(handle, *find_data);
            if !success break;
        }

        FindClose(handle);
    }
}

#scope_file
#import "Windows";
#import "Windows_Utf8";

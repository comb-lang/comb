package utils

import "core:os"
import "core:path/filepath"

CompilerFile :: struct {
    code:      string,
    file_path: string,
    dir_path:  string,
}

FilesCache :: struct {
    files:     []CompilerFile,
    files_map: map[string]^CompilerFile,
}

empty_files_cache :: proc(a: ^Arena) -> FilesCache {
    return FilesCache{arena_make(a, []CompilerFile, 0, resizable = true), nil}
}

cleanup_files_cache :: proc(c: FilesCache) {
    fix_resizable_dynamic(c.files)
    delete(c.files_map)
}

@(private = "file")
add_file :: proc(c: ^FilesCache, absolute_path: string, code: string) -> ^CompilerFile {
    append_dynamic(&c.files, CompilerFile{code, absolute_path, filepath.dir(absolute_path)})
    file_ref := &c.files[len(c.files) - 1]
    c.files_map[absolute_path] = file_ref
    return file_ref
}

read_file :: proc(c: ^FilesCache, absolute_path: string) -> (^CompilerFile, os.Error) {
    if file_ref, exists := c.files_map[absolute_path]; exists {
        return file_ref, nil
    }
    data, data_err := os.read_entire_file(absolute_path, context.allocator)
    if data_err != nil {
        return nil, data_err
    }
    return add_file(c, absolute_path, string(data)), nil
}

set_file :: proc(c: ^FilesCache, absolute_path: string, new_contents: string) -> ^CompilerFile {
    if file_ref, exists := c.files_map[absolute_path]; exists {
        file_ref.code = new_contents
        return file_ref
    } else {
        return add_file(c, absolute_path, new_contents)
    }
}

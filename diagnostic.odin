package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "utils"

FilesCache :: struct {
    files:     []CompilerFile,
    files_map: map[string]^CompilerFile,
}

empty_files_cache :: proc(a: ^utils.Arena) -> FilesCache {
    return FilesCache{utils.arena_make(a, []CompilerFile, 0, resizable = true), nil}
}

cleanup_files_cache :: proc(c: FilesCache) {
    utils.fix_resizable_dynamic(c.files)
    delete(c.files_map)
}

read_file :: proc(c: ^FilesCache, absolute_path: string) -> (^CompilerFile, os.Error) {
    file_ref, exists := c.files_map[absolute_path]
    if exists {
        return file_ref, nil
    }
    data, data_err := os.read_entire_file(absolute_path, context.allocator)
    if data_err != nil {
        return nil, data_err
    }
    utils.append_dynamic(
        &c.files,
        CompilerFile{string(data), absolute_path, filepath.dir(absolute_path)},
    )
    file_ref = &c.files[len(c.files) - 1]
    return file_ref, nil
}

DiagnosticReporter :: struct {
    io:        utils.Pipe(io.Writer),
    number_of: [DiagnosticType]uint,
}

Pos :: struct {
    index: uint,
    file:  ^CompilerFile,
}

unknown_pos :: Pos{max(uint), nil}

diagnostic_header :: proc(r: ^DiagnosticReporter, pos: Pos, type: DiagnosticType) -> io.Writer {
    w := type == .Error ? r.io.stderr : r.io.stdout
    if r.number_of[.Error] + r.number_of[.Warning] == 0 {
        io.write_byte(w, '\n')
    }
    r.number_of[type] += 1
    // TODO: use bold text for header
    switch type {
    case .Error:
        io.write_string(w, "Error")
    case .Warning:
        io.write_string(w, "Warning")
    case:
        panic("Unreachable")
    }
    io.write_string(w, " compiling")
    if pos != unknown_pos {
        fmt.wprintf(w, " %v", pos, flush = false)
    }
    io.write_byte(w, '\n')
    return w
}

diagnostic_footer :: proc(w: io.Writer) {
    io.write_string(w, "\n\n")
    io.flush(w)
}

DiagnosticType :: enum {
    Error,
    Warning,
}

CompilerFile :: struct {
    code:      string,
    file_path: string,
    dir_path:  string,
}

// Set the position to `unknown_pos` to not have a position for the error message
diagnostic :: proc(
    r: ^DiagnosticReporter,
    position: Pos,
    message_fmt: string,
    message_args: ..any,
    type: DiagnosticType = .Error,
    loc := #caller_location,
) {
    when utils.debug_diagnostics {
        print_call(loc, "diagnostic")
    }
    w := diagnostic_header(r, position, type)
    fmt.wprintf(w, message_fmt, ..message_args)
    diagnostic_footer(w)
}

/*
err :: proc(
    s: ^CheckerState,
    position: Pos,
    message_fmt: string,
    message_args: ..any,
    loc := #caller_location,
) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_errors += 1
    diagnostic(
        s.stderr,
        s.files.file[:len(s.files)],
        position,
        message_fmt,
        ..message_args,
        type = .Error,
        newline_before = !diagnostic_before,
        newline_after = true,
        loc = loc,
    )
}

warn :: proc(
    s: ^CheckerState,
    position: Pos,
    message_fmt: string,
    message_args: ..any,
    loc := #caller_location,
) {
    diagnostic_before :=
        s.diagnostics_info.number_of_errors + s.diagnostics_info.number_of_warnings > 0
    s.diagnostics_info.number_of_warnings += 1
    diagnostic(
        s.stderr,
        s.files.file[:len(s.files)],
        position,
        message_fmt,
        ..message_args,
        type = "Warning",
        newline_before = !diagnostic_before,
        newline_after = true,
        loc = loc,
    )
}
*/

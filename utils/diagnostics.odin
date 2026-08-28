package utils

import "core:fmt"
import "core:io"

DiagnosticReporter :: struct {
    data:              rawptr,
    has_errors:        proc(data: rawptr) -> bool,

    // Once the consumer has finished writing the contents of the diagnostic, it should call `io.close` on the returned `io.Writer`
    diagnostic_header: proc(
        data: rawptr,
        pos: RangeOrFile,
        type: DiagnosticType,
        loc := #caller_location,
    ) -> io.Writer,
}

StandardDiagnosticReporter :: struct {
    io:        Pipe(io.Writer),
    number_of: [DiagnosticType]uint,
}

Range :: struct {
    start:  uint,
    length: DebugValue(uint),
    file:   ^CompilerFile,
}

RangeOrFile :: union #no_nil {
    Range,
    ^CompilerFile,
}

Pos :: struct {
    index: uint,
    file:  ^CompilerFile,
}

write_file :: proc(w: io.Writer, f: ^CompilerFile) {
    io.write_byte(w, '`')
    io.write_string(w, f.file_path)
    io.write_byte(w, '`')
}

write_pos :: proc(w: io.Writer, pos: Pos, loc := #caller_location) {
    when ODIN_DEBUG {
        call(loc, "write_pos", "")
    }
    write_file(w, pos.file)
    p := get_pos(pos)
    p.line += 1
    p.col += 1
    fmt.wprintf(w, " (%d:%d)", p.line, p.col, flush = false)
}

write_range :: proc(w: io.Writer, range: Range, loc := #caller_location) {
    when ODIN_DEBUG {
        call(loc, "write_range", "")
    }
    write_file(w, range.file)
    r := get_range(
        Range{range.start, update_debug_value(range.length, range.length.v - 1), range.file},
    )
    r.start.line += 1
    r.start.col += 1
    r.end.line += 1
    r.end.col += 1
    if r.start == r.end {
        fmt.wprintf(w, " (%d:%d)", r.start.line, r.start.col, flush = false)
    } else {
        fmt.wprintf(
            w,
            " (%d:%d - %d:%d)",
            r.start.line,
            r.start.col,
            r.end.line,
            r.end.col,
            flush = false,
        )
    }
}

standard_diagnostic_header :: proc(
    data: rawptr,
    pos: RangeOrFile,
    type: DiagnosticType,
    loc := #caller_location,
) -> io.Writer {
    when ODIN_DEBUG {
        call(loc, "standard_diagnostic_header", "")
    }
    r := cast(^StandardDiagnosticReporter)data
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
    fmt.wprintf(w, " compiling %v", pos, flush = false)
    io.write_byte(w, '\n')
    return override_close_handler(w, nil, proc(d: ^OverriddenCloseHandlerStreamData) {
        io.write_byte(d.original_stream, '\n')
        io.flush(d.original_stream)
        d.original_stream = panic_stream
    })
}

DiagnosticType :: enum {
    Error,
    Warning,
}

standard_has_errors :: proc(data: rawptr) -> bool {
    r := cast(^StandardDiagnosticReporter)data
    return r.number_of[.Error] > 0
}

diagnostic :: proc(
    r: DiagnosticReporter,
    range: RangeOrFile,
    message_fmt: string,
    message_args: ..any,
    type: DiagnosticType = .Error,
    loc := #caller_location,
) {
    call(loc, "diagnostic", "", enable_debug = debug_diagnostics)
    w := r.diagnostic_header(r.data, range, type)
    fmt.wprintf(w, message_fmt, ..message_args, flush = false)
    io.write_byte(w, '\n')
    io.flush(w)
    io.close(w)
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

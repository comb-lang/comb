package utils

import "core:fmt"
import "core:io"

DiagnosticReporter :: struct {
    data:              rawptr,
    has_errors:        proc(data: rawptr) -> bool,
    // Once the consumer has finished writing the contents of the diagnostic, it should call `io.close` on the returned `io.Writer`
    diagnostic_header: proc(
        data: rawptr,
        // Set to `unknown_pos` to not have a position for the diagnostic
        pos: Pos,
        type: DiagnosticType,
    ) -> io.Writer,
}

StandardDiagnosticReporter :: struct {
    io:        Pipe(io.Writer),
    number_of: [DiagnosticType]uint,
}

Pos :: struct {
    index: uint, // set index to `max(uint)` if the index is not known
    file:  ^CompilerFile,
}

standard_diagnostic_header :: proc(data: rawptr, pos: Pos, type: DiagnosticType) -> io.Writer {
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
        io.write_string(d.original_stream, "\n\n")
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
    position: Pos,
    message_fmt: string,
    message_args: ..any,
    type: DiagnosticType = .Error,
    loc := #caller_location,
) {
    when debug_diagnostics {
        print_call(loc, "diagnostic")
    }
    w := r.diagnostic_header(r.data, position, type)
    fmt.wprintf(w, message_fmt, ..message_args)
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

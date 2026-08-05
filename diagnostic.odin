package main

import "core:fmt"
import "core:io"
import "utils"

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
    io:        utils.Pipe(io.Writer),
    number_of: [DiagnosticType]uint,
}

Pos :: struct {
    index: uint,
    file:  ^utils.CompilerFile,
}

unknown_pos :: Pos{max(uint), nil}

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
    when utils.debug_diagnostics {
        print_call(loc, "diagnostic")
    }
    r := cast(^StandardDiagnosticReporter)data
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

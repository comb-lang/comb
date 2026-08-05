package lsp

import "../utils"
import "core:io"

LspDiagnosticReporterData :: struct {
    diagnostics: []Diagnostic,
}

lsp_diagnostic_reporter :: proc(data: ^LspDiagnosticReporterData) -> utils.DiagnosticReporter {
    return utils.DiagnosticReporter{data, has_errors, diagnostic_header}
}

@(private = "file")
has_errors :: proc(data: rawptr) -> bool {
    d := cast(^LspDiagnosticReporterData)data
    for d in d.diagnostics {
        if d.severity == .Error {
            return true
        }
    }
    return false
}

@(private = "file")
diagnostic_header :: proc(data: rawptr, pos: utils.Pos, type: utils.DiagnosticType) -> io.Writer {
    panic("todo")
}

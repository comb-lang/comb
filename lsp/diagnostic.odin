package main

import "../utils"

LspDiagnosticHandlerData :: struct {
    diagnostics: []Diagnostic,
}

lsp_diagnostic_handler :: proc(data: ^LspDiagnosticHandlerData) -> utils.DiagnosticReporter {
    return utils.DiagnosticReporter{}
}

lsp_diagnostic_header :: proc()

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
    d := cast(^LspDiagnosticReporterData)data
    message_writer := utils.make_builder(&lsp_state.a)
    return utils.override_close_handler(
        message_writer,
        new_clone(DiagnosticCloseData{pos, type, &d.diagnostics}),
        proc(data: ^utils.OverriddenCloseHandlerStreamData) {
            d := cast(^DiagnosticCloseData)data.new_data

            p: utils.Position = ---
            if d.pos.index == max(uint) {
                p = utils.Position{1, 1}
            } else {
                p = utils.get_position(d.pos)
            }

            severity: Severity = ---
            switch d.type {
            case .Error:
                severity = .Error
            case .Warning:
                severity = .Warning
            case:
                panic("Unreachable")
            }

            utils.append_dynamic(
                d.diagnostics,
                Diagnostic {
                    Range{p, p},
                    severity,
                    d.pos.file.file_path,
                    utils.finish_building(data.original_stream),
                },
            )
        },
    )
}

DiagnosticCloseData :: struct {
    pos:         utils.Pos,
    type:        utils.DiagnosticType,
    diagnostics: ^[]Diagnostic,
}

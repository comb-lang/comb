package lsp

import "../compiler"
import "../utils"
import "core:io"

lsp_name :: "Programming language LSP" // TODO

LspDiagnosticReporterData :: struct {
    diagnostics:                map[uint][]Diagnostic, // The key is the file index
    diagnostics_include_errors: bool,
}

lsp_diagnostic_reporter :: utils.DiagnosticReporter{nil, has_errors, diagnostic_header}

@(private = "file")
has_errors :: proc(_: rawptr) -> bool {
    return lsp_state.diagnostics.diagnostics_include_errors
}

@(private = "file")
diagnostic_header :: proc(_: rawptr, pos: utils.Pos, type: utils.DiagnosticType) -> io.Writer {
    message_writer := utils.make_builder(&lsp_state.temp_arena)
    return utils.override_close_handler(
        message_writer,
        new_clone(DiagnosticCloseData{pos, type}),
        proc(data: ^utils.OverriddenCloseHandlerStreamData) {
            d := cast(^DiagnosticCloseData)data.new_data

            p: utils.Position = ---
            if d.pos.index == max(uint) {
                p = utils.Position{0, 0}
            } else {
                p = utils.get_position(d.pos)
            }

            severity: Severity = ---
            switch d.type {
            case .Error:
                lsp_state.diagnostics.diagnostics_include_errors = true
                severity = .Error
            case .Warning:
                severity = .Warning
            case:
                panic("Unreachable")
            }

            file_index := uint(compiler.get_file_index(lsp_state.files_cache.files, d.pos.file))
            if file_index not_in lsp_state.diagnostics.diagnostics {
                lsp_state.diagnostics.diagnostics[file_index] = utils.arena_make(
                    &lsp_state.temp_arena,
                    []Diagnostic,
                    0,
                    resizable = true,
                )
            }
            utils.append_dynamic(
                &lsp_state.diagnostics.diagnostics[file_index],
                Diagnostic {
                    Range{p, p},
                    severity,
                    lsp_name,
                    utils.finish_building(data.original_stream),
                },
            )
        },
    )
}

DiagnosticCloseData :: struct {
    pos:  utils.Pos,
    type: utils.DiagnosticType,
}

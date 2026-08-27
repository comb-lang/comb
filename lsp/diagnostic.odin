package lsp

import "../compiler"
import "../utils"
import "core:io"
import "core:strings"

lsp_name :: "Comb LSP"

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
diagnostic_header :: proc(
    _: rawptr,
    pos: utils.RangeOrFile,
    type: utils.DiagnosticType,
    loc := #caller_location,
) -> io.Writer {
    message_writer := utils.make_builder(&lsp_state.temp_arena)
    return utils.override_close_handler(
        message_writer,
        new_clone(DiagnosticCloseData{pos, type}),
        proc(data: ^utils.OverriddenCloseHandlerStreamData) {
            d := cast(^DiagnosticCloseData)data.new_data

            range: utils.ReadableRange = ---
            file: ^utils.CompilerFile = ---
            switch pos in d.pos {
            case ^utils.CompilerFile:
                range = utils.ReadableRange{utils.ReadablePos{0, 0}, utils.ReadablePos{0, 0}}
                file = pos
            case utils.Range:
                range = utils.get_range(pos)
                file = pos.file
            case:
                panic("Unreachable")
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

            file_index := uint(compiler.get_file_index(lsp_state.files_cache.files, file))
            if file_index not_in lsp_state.diagnostics.diagnostics {
                lsp_state.diagnostics.diagnostics[file_index] = utils.arena_make(
                    &lsp_state.temp_arena,
                    []Diagnostic,
                    0,
                    resizable = true,
                )
            }
            message := utils.finish_building(data.original_stream)
            assert(strings.ends_with(message, "\n"))
            utils.append_dynamic(
                &lsp_state.diagnostics.diagnostics[file_index],
                Diagnostic{range, severity, lsp_name, message[:len(message) - 1]},
            )
        },
    )
}

DiagnosticCloseData :: struct {
    pos:  utils.RangeOrFile,
    type: utils.DiagnosticType,
}

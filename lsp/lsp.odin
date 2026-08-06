package lsp

// TODO: Add test(s) for the LSP implementation

import "../compiler"
import "../utils"
import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:strings"
import "core:time"

@(private = "package")
LspState :: struct {
    files_cache:    utils.FilesCache,
    diagnostics:    LspDiagnosticReporterData,
    entry_point:    ^utils.CompilerFile,
    reader:         bufio.Reader,
    writer:         io.Writer,
    temp_arena:     utils.Arena, // Cleared after every iteration of the main loop
    lifetime_arena: utils.Arena, // Only freed when the LSP exits
    // The `context.temp_allocator` is also freed after every iteration of the main loop
}

@(private = "package")
uri_prefix :: "file://"

@(private = "package")
from_uri :: proc(uri: string) -> string {
    // TODO: I think there is an unnamed prefix which has to be supported
    assert(uri[:len(uri_prefix)] == uri_prefix)
    out, _ := strings.replace_all(uri[len(uri_prefix):], "%20", " ", context.temp_allocator)
    return out
}

@(private = "package")
to_uri :: proc(path: string) -> string {
    replaced, _ := strings.replace_all(path, " ", "%20", context.temp_allocator)
    return strings.join([]string{uri_prefix, path}, "", context.temp_allocator)
}

@(private = "package")
lsp_state: LspState

run_lsp :: proc() {
    lsp_state.writer = io.Writer(os.to_stream(os.stdout))

    temp_dir, err := os.temp_dir(context.allocator)
    if err != nil {
        fmt.eprintfln("Failed get temporary dir: %v", err)
        os.exit(1)
    }
    defer delete(temp_dir)

    debug_file, err2 := os.create_temp_file(temp_dir, "lsp_logs_")
    if err2 != nil {
        fmt.eprintfln("Failed to create temporary file: %v", err2)
        os.exit(1)
    }
    defer os.close(debug_file)

    debug_writer_buffer: [1024]byte
    debug_writer: bufio.Writer
    bufio.writer_init_with_buf(&debug_writer, os.to_stream(debug_file), debug_writer_buffer[:])
    utils.debug_writer = bufio.writer_to_writer(&debug_writer)
    defer io.flush(utils.debug_writer)

    reader_buf: [1024]byte
    bufio.reader_init_with_buf(&lsp_state.reader, io.Reader(os.to_stream(os.stdin)), reader_buf[:])

    lsp_state.files_cache = utils.empty_files_cache(&lsp_state.lifetime_arena)

    context.assertion_failure_proc = proc(
        prefix: string,
        message: string,
        loc: runtime.Source_Code_Location,
    ) -> ! {
        fmt.wprintfln(utils.debug_writer, "%v: %s: %s", loc, prefix, message)
        os.exit(1)
    }

    fmt.wprintfln(utils.debug_writer, "Lsp started at %v", time.now())

    initialize_request := receive_request().(LspInitialize)
    supports_utf8 := false
    for encoding_kind in initialize_request.params.capabilities.general.position_encodings {
        if encoding_kind == utf8 {
            supports_utf8 = true
        }
    }
    if !supports_utf8 {
        fmt.wprintln(utils.debug_writer, "Warning: LSP client does not support utf8 encodings")
    }
    send_response(
        InitializeResponse {
            ResponseData{jsonrpc, initialize_request.id},
            InitializeResult{ServerCapabilities{utf8, .Full}, server_info},
        },
    )
    _ = receive_request().(LspInitialized)
    fmt.wprintln(utils.debug_writer, "Starting main loop...")

    for {
        message := receive_request()
        fmt.wprintfln(utils.debug_writer, "Received message: %v", message)
        switch m in message {
        case LspInitialize, LspInitialized:
            panic("Unexpected initialize message while running LSP")
        case Exit:
            panic("Unexpected exit message while running LSP")
        case Shutdown:
            utils.cleanup_arena(&lsp_state.temp_arena, expect_empty = false, delete_blocks = true)
            utils.cleanup_arena(
                &lsp_state.lifetime_arena,
                expect_empty = false,
                delete_blocks = true,
            )
            free_all(context.temp_allocator)
            send_response(ShutdownResponse{ResponseData{jsonrpc, m.id}, nil})
            _ = receive_request().(Exit)
            return
        case DidSaveTextDocumentNotification:
        case DidOpenTextDocumentNotification:
            lsp_state.entry_point = utils.set_file(
                &lsp_state.files_cache,
                from_uri(m.params.text_document.uri),
                m.params.text_document.text,
            )
        case DidChangeTextDocumentNotification:
            assert(len(m.params.content_changes) == 1)
            lsp_state.entry_point = utils.set_file(
                &lsp_state.files_cache,
                from_uri(m.params.text_document.uri),
                m.params.content_changes[0].text,
            )
        }

        if lsp_state.entry_point == nil {
            fmt.wprintln(utils.debug_writer, "Skipping check because lsp_state.entry_point == nil")
            continue
        }

        lsp_state.diagnostics.diagnostics_include_errors = false
        fmt.wprintln(utils.debug_writer, "Iterating diagnostics")
        for key, diagnostics in lsp_state.diagnostics.diagnostics {
            lsp_state.diagnostics.diagnostics[key] = utils.arena_make(
                &lsp_state.temp_arena,
                []Diagnostic,
                0,
                resizable = true,
            )
        }
        fmt.wprintln(utils.debug_writer, "Finished iterating diagnostics")

        compiler.parse_and_check(
            &lsp_state.temp_arena,
            &lsp_state.files_cache,
            lsp_state.entry_point,
            "",
            utils.Pipe(io.Stream){utils.debug_writer, utils.debug_writer},
            compiler.NeverExitEarly{}, // TODO: Exit early if the source code is edited
            lsp_diagnostic_reporter,
        )
        fmt.wprintln(utils.debug_writer, "Finished parse and check")
        for file_index, diagnostics in lsp_state.diagnostics.diagnostics {
            fmt.wprintfln(
                utils.debug_writer,
                "Responding with diagnostics for file index %d",
                file_index,
            )
            send_response(
                PublishDiagnosticNotification {
                    Notification{jsonrpc, "textDocument/publishDiagnostics"},
                    PublishDiagnosticParams {
                        to_uri(lsp_state.files_cache.files[file_index].file_path),
                        diagnostics,
                    },
                },
            )
            utils.fix_resizable_dynamic(diagnostics)
        }

        utils.cleanup_arena(&lsp_state.temp_arena, expect_empty = false, delete_blocks = false)
        free_all(context.temp_allocator)
    }
}

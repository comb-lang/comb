package lsp

import "../utils"
import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"
import "core:time"

LspState :: struct {
    files_cache:  utils.FilesCache,
    entry_point:  ^utils.CompilerFile,
    reader:       bufio.Reader,
    writer:       io.Writer,
    debug_writer: io.Writer,
    a:            utils.Arena,
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

    reader_buf: [1024]byte
    bufio.reader_init_with_buf(&lsp_state.reader, io.Reader(os.to_stream(os.stdin)), reader_buf[:])

    lsp_state.files_cache = utils.empty_files_cache(&lsp_state.a)
    lsp_state.debug_writer = bufio.writer_to_writer(&debug_writer)

    context.assertion_failure_proc = proc(
        prefix: string,
        message: string,
        loc: runtime.Source_Code_Location,
    ) -> ! {
        fmt.wprintfln(lsp_state.debug_writer, "%v: %s: %s", loc, prefix, message)
        os.exit(1)
    }

    fmt.wprintfln(lsp_state.debug_writer, "Lsp started at %v", time.now())

    initialize_request := receive_request().(LspInitialize)
    send_response(
        InitializeResponse {
            ResponseData{jsonrpc, initialize_request.id},
            InitializeResult{ServerCapabilities{.Full}, server_info},
        },
    )
    _ = receive_request().(LspInitialized)
    fmt.wprintln(lsp_state.debug_writer, "Starting main loop...")

    for {
        message := receive_request()
        fmt.wprintfln(lsp_state.debug_writer, "Received message: %v", message)
        switch m in message {
        case LspInitialize, LspInitialized:
            panic("Unexpected initialize message while running LSP")
        case DidOpenTextDocumentNotification:
            lsp_state.entry_point = utils.set_file(
                &lsp_state.files_cache,
                m.params.text_document.uri,
                m.params.text_document.text,
            )
        case DidChangeTextDocumentNotification:
            assert(len(m.params.content_changes) == 1)
            lsp_state.entry_point = utils.set_file(
                &lsp_state.files_cache,
                m.params.text_document.uri,
                m.params.content_changes[0].text,
            )
        }
        // TODO: Compile
        send_response(
            PublishDiagnosticNotification {
                Notification{jsonrpc, "textDocument/publishDiagnostics"},
                PublishDiagnosticParams{},
            },
        )

    }
}

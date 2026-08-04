package lsp

import "../utils"
import "base:runtime"
import "core:bufio"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:os"
import "core:time"

LspState :: struct {
    reader:       bufio.Reader,
    writer:       io.Writer,
    debug_writer: io.Writer,
    a:            utils.Arena,
}

@(private = "file")
lsp_state: LspState

TODO :: struct {}

LspMessage :: union {
    LspInitializeMessage,
}

LspInitializeMessage :: struct {}

ServerCapabilities :: struct {}

encode_message :: proc(data: any) {
    builder := utils.make_builder(&lsp_state.a)
    defer utils.delete_builder(builder)
    opt := json.Marshal_Options{}
    err := json.marshal_to_writer(builder, data, &opt)
    if err != nil {
        fmt.wprintfln(lsp_state.debug_writer, "Failed to marshal: %v", err)
        os.exit(1)
    }
    json_str := utils.finish_building(builder)
    fmt.wprintf(lsp_state.writer, "Content-Length: %d\r\n\r\n%s", len(json_str), json_str)
}

receive_message :: proc() -> LspMessage {
    LspInitialMessage :: struct {
        method: string,
    }

    utils.expect_string2(&lsp_state.reader, "Content-Length: ")
    content_length := utils.parse_uint(&lsp_state.reader)
    utils.expect_string2(&lsp_state.reader, "\r\n\r\n")
    content := make([]byte, content_length)
    n := 0
    for n < len(content) {
        num_read, err := bufio.reader_read(&lsp_state.reader, content[n:])
        if err != nil {
            utils.panicf("err: %v", err)
        }
        assert(num_read > 0)
        n += num_read
    }
    fmt.wprintfln(lsp_state.debug_writer, "Got content ```\n%s\n```", content)

    raw := LspInitialMessage{}
    err2 := json.unmarshal(content, &raw)
    assert(err2 == nil)

    switch raw.method {
    case "initialize":
        out := LspInitializeMessage{}
        err3 := json.unmarshal(content, &out)
        assert(err3 == nil)
        return out
    case:
        fmt.wprintfln(lsp_state.debug_writer, "TODO: Handle method %q", raw.method)
        return nil
    }
}

run_lsp :: proc() {
    writer := io.Writer(os.to_stream(os.stdout))

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

    reader: bufio.Reader
    reader_buf: [1024]byte
    bufio.reader_init_with_buf(&reader, io.Reader(os.to_stream(os.stdin)), reader_buf[:])

    lsp_state = LspState{reader, writer, bufio.writer_to_writer(&debug_writer), utils.Arena{}}

    context.assertion_failure_proc = proc(
        prefix: string,
        message: string,
        loc: runtime.Source_Code_Location,
    ) -> ! {
        fmt.wprintfln(lsp_state.debug_writer, "%v: %s: %s", loc, prefix, message)
        os.exit(1)
    }

    fmt.wprintfln(lsp_state.debug_writer, "Lsp started at %v", time.now())

    initialise_message := receive_message().(LspInitializeMessage)


    for {
        message := receive_message()
        fmt.wprintfln(lsp_state.debug_writer, "Got message: %v", message)
        switch m in message {
        case LspInitializeMessage:
            panic("Unexpected initialize message while running LSP")
        }
    }
}

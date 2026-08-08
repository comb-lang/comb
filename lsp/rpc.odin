package lsp

import "../utils"
import "core:bufio"
import "core:encoding/json"
import "core:fmt"
import "core:os"

Request :: union {
    LspInitialized,
    LspInitialize,
    DidOpenTextDocumentNotification,
    DidChangeTextDocumentNotification,
    DidSaveTextDocumentNotification,
    Shutdown,
    Exit,
}

ResponseData :: struct {
    jsonrpc: string,
    id:      union {
        int,
    },
}

jsonrpc :: "2.0"

Notification :: struct {
    jsonrpc: string,
    method:  string,
}

TextDocumentItem :: struct {
    uri:         string,
    language_id: string `json:"languageId"`,
    version:     int,
    text:        string,
}

TextDocumentIdentifier :: struct {
    uri: string,
}

DidOpenTextDocumentNotification :: struct {
    using _: Notification,
    params:  DidOpenTextDocumentParams,
}

DidChangeTextDocumentNotification :: struct {
    using _: Notification,
    params:  DidChangeTextDocumentParams,
}

DidSaveTextDocumentNotification :: struct {}

Shutdown :: struct {
    using _: RequestData,
}

Exit :: struct {}

DidChangeTextDocumentParams :: struct {
    text_document:   TextDocumentIdentifier `json:"textDocument"`,
    content_changes: []TextDocumentContentChangeEvent `json:"contentChanges"`,
}

TextDocumentContentChangeEvent :: struct {
    // The new text of the whole document.
    text: string,
}

DidOpenTextDocumentParams :: struct {
    text_document: TextDocumentItem `json:"textDocument"`,
}

TextDocumentPositionParams :: struct {
    text_document: TextDocumentIdentifier `json:"textDocument"`,
    position:      utils.Position,
}

RequestData :: struct {
    id: int,
}

Response :: union {
    InitializeResponse,
    PublishDiagnosticNotification,
    ShutdownResponse,
}

ShutdownResponse :: struct {
    using _: ResponseData,
    result:  union {}, // Should always be `null` when marshalled into JSON
}

PublishDiagnosticNotification :: struct {
    using _: Notification,
    params:  PublishDiagnosticParams,
}

PublishDiagnosticParams :: struct {
    uri:         string,
    diagnostics: []Diagnostic,
}

Severity :: enum {
    Error       = 1,
    Warning     = 2,
    Information = 3,
    Hint        = 4,
}

Range :: struct {
    start: utils.Position,
    end:   utils.Position,
}

Diagnostic :: struct {
    range:    Range,
    severity: Severity,
    source:   string,
    message:  string,
}

InitializeResponse :: struct {
    using _: ResponseData,
    result:  InitializeResult,
}

InitializeResult :: struct {
    capabilities: ServerCapabilities,
    server_info:  Info `json:"serverInfo"`,
}

LspInitialize :: struct {
    using _: RequestData,
    params:  InitializeParams,
}

GeneralClientCapabilities :: struct {
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/#generalClientCapabilities
    position_encodings: []PositionEncodingKind `json:"positionEncodings"`,
}

ClientCapabilities :: struct {
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/#clientCapabilities
    general: GeneralClientCapabilities,
}

InitializeParams :: struct {
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/#initializeParams
    client_info:  Info `json:"clientInfo"`,
    capabilities: ClientCapabilities,
}
LspInitialized :: struct {}

TextDocumentSync :: enum {
    None        = 0,
    Full        = 1,
    Incremental = 2,
}

Info :: struct {
    name:    string,
    version: string,
}

// TODO: Update server version
@(private = "package")
server_info :: Info{"Comb LSP", "0.0.1"}

// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/#positionEncodingKind
@(private = "package")
PositionEncodingKind :: distinct string

@(private = "package")
utf8: PositionEncodingKind : "utf-8"

@(private = "package")
utf16: PositionEncodingKind : "utf-16"

@(private = "package")
utf32: PositionEncodingKind : "utf-32"

@(private = "package")
ServerCapabilities :: struct {
    // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.18/specification/#serverCapabilities
    position_encoding:  PositionEncodingKind `json:"positionEncoding"`,
    text_document_sync: TextDocumentSync `json:"textDocumentSync"`,
}

@(private = "package")
send_response :: proc(data: Response) {
    builder := utils.make_builder(&lsp_state.temp_arena)
    defer utils.delete_builder(builder)
    opt := json.Marshal_Options{}
    err := json.marshal_to_writer(builder, data, &opt)
    if err != nil {
        fmt.wprintfln(utils.debug_writer, "Failed to marshal: %v", err)
        os.exit(1)
    }
    json_str := utils.finish_building(builder)
    fmt.wprintf(lsp_state.writer, "Content-Length: %d\r\n\r\n%s", len(json_str), json_str)
    fmt.wprintf(utils.debug_writer, "Sent message ```\n%s\n```", json_str)
}

receive_request :: proc() -> Request {
    LspInitialMessage :: struct {
        method: string,
    }

    utils.expect_string2(&lsp_state.reader, "Content-Length: ")
    content_length := utils.parse_uint(&lsp_state.reader)
    utils.expect_string2(&lsp_state.reader, "\r\n\r\n")
    content := utils.arena_make(&lsp_state.temp_arena, []byte, content_length)
    n := 0
    for n < len(content) {
        num_read, err := bufio.reader_read(&lsp_state.reader, content[n:])
        if err != nil {
            utils.panicf("err: %v", err)
        }
        assert(num_read > 0)
        n += num_read
    }
    fmt.wprintfln(utils.debug_writer, "Got content ```\n%s\n```", content)

    raw := LspInitialMessage{}
    err2 := json.unmarshal(content, &raw)
    assert(err2 == nil)

    switch raw.method {
    case "initialize":
        out := LspInitialize{}
        err3 := json.unmarshal(content, &out)
        assert(err3 == nil)
        return out
    case "textDocument/didOpen":
        out := DidOpenTextDocumentNotification{}
        err3 := json.unmarshal(content, &out)
        assert(err3 == nil)
        return out
    case "textDocument/didChange":
        out := DidChangeTextDocumentNotification{}
        err3 := json.unmarshal(content, &out)
        assert(err3 == nil)
        return out
    case "textDocument/didSave":
        return DidSaveTextDocumentNotification{}
    case "initialized":
        return LspInitialized{}
    case "shutdown":
        out := Shutdown{}
        err3 := json.unmarshal(content, &out)
        assert(err3 == nil)
        return out
    case "exit":
        return Exit{}
    case:
        fmt.wprintfln(utils.debug_writer, "TODO: Handle method %q", raw.method)
        return nil
    }
}

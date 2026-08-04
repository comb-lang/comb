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
}

ResponseData :: struct {
    jsonrpc: string,
    id:      union {
        int,
    },
}

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

Position :: struct {
    line:      uint,
    character: uint,
}

DidOpenTextDocumentNotification :: struct {
    using _: Notification,
    params:  DidOpenTextDocumentParams,
}

DidChangeTextDocumentNotification :: struct {
    using _: Notification,
    params:  DidChangeTextDocumentParams,
}

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
    position:      Position,
}

RequestData :: struct {
    id: int,
}

Response :: union {
    InitializeResponse,
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
InitializeParams :: struct {
    client_info: Info `json:"clientInfo"`,
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

// TODO: Update server info
server_info :: Info{"programming_language", "0.0.1"}

ServerCapabilities :: struct {
    text_document_sync: TextDocumentSync `json:"textDocumentSync"`,
}

send_response :: proc(data: Response) {
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
    fmt.wprintf(lsp_state.debug_writer, "Sent message ```\n%s\n```", json_str)
}

receive_request :: proc() -> Request {
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
    case "initialized":
        return LspInitialized{}
    case:
        fmt.wprintfln(lsp_state.debug_writer, "TODO: Handle method %q", raw.method)
        return nil
    }
}

package main

// This file is mostly AI generated
// TODO: Proper memory management (garbage collector?)

import "compiler"
import "core:fmt"
import "core:io"
import "core:math"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"
import "utils"
import "webserver"

RuntimeValue :: union {
    f64, // TODO: Support using i64 or u64 to increase accuracy
    bool,
    RuntimeString,
    RuntimeArray,
    RuntimeOrderedHashMap,
    RuntimeStruct,
    RuntimeSumType,
    RuntimeFunc,
    compiler.BuiltinFunction,
    compiler.CastFunction,
    SetHttpServerHandler,
    HttpServerListenAndServe,
    SetWebsocketHandler,
    SendToWebsockets,
}

get_value_type :: proc(s: InterpState, value: RuntimeValue) -> compiler.Type {
    switch v in value {
    case f64:
        if math.floor(v) != v {
            return .Float
        } else if v < 0 {
            return .Int
        } else {
            return .UInt
        }
    case bool:
        return .Bool
    case RuntimeString:
        return .String
    case RuntimeArray:
        return v.type
    case RuntimeOrderedHashMap:
        return v.type
    case RuntimeStruct:
        return v.type
    /*
    // OLD(INITIALISING STRUCTS LIKE `StructType(fields...)`)
    case compiler.StructTypeInitFunc:
        return_types := make([]compiler.Type, 1)
        return_types[0] = v.return_type
        return compiler.create_type(&s.types, compiler.FuncType{nil, return_types}).type
        */
    case RuntimeSumType:
        return v.type
    case RuntimeFunc:
        return s.checked_funcs[v.ref.index].type
    case compiler.BuiltinFunction:
        panic("TODO")
    case compiler.CastFunction:
        panic("TODO")
    case SetHttpServerHandler:
        panic("TODO")
    case HttpServerListenAndServe:
        panic("TODO")
    case SetWebsocketHandler:
        panic("TODO")
    case SendToWebsockets:
        panic("TODO")
    case:
        panic("Unreachable")
    }
}

RuntimeFunc :: struct {
    ref:         compiler.CheckedFuncRef,
    lambda_args: []RuntimeValue,
}

SetHttpServerHandler :: struct {
    server: uint,
}

HttpServerListenAndServe :: struct {
    server: uint,
}

SetWebsocketHandler :: struct {
    server: uint,
}

SendToWebsockets :: struct {
    server: uint,
}

RuntimeString :: struct {
    needs_freeing: bool,
    value:         string,
}

RuntimeArray :: struct {
    type:          compiler.Type,
    needs_freeing: bool,
    elems:         []RuntimeValue,
}

RuntimeOrderedHashMap :: struct {
    type:          compiler.Type,
    needs_freeing: bool,
    hashmap:       map[compiler.HashMapKey]RuntimeValue,
    order:         []compiler.HashMapKey,
}
RuntimeStruct :: struct {
    needs_freeing: bool,
    field_values:  []RuntimeValue,
    type:          compiler.Type,
}
RuntimeSumType :: struct {
    type:          compiler.Type,
    needs_freeing: bool,
    variant_index: u32,
    payload:       ^RuntimeValue, // May be nil
}

Frame :: struct {
    func_index: uint,
    scopes:     [dynamic][]RuntimeValue,
}

BuiltinHandler :: struct {
    data:      rawptr,
    procedure: proc(
        state: InterpState,
        f: compiler.BuiltinFunction,
        args: []RuntimeValue,
    ) -> RuntimeValue,
}

ReturnFromFunction :: struct {
    value: RuntimeValue,
}

ControlFlowOperation :: union {
    compiler.CheckedLoopControlFlow,
    ReturnFromFunction,
}

HttpServer :: struct {
    socket:            net.TCP_Socket,
    handler:           RuntimeFunc,
    websocket_handler: RuntimeFunc,
}

WebsocketConnection :: struct {
    client:      net.TCP_Socket,
    server:      uint,
    open:        bool,
    read_buffer: [dynamic]byte,
}

// Interpreter state that lasts when the program is restarted by the `-watch` flag
LongLivedInterpState :: struct {
    cache:        map[string]RuntimeValue,
    http_servers: [dynamic]HttpServer,
    websockets:   [dynamic]WebsocketConnection,
}

// Interpreter state that is reset when the program is restarted by the `-watch` flag
ShortLivedInterpState :: struct {
    types:                   compiler.Types,
    globals_without_generic: []compiler.GlobalValueWithoutGeneric,
    globals_with_generic:    []compiler.GlobalValueWithGeneric,
    checked_funcs:           []compiler.CheckedFunction,
    builtin_handler:         BuiltinHandler,
    frames:                  [dynamic]Frame,
    current_loop:            uint,
    control_flow_op:         ControlFlowOperation,
    exit_early:              compiler.EarlyExitInfo,
}

InterpState :: struct {
    using s: ^ShortLivedInterpState,
    l:       ^LongLivedInterpState,
}

/*
interpret :: proc(
    c: Checked,
    builtin_handler: BuiltinHandler,
    entry_func_ref: CheckedFuncRef,
) -> RuntimeValue {
    state := InterpState {
        c               = c,
        frames          = make([dynamic]Frame),
        builtin_handler = builtin_handler,
    }

    result := interp_execute_function2(&state, entry_func_ref, nil)
    assert(len(state.frames) == 0)
    delete(state.frames)
    return result
}
*/

interp_execute_function :: proc(s: InterpState, c: compiler.CheckedFunctionCall) -> RuntimeValue {
    fn_val := interp_eval_value(s, c.function^)
    args := make([]RuntimeValue, len(c.args))
    for arg_val, i in c.args {
        args[i] = interp_clone_value(interp_eval_value(s, arg_val))
    }

    #partial switch val in fn_val {
    /*
    // OLD(INITIALISING STRUCTS LIKE `StructType(fields...)`)
    case compiler.StructTypeInitFunc:
        return RuntimeStruct{true, args, val.return_type}
    */
    case compiler.CastFunction:
        assert(len(args) == 1)
        got_type := get_value_type(s, args[0])
        if got_type != val.type {
            panic(
                fmt.aprintf(
                    "Expected the type `%s`\nGot the type `%s`",
                    compiler.type_to_string2(
                        s.types,
                        s.globals_without_generic,
                        s.globals_with_generic,
                        val.type,
                    ),
                    compiler.type_to_string2(
                        s.types,
                        s.globals_without_generic,
                        s.globals_with_generic,
                        got_type,
                    ),
                ),
            )
        }
        out := args[0]
        delete(args)
        return out
    }

    defer {
        for &arg in args {
            interp_destroy_value(&arg)
        }
        delete(args)
    }

    #partial switch val in fn_val {
    case compiler.BuiltinFunction:
        return s.builtin_handler.procedure(s, val, args)
    case RuntimeFunc:
        return interp_execute_function2(s, val, args)
    case SetHttpServerHandler:
        assert(len(args) == 1)
        s.l.http_servers[val.server].handler = args[0].(RuntimeFunc)
        return nil
    case SetWebsocketHandler:
        assert(len(args) == 1)
        s.l.http_servers[val.server].websocket_handler = args[0].(RuntimeFunc)
        return nil
    case SendToWebsockets:
        assert(len(args) == 1)
        message := args[0].(RuntimeSumType)
        none_tag := websocket_message_variant_index(s, "None")
        text_tag := websocket_message_variant_index(s, "Text")
        binary_tag := websocket_message_variant_index(s, "Binary")
        if message.variant_index != none_tag {
            opcode := webserver.WebSocket_Opcode.Text
            if message.variant_index == binary_tag {
                opcode = .Binary
            } else if message.variant_index != text_tag {
                panic("Expected the websocket message to be a `WebSocketMessage`")
            }
            payload := transmute([]byte)message.payload.(RuntimeString).value
            for i in 0 ..< len(s.l.websockets) {
                conn := &s.l.websockets[i]
                if conn.open && conn.server == val.server {
                    webserver.send_ws_frame(conn.client, opcode, payload)
                }
            }
        }
        return nil
    case HttpServerListenAndServe:
        assert(len(args) == 0)
        server := s.l.http_servers[val.server]
        if server.handler.ref.index == max(uint) {
            panic("`listen_and_serve` called when handler has not been set")
        }
        buf: [65536]byte
        for {
            pump_websockets(s)
            // TODO: Set timeout on accept_tcp so it does not block the
            // automatic recompilation of the `-watch` flag
            client, _, accept_err := net.accept_tcp(server.socket)
            if accept_err == .Would_Block {
                if compiler.should_exit_early(s.exit_early) {
                    return nil
                }
                time.sleep(utils.wait_time)
                continue
            }
            if accept_err != nil {
                // TODO: Better error handling
                panic(fmt.aprintf("Accept error: %v", accept_err))
            }

            n, receive_err := net.recv_tcp(client, buf[:])
            if receive_err != nil {
                // TODO: Better error handling
                panic(fmt.aprintf("Receive error: %v", receive_err))
            }

            data := buf[:n]

            if webserver.is_websocket_upgrade_request(data) {
                // Successfully upgraded connections are kept open and are
                // handled by `pump_websockets`, `accept_websocket` closes the
                // client itself when the handshake fails
                accept_websocket(s, val.server, client, data)
                continue
            }

            defer net.close(client)

            request, ok := webserver.parse_http_request(data)
            if !ok {
                err := webserver.send_error(client, 400, "Bad Request")
                if err != nil {
                    // TODO: Better error handling
                    panic("Failed to send error")
                }
                continue
            }
            defer delete(request.headers)

            req_fields := make([]RuntimeValue, 2)
            req_fields[0] = RuntimeString{false, request.path}
            req_fields[1] = RuntimeString{false, request.method}

            handler_args := make([]RuntimeValue, 1)
            handler_args[0] = RuntimeStruct{true, req_fields, .HttpRequest}

            response_raw := interp_execute_function2(s, server.handler, handler_args)
            if compiler.should_exit_early(s.exit_early) {
                return nil
            }
            response := response_raw.(RuntimeSumType)

            err := webserver.send_response(
                client,
                200,
                "OK",
                compiler.response_type_variant_index_to_content_type(response.variant_index),
                transmute([]byte)(response.payload.(RuntimeString).value),
            )
            if err != nil {
                // TODO: Better error handling
                panic("Failed to send response")
            }
        }
        return nil
    case:
        panic("Unreachable")
    }
}

// Performs the websocket handshake and stores the connection so that
// `pump_websockets` can dispatch its messages to the server's websocket
// handler. Does not close `client` on success, the caller is responsible for
// that. Closes `client` itself when the handshake fails.
accept_websocket :: proc(
    s: InterpState,
    server_index: uint,
    client: net.TCP_Socket,
    upgrade_data: []byte,
) {
    key, key_ok := webserver.get_websocket_key(upgrade_data)
    if !key_ok {
        err := webserver.send_error(client, 400, "Bad Request")
        if err != nil {
            // TODO: Better error handling
            panic("Failed to send error")
        }
        net.close(client)
        return
    }

    accept_key, accept_ok := webserver.compute_accept_key(key)
    if !accept_ok {
        // TODO: Better error handling
        panic("Failed to compute the `Sec-WebSocket-Accept` value")
    }
    defer delete(accept_key)

    webserver.send_websocket_upgrade_response(client, accept_key)

    err := net.set_blocking(client, false)
    if err != nil {
        utils.panicf("Failed to disable blocking: %v", err)
    }

    append(&s.l.websockets, WebsocketConnection{client, server_index, true, make([dynamic]byte)})
}

// Dispatches the messages which have been received on open websocket
// connections to the websocket handlers and closes connections which the
// clients have closed. Messages which arrive while the program is being
// recompiled by the `-watch` flag stay in the connection's read buffer and
// are dispatched on the next run.
pump_websockets :: proc(s: InterpState) {
    none_tag := websocket_message_variant_index(s, "None")
    text_tag := websocket_message_variant_index(s, "Text")
    binary_tag := websocket_message_variant_index(s, "Binary")

    recv_buf: [65536]byte
    frame_buf: [65536]byte

    for conn_index in 0 ..< len(s.l.websockets) {
        conn := &s.l.websockets[conn_index]
        if !conn.open do continue

        for conn.open {
            if compiler.should_exit_early(s.exit_early) {
                break
            }

            frame, parse_ok := webserver.parse_ws_frame(frame_buf[:], conn.read_buffer[:])
            if !parse_ok {
                close_websocket_connection(conn)
                break
            }

            if frame == nil {
                n, recv_err := net.recv_tcp(conn.client, recv_buf[:])
                if recv_err == .Would_Block {
                    break
                }
                if recv_err != nil || n == 0 {
                    close_websocket_connection(conn)
                    break
                }
                append_elems(&conn.read_buffer, ..recv_buf[:n])
                continue
            }

            frame_len := ws_frame_len(conn.read_buffer[:])

            switch frame.opcode {
            case .Text:
                dispatch_websocket_message(
                    s,
                    conn,
                    text_tag,
                    frame.payload,
                    none_tag,
                    text_tag,
                    binary_tag,
                )
            case .Binary:
                dispatch_websocket_message(
                    s,
                    conn,
                    binary_tag,
                    frame.payload,
                    none_tag,
                    text_tag,
                    binary_tag,
                )
            case .Ping:
                webserver.send_ws_frame(conn.client, .Pong, frame.payload)
            case .Pong, .Continuation:
            case .Close:
                webserver.send_ws_frame(conn.client, .Close, nil)
            }

            // `parse_ws_frame` allocates the payload when the frame is
            // masked, otherwise the payload points into the read buffer
            if frame.mask {
                delete(frame.payload)
            }

            consume_ws_frame(&conn.read_buffer, frame_len)

            if frame.opcode == .Close {
                close_websocket_connection(conn)
            }
        }
    }

    i := 0
    for i < len(s.l.websockets) {
        if s.l.websockets[i].open {
            i += 1
        } else {
            last := pop(&s.l.websockets)
            if i < len(s.l.websockets) {
                s.l.websockets[i] = last
            }
        }
    }
}

// Calls the server's websocket handler with the message and sends the
// returned `WebSocketMessage` back over the connection
dispatch_websocket_message :: proc(
    s: InterpState,
    conn: ^WebsocketConnection,
    variant_index: u32,
    payload: []byte,
    none_tag: u32,
    text_tag: u32,
    binary_tag: u32,
) {
    server := s.l.http_servers[conn.server]
    if server.websocket_handler.ref.index == max(uint) {
        return
    }

    payload_value := new(RuntimeValue)
    payload_value^ = RuntimeString{true, strings.clone(string(payload))}

    args := make([]RuntimeValue, 1)
    args[0] = RuntimeSumType{.WebSocketMessage, true, variant_index, payload_value}

    response := interp_execute_function2(s, server.websocket_handler, args)
    if compiler.should_exit_early(s.exit_early) {
        return
    }

    response_sum, ok := response.(RuntimeSumType)
    if !ok {
        panic("Expected the websocket handler to return a `WebSocketMessage`")
    }
    if !conn.open {
        return
    }

    switch response_sum.variant_index {
    case none_tag:
    case text_tag:
        webserver.send_ws_frame(
            conn.client,
            .Text,
            transmute([]byte)response_sum.payload.(RuntimeString).value,
        )
    case binary_tag:
        webserver.send_ws_frame(
            conn.client,
            .Binary,
            transmute([]byte)response_sum.payload.(RuntimeString).value,
        )
    case:
        panic("Unreachable")
    }
}

close_websocket_connection :: proc(conn: ^WebsocketConnection) {
    if !conn.open do return
    conn.open = false
    net.close(conn.client)
    delete(conn.read_buffer)
}

// The number of bytes that the frame at the start of `data` takes up. `data`
// must contain a full frame.
ws_frame_len :: proc(data: []byte) -> int {
    payload_len := int(data[1] & 0x7F)
    offset := 2
    if payload_len == 126 {
        payload_len = int(data[2]) << 8 | int(data[3])
        offset += 2
    } else if payload_len == 127 {
        payload_len = 0
        for i in 0 ..< 8 {
            payload_len = payload_len << 8 | int(data[2 + i])
        }
        offset += 8
    }
    if data[1] & 0x80 != 0 {
        offset += 4
    }
    return offset + payload_len
}

consume_ws_frame :: proc(buffer: ^[dynamic]byte, frame_len: int) {
    remaining := len(buffer^) - frame_len
    copy((buffer^)[:remaining], (buffer^)[frame_len:])
    resize(buffer, remaining)
}

websocket_message_variant_index :: proc(s: InterpState, tag_name: string) -> u32 {
    index := utils.lookup(s.types.sum_type_tags, tag_name, utils.string_to_index_procs)
    assert(index != utils.does_not_exist)
    return index.index
}

// Called at the start of every program run because the handlers which are
// stored in the long lived state point into the previous run's functions
reset_persisted_handlers :: proc(l: ^LongLivedInterpState) {
    for &server in l.http_servers {
        server.handler = RuntimeFunc{compiler.CheckedFuncRef{max(uint)}, nil}
        server.websocket_handler = RuntimeFunc{compiler.CheckedFuncRef{max(uint)}, nil}
    }
}

interp_execute_function2 :: proc(
    state: InterpState,
    func: RuntimeFunc,
    args: []RuntimeValue,
    loc := #caller_location,
) -> RuntimeValue {
    utils.call(loc, "interp_execute_function2", "", enable_debug = utils.debug_interpreter)
    checked_func := state.checked_funcs[func.ref.index]
    utils.debug("checked_func.body: %v", checked_func.body)

    frame := Frame {
        func_index = func.ref.index,
        scopes     = make([dynamic][]RuntimeValue),
    }
    append_elem(&frame.scopes, func.lambda_args)
    append_elem(&frame.scopes, args)
    append_elem(&frame.scopes, make([]RuntimeValue, len(checked_func.variables)))
    // for var_type, i in checked_func.variables {
    // frame.scopes[1][i] = interp_default_value(state, var_type)
    // }

    append_elem(&state.frames, frame)

    assert(state.control_flow_op == nil)
    interp_exec_block(state, checked_func.body.v)
    f := pop(&state.frames)
    assert(len(f.scopes) == 3)
    for &v in f.scopes[2] {
        interp_destroy_value(&v)
    }
    delete(f.scopes[2])
    delete(f.scopes)

    if return_data, returning := state.control_flow_op.(ReturnFromFunction); returning {
        state.control_flow_op = nil
        return return_data.value
    } else {
        assert(state.control_flow_op == nil)
        return nil
    }
}

/*
interp_default_value :: proc(state: ^InterpState, t: compiler.Type) -> RuntimeValue {
    switch t {
    case i64_type:
        return i64(0)
    case i32_type:
        return i32(0)
    case i16_type:
        return i16(0)
    case i8_type:
        return i8(0)
    case u64_type:
        return u64(0)
    case u32_type:
        return u32(0)
    case u16_type:
        return u16(0)
    case u8_type:
        return u8(0)
    case bool_type:
        return false
    case string_type:
        return RuntimeString{false, ""}
    case:
        type_val := get_type(state.types, t)
        switch v in type_val {
        case OrderedHashMapTypeWithStringKey:
            return RuntimeStringOrderedHashMap{}
        case OrderedHashMapTypeWithIntKey:
            return RuntimeIntOrderedHashMap{}
        case ArrayType:
            return RuntimeArray{true, make([dynamic]RuntimeValue)}
        case Struct(compiler.Type, compiler.Type):
            fields := make([]RuntimeValue, len(v.fields))
            for field_type, i in v.fields {
                fields[i] = interp_default_value(state, field_type.type)
            }
            return RuntimeStruct{true, fields}
        case SumType(compiler.Type):
            payload := interp_default_value(state, v.variants[0].payload)
            return RuntimeSumType{true, 0, new_clone(payload)}
        case FuncType, GenericTypeValue:
            return i64(0)
        }
        return i64(0)
    }
}
*/

interp_exec_block :: proc(state: InterpState, body: []compiler.CheckedStatement) {
    for stmt in body {
        if state.control_flow_op != nil {
            return
        }
        if compiler.should_exit_early(state.exit_early) {
            return
        }
        interp_exec_statement(state, stmt)
    }
}

interp_push_scope :: proc(state: ^ShortLivedInterpState, variable_types: []compiler.Type) {
    scope := make([]RuntimeValue, len(variable_types))
    append_elem(&state.frames[len(state.frames) - 1].scopes, scope)
}

interp_pop_scope :: proc(state: ^ShortLivedInterpState, loc := #caller_location) {
    utils.call(loc, "interp_pop_scope", "")
    frame := &state.frames[len(state.frames) - 1]
    scope := pop(&frame.scopes)
    for &val in scope {
        interp_destroy_value(&val)
    }
    delete(scope)
}

interp_destroy_value :: proc(val: ^RuntimeValue, loc := #caller_location) {
    /*
        utils.call(loc, "interp_destroy_value")
    switch &v in val {
    case RuntimeStringOrderedHashMap:
        if v.needs_freeing {
            for _, &value in v.hashmap {
                interp_destroy_value(&value)
            }
            delete(v.hashmap)
            delete(v.order)
            v.needs_freeing = false
        }
    case RuntimeIntOrderedHashMap:
        if v.needs_freeing {
            for _, &value in v.hashmap {
                interp_destroy_value(&value)
            }
            delete(v.hashmap)
            delete(v.order)
            v.needs_freeing = false
        }
    case RuntimeArray:
        if v.needs_freeing {
            for &elem in v.elems {
                interp_destroy_value(&elem)
            }
            // TODO: Proper memory management
            // delete(v.elems)
            v.needs_freeing = false
        }
    case RuntimeStruct:
        if v.needs_freeing {
            for &field in v.field_values {
                interp_destroy_value(&field)
            }
            delete(v.field_values)
            v.needs_freeing = false
        }
    case RuntimeSumType:
        if v.needs_freeing {
            for &value in v.payload {
                interp_destroy_value(&value)
            }
            delete(v.payload)
            v.needs_freeing = false
        }
    case RuntimeString:
        if v.needs_freeing {
            delete(v.value)
            v.needs_freeing = false
        }
    case nil,
         i64,
         i32,
         i16,
         i8,
         u64,
         u32,
         u16,
         u8,
         bool,
         FuncDefinitionRef,
         BuiltinFunction,
         StructTypeInitFunc,
         SumTypeInitFunc,
         RuntimeStringOrderedHashMapInitFunc,
         RuntimeIntOrderedHashMapInitFunc:
    }
    */
}

interp_clone_value :: proc(val: RuntimeValue, loc := #caller_location) -> RuntimeValue {
    utils.call(loc, "interp_clone_value", "")
    switch v in val {
    case nil:
        panic("Unreachable: Uninitialised")
    case RuntimeOrderedHashMap:
        out_hashmap := make(map[compiler.HashMapKey]RuntimeValue, len(v.hashmap))
        for key, value in v.hashmap {
            out_hashmap[key] = interp_clone_value(value)
        }
        out_order := slice.clone(v.order)
        return RuntimeOrderedHashMap{v.type, true, out_hashmap, out_order}
    case RuntimeArray:
        new_elems := make([]RuntimeValue, len(v.elems))
        for elem, i in v.elems {
            new_elems[i] = interp_clone_value(elem)
        }
        return RuntimeArray{v.type, true, new_elems}
    case RuntimeStruct:
        new_fields := make([]RuntimeValue, len(v.field_values))
        for field, i in v.field_values {
            new_fields[i] = interp_clone_value(field)
        }
        return RuntimeStruct{true, new_fields, v.type}
    case RuntimeSumType:
        out := RuntimeSumType{v.type, true, v.variant_index, nil}
        if v.payload != nil {
            out.payload = new_clone(interp_clone_value(v.payload^))
        }
        return out
    case RuntimeString:
        return RuntimeString{true, strings.clone(v.value)}
    case f64,
         bool,
         RuntimeFunc,
         compiler.BuiltinFunction,
         HttpServerListenAndServe,
         SetHttpServerHandler,
         SetWebsocketHandler,
         SendToWebsockets,
         compiler.CastFunction:
        return val
    }
    return RuntimeValue{}
}

interp_exec_statement :: proc(state: InterpState, stmt: compiler.CheckedStatement) {
    switch s in stmt {
    case compiler.UnreachableStatement:
        panic("Reached unreachable code")

    case compiler.CheckedReturn:
        if s.value != nil {
            state.control_flow_op = ReturnFromFunction {
                interp_clone_value(interp_eval_value(state, s.value)),
            }
        } else {
            state.control_flow_op = ReturnFromFunction{nil}
        }
        utils.debug("state.control_flow_op set to %v", state.control_flow_op)

    case compiler.CheckedIf:
        cond := interp_eval_value(state, s.condition)
        cond_bool, cond_ok := cond.(bool)
        if !cond_ok {
            panic("Expected bool in if condition")
        }
        if cond_bool {
            interp_push_scope(state, s.if_block.variables)
            interp_exec_block(state, s.if_block.body)
            interp_pop_scope(state)
        } else {
            interp_push_scope(state, s.else_block.variables)
            interp_exec_block(state, s.else_block.body)
            interp_pop_scope(state)
        }

    case compiler.CheckedLoop:
        loop_index := s.loop_index
        interp_push_scope(state, s.variables)
        interp_exec_block(state, s.enter)
        outer: for {
            if state.control_flow_op != nil do break

            old_loop := state.current_loop
            state.current_loop = loop_index
            interp_exec_block(state, s.body.v)
            state.current_loop = old_loop

            switch op in state.control_flow_op {
            case ReturnFromFunction:
                break outer
            case compiler.CheckedLoopControlFlow:
                if op.loop_index == loop_index {
                    switch op.kind {
                    case .Continue:
                        state.control_flow_op = nil
                    case .Break:
                        state.control_flow_op = nil
                        break outer
                    }
                }
            }

            interp_exec_block(state, s.continue_code)
        }
        interp_pop_scope(state)

    case compiler.CheckedLoopControlFlow:
        assert(state.control_flow_op == nil)
        state.control_flow_op = compiler.CheckedLoopControlFlow{s.loop_index, s.kind}

    case compiler.CheckedAssignment:
        /*
        get_mutable_value :: proc(
            s: InterpState,
            value: CheckedValue,
            loc := #caller_location,
        ) -> ^RuntimeValue {
            utils.call(loc, "get_mutable_value")
            #partial switch v in value {
            case CheckedArrayAccess:
                array := get_mutable_value(s, v.array^).(RuntimeArray)
                return &array.elems[interp_eval_value(s, v.index^).(i64)]
            case VariableRef:
                return &s.frames[len(s.frames) - 1].scopes[v.nesting_level][v.index]
            case CheckedOrderedHashMapAccess:
                key := interp_eval_value(s, v.key^)
                #partial switch &hash_map_value in get_mutable_value(s, v.hash_map^) {
                case RuntimeStringOrderedHashMap:
                    key_string := key.(RuntimeString).value
                    if !(key_string in hash_map_value.hashmap) {
                        hash_map_value.hashmap[key_string] = nil
                        append_elem(&hash_map_value.order, key_string)
                    }
                    return &hash_map_value.hashmap[key_string]
                case RuntimeIntOrderedHashMap:
                    return &hash_map_value.hashmap[key.(i64)]
                }
                panic("Unreachable")
            case:
                panic("Unreachable")
            }
        }
        mutable_value := get_mutable_value(state, s.destination)
        interp_destroy_value(mutable_value)
        */
        state.frames[len(state.frames) - 1].scopes[s.dest.nesting_level][s.dest.index] =
            interp_eval_value(state, s.value)

    /*
    case CheckedArrayMutation:
        old_value :=
            state.frames[len(state.frames) - 1].scopes[s.variable.nesting_level][s.variable.index]
        arr, old_value_is_array := old_value.(RuntimeArray)
        if old_value_is_array {
            clear(&arr.elems)
        } else {
            arr = RuntimeArray{arr.type, true, make([dynamic]RuntimeValue)}
        }
        for segment in s.segments {
            switch seg in segment {
            case SingleElemSegment:
                val := interp_eval_value(state, seg.elem)
                append_elem(&arr.elems, interp_clone_value(val))
            case InlineArraySegment:
                src := interp_eval_value(state, seg.array)
                src_arr, src_ok := src.(RuntimeArray)
                if !src_ok {panic("Expected array for inline array segment")}
                for elem in src_arr.elems {
                    append_elem(&arr.elems, interp_clone_value(elem))
                }
            }
        }
        state.frames[len(state.frames) - 1].scopes[s.variable.nesting_level][s.variable.index] =
            arr
            */

    case compiler.CheckedFunctionCall:
        assert(interp_execute_function(state, s) == nil)

    case compiler.CheckedMatch:
        val := state.frames[len(state.frames) - 1].scopes[s.value.nesting_level][s.value.index].(RuntimeSumType)
        branch := s.branches[val.variant_index]
        interp_push_scope(state, branch.block.variables)
        val_var, has_val := branch.value_var.(compiler.VariableRef)
        if has_val {
            state.frames[len(state.frames) - 1].scopes[val_var.nesting_level][val_var.index] = val.payload^
        }
        interp_exec_block(state, branch.block.body)
        interp_pop_scope(state)

    }
}

mod :: proc(a: f64, b: f64) -> f64 {
    for a - b >= 0 {
        return mod(a - b, b)
    }
    return a
}

interp_is_equal :: proc(s: InterpState, lhs: RuntimeValue, val1: compiler.CheckedValue) -> bool {
    rhs := interp_eval_value(s, val1)
    #partial switch lhs_value in lhs {
    case f64:
        return lhs_value == rhs.(f64)
    case bool:
        return lhs_value == rhs.(bool)
    case:
        panic("Unreachable")
    }
}

interp_eval_comptime_value :: proc(
    s: InterpState,
    value: compiler.CompileTimeValue,
) -> RuntimeValue {
    switch comptime in value {
    case compiler.CompileTimeArray:
        elems := make([]RuntimeValue, len(comptime.elements))
        for elem, i in comptime.elements {
            elems[i] = interp_eval_comptime_value(s, elem)
        }
        return RuntimeArray{comptime.type, true, elems}
    case compiler.CompileTimeOrderedHashMapInitialisation:
        out_map: map[compiler.HashMapKey]RuntimeValue
        for key, v in comptime.value {
            out_map[key] = interp_eval_comptime_value(s, v)
        }
        return RuntimeOrderedHashMap{comptime.type, true, out_map, comptime.order}
    case compiler.CastFunction:
        return comptime
    case compiler.BuiltinFunction:
        return comptime
    case compiler.CompileTimeStructInitialisation:
        out_fields := make([]RuntimeValue, len(comptime.fields))
        for field, i in comptime.fields {
            out_fields[i] = interp_eval_comptime_value(s, field)
        }
        return RuntimeStruct{true, out_fields, comptime.struct_type}
    case compiler.Func:
        lambda_args := make(
            []RuntimeValue,
            len(s.checked_funcs[comptime.ref.index].inline_stuff.scope0.variables),
        )
        for _, i in lambda_args {
            var_ref := comptime.lambda_args.d[i]
            lambda_args[i] =
                s.frames[len(s.frames) - 1].scopes[var_ref.nesting_level][var_ref.index]
        }
        return RuntimeFunc{comptime.ref, lambda_args}
    case compiler.StringLiteralValue:
        return RuntimeString{false, string(comptime)}
    case utils.NumberValue:
        return utils.number_value_to_f64(comptime).(f64)
    case compiler.BoolValue:
        return bool(comptime)
    case compiler.Type,
         compiler.GlobalValueWithGenericRef,
         compiler.UninitialisedOrderedHashMapType,
         compiler.Import:
        panic("Unreachable")
    case:
        panic("Unreachable")
    }
}

interp_derive_value :: proc(
    s: InterpState,
    v: RuntimeValue,
    subset_elems: []compiler.DerivationSubsetElement,
    alteration: compiler.DerivationAlteration,
) -> RuntimeValue {
    if len(subset_elems) == 0 {
        arg := interp_eval_value(s, alteration.arg^)
        switch alteration.kind {
        case .Replace:
            return arg
        case .PipeThroughFunction:
            args := make([]RuntimeValue, 1)
            args[0] = v
            return interp_execute_function2(s, arg.(RuntimeFunc), args)
        case:
            panic("Unreachable")
        }
    }

    switch elem in subset_elems[0] {
    case compiler.ArrayElementAccess:
        index := expect_int(interp_eval_value(s, elem.index).(f64))
        old := v.(RuntimeArray)
        new_elems := make([]RuntimeValue, len(old.elems))
        for old_elem, i in old.elems {
            new_elems[i] = old_elem
        }
        new_elems[index] = interp_derive_value(s, old.elems[index], subset_elems[1:], alteration)
        return RuntimeArray{old.type, true, new_elems}
    case compiler.StringOrderedHashMapAccess:
        key := to_hashmap_key(interp_eval_value(s, elem.key))
        old := v.(RuntimeOrderedHashMap)
        new_hashmap := make(map[compiler.HashMapKey]RuntimeValue)
        new_order := old.order
        if key not_in old.hashmap {
            dyn := slice.clone_to_dynamic(old.order)
            append_elem(&dyn, key)
            new_order = dyn[:]
        }
        for k, old_elem in old.hashmap {
            new_hashmap[k] = old_elem
        }
        new_hashmap[key] = interp_derive_value(s, old.hashmap[key], subset_elems[1:], alteration)
        return RuntimeOrderedHashMap{old.type, true, new_hashmap, new_order}
    case compiler.FieldAccess:
        old := v.(RuntimeStruct)
        new_fields := make([]RuntimeValue, len(old.field_values))
        for old_field, i in old.field_values {
            new_fields[i] = old_field
        }
        new_fields[elem.field_index] = interp_derive_value(
            s,
            old.field_values[elem.field_index],
            subset_elems[1:],
            alteration,
        )
        return RuntimeStruct{true, new_fields, old.type}
    case:
        panic("Unreachable")
    }
}

expect_int :: proc(f: f64) -> int {
    assert(math.floor(f) == f)
    return int(f)
}

to_hashmap_key :: proc(value: RuntimeValue) -> compiler.HashMapKey {
    #partial switch v in value {
    case RuntimeString:
        return v.value
    case f64:
        return v
    case:
        panic("Unreachable")
    }
}

interp_eval_value :: proc(s: InterpState, v: compiler.CheckedValue) -> RuntimeValue {
    switch value in v {
    case compiler.StructInitialisation:
        out := RuntimeStruct{true, make([]RuntimeValue, len(value.fields)), value.struct_type}
        for field, i in value.fields {
            out.field_values[i] = interp_eval_value(s, field)
        }
        return out
    case compiler.SumTypeInitialisation:
        out := RuntimeSumType{value.sum_type, true, value.variant_index, nil}
        if value.payload != nil {
            out.payload = new_clone(interp_eval_value(s, value.payload^))
        }
        return out
    case compiler.LengthOfString:
        return f64(len(interp_eval_value(s, value.str^).(RuntimeString).value))
    case compiler.OrderedHashMapInitialisation:
        out_map: map[compiler.HashMapKey]RuntimeValue
        for k, val in value.compile_time_values {
            out_map[k] = interp_eval_comptime_value(s, val)
        }
        for k, val in value.runtime_values {
            out_map[k] = interp_eval_value(s, val)
        }
        return RuntimeOrderedHashMap{value.type, true, out_map, value.order}
    case compiler.ArrayLiteral:
        elems := make([dynamic]RuntimeValue)
        for segment in value.segments {
            switch seg in segment {
            case compiler.InlineArraySegment:
                append_elems(&elems, ..interp_eval_value(s, seg.array).(RuntimeArray).elems[:])
            case compiler.SingleElemSegment:
                append_elem(&elems, interp_eval_value(s, seg.elem))
            case:
                panic("Unreachable")
            }
        }
        return RuntimeArray{value.type, true, elems[:]}
    case compiler.CheckedDerivation:
        base_value := interp_eval_value(s, value.base^)
        return interp_derive_value(s, base_value, value.subset.elements, value.alteration)
    case compiler.CheckedOrderedHashMapAccess:
        hash_map := interp_eval_value(s, value.hash_map^).(RuntimeOrderedHashMap)
        key := interp_eval_value(s, value.key^)
        return hash_map.hashmap[to_hashmap_key(key)]
    case compiler.KeysOfOrderedHashMap:
        keys := interp_eval_value(s, value.hash_map^).(RuntimeOrderedHashMap).order
        out := make([]RuntimeValue, len(keys))
        for key, i in keys {
            switch k in key {
            case string:
                out[i] = RuntimeString{false, k}
            case f64:
                out[i] = k
            case:
                panic("Unreachable")
            }
        }
        return RuntimeArray {
            compiler.create_type(&s.types, compiler.ArrayType{nil, .String}).type,
            true,
            out,
        }

    case compiler.CompileTimeValue:
        return interp_eval_comptime_value(s, value)

    case compiler.ToString:
        inner := interp_eval_value(s, value.value^)
        switch inner_val in inner {
        case nil:
            panic("Unreachable: Uninitialised")
        case f64:
            if value.from_type == .FloatType {
                return RuntimeString{true, fmt.aprintf("%f", inner_val)}
            }
            assert(math.floor(inner_val) == inner_val)
            return RuntimeString{true, fmt.aprintf("%d", i64(inner_val))}
        case bool:
            return RuntimeString{false, inner_val ? "true" : "false"}
        case RuntimeString:
            return inner_val
        case RuntimeArray,
             RuntimeStruct,
             RuntimeSumType,
             RuntimeFunc,
             compiler.BuiltinFunction,
             RuntimeOrderedHashMap,
             HttpServerListenAndServe,
             SetHttpServerHandler,
             SetWebsocketHandler,
             SendToWebsockets,
             compiler.CastFunction:
            panic("Unreachable")
        }

    case compiler.VariableRef:
        return s.frames[len(s.frames) - 1].scopes[value.nesting_level][value.index]

    case compiler.BooleanNotValue:
        inner := interp_eval_value(s, value^)
        return !inner.(bool)

    case compiler.CheckedJoinedValues:
        lhs := interp_eval_value(s, value.val0^)

        switch value.join_method {

        case .In:
            hashmap := interp_eval_value(s, value.val1^).(RuntimeOrderedHashMap)
            return to_hashmap_key(lhs) in hashmap.hashmap

        case .Addition:
            return lhs.(f64) + interp_eval_value(s, value.val1^).(f64)

        case .Subtraction:
            return lhs.(f64) - interp_eval_value(s, value.val1^).(f64)

        case .Multiplication:
            return lhs.(f64) * interp_eval_value(s, value.val1^).(f64)

        case .Division:
            return lhs.(f64) / interp_eval_value(s, value.val1^).(f64)

        case .Modulo:
            return mod(lhs.(f64), interp_eval_value(s, value.val1^).(f64))

        case .IsEqual:
            return interp_is_equal(s, lhs, value.val1^)

        case .IsNotEqual:
            return !interp_is_equal(s, lhs, value.val1^)

        case .IsLessThan:
            return lhs.(f64) < interp_eval_value(s, value.val1^).(f64)

        case .IsLessThanOrEqual:
            return lhs.(f64) <= interp_eval_value(s, value.val1^).(f64)

        case .IsGreaterThan:
            return lhs.(f64) > interp_eval_value(s, value.val1^).(f64)

        case .IsGreaterThanOrEqual:
            return lhs.(f64) >= interp_eval_value(s, value.val1^).(f64)

        case .BooleanAnd:
            if lhs.(bool) == false {
                return false
            }
            return interp_eval_value(s, value.val1^).(bool)

        case .BooleanOr:
            if lhs.(bool) == true {
                return true
            }
            return interp_eval_value(s, value.val1^).(bool)

        case .StringConcat:
            return RuntimeString {
                true,
                strings.concatenate(
                    []string {
                        lhs.(RuntimeString).value,
                        interp_eval_value(s, value.val1^).(RuntimeString).value,
                    },
                ),
            }

        }

    case compiler.CheckedFunctionCall:
        return interp_execute_function(s, value)

    /*
    // OLD(INITIALISING STRUCTS LIKE `StructType(fields...)`)
    case compiler.StructTypeInitFunc:
        // struct_type := get_type(state.checked.types, value.type).(Struct(compiler.Type, compiler.Type))
        // fields := make([dynamic]RuntimeValue, len(struct_type.fields))
        // for field_type, i in struct_type.fields {
        // fields[i] = interp_default_value(state, field_type.type)
        // }
        // return RuntimeStruct{fields}
        return value
        */

    case compiler.CheckedIndexedAccess:
        base := interp_eval_value(s, value.base^)
        start_index := expect_int(interp_eval_value(s, value.i.start_index^).(f64))
        switch value.base_type {
        case .Array:
            arr := base.(RuntimeArray)
            if value.i.end_index != nil {
                end_index := expect_int(interp_eval_value(s, value.i.end_index^).(f64))
                // TODO: Using `arr.type` means that the result has the incorrect type if `arr` is fixed-size
                return RuntimeArray{arr.type, false, arr.elems[start_index:end_index]}
            }
            return base.(RuntimeArray).elems[start_index]
        case .String:
            str := base.(RuntimeString).value
            if value.i.end_index != nil {
                end_index := expect_int(interp_eval_value(s, value.i.end_index^).(f64))
                return RuntimeString{false, str[start_index:end_index]}
            }
            return f64(str[start_index])
        case:
            panic("Unreachable")
        }

    case compiler.CheckedFieldAccess:
        struct_val := interp_eval_value(s, value.value^)
        s, s_ok := struct_val.(RuntimeStruct)
        if !s_ok {panic("Expected struct for field access")}
        return s.field_values[value.field_index]

    case compiler.LengthOfArray:
        arr := interp_eval_value(s, value.array^).(RuntimeArray)
        return f64(len(arr.elems))

    case compiler.LengthOfOrderedHashMap:
        hash_map := interp_eval_value(s, value.hash_map^)
        return f64(len(hash_map.(RuntimeOrderedHashMap).order))

    case compiler.StringsAreEqual:
        str0 := interp_eval_value(s, value.str0^)
        str1 := interp_eval_value(s, value.str1^)
        return str0.(RuntimeString).value == str1.(RuntimeString).value

    }
    panic("Unreachable")
}

DefaultBuiltinHandlerData :: struct {
    working_dir: string,
    pipe:        utils.Pipe(io.Writer),
    stdin:       io.Reader,
}

// Caller should `delete` the returned string
handle_path :: proc(working_dir: string, path: string) -> string {
    if filepath.is_abs(path) {
        return strings.clone(path)
    }
    out, err := filepath.join([]string{working_dir, path})
    if err != nil {
        panic(fmt.aprintf("Failed to join path: %v", err))
    }
    return out
}

default_builtin_handler_procedure :: proc(
    state: InterpState,
    index: compiler.BuiltinFunction,
    args: []RuntimeValue,
) -> RuntimeValue {
    data := cast(^DefaultBuiltinHandlerData)state.builtin_handler.data
    // TODO: Maybe we should use the definitions in glue.c
    // https://odin-lang.org/news/binding-to-c/
    switch index {
    case .print:
        assert(len(args) == 1)
        fmt.wprint(data.pipe.stdout, args[0].(RuntimeString).value)
        return nil
    case .println:
        assert(len(args) == 1)
        fmt.wprintln(data.pipe.stdout, args[0].(RuntimeString).value)
        return nil
    case .eprint:
        assert(len(args) == 1)
        fmt.wprint(data.pipe.stderr, args[0].(RuntimeString).value)
        return nil
    case .eprintln:
        assert(len(args) == 1)
        fmt.wprintln(data.pipe.stderr, args[0].(RuntimeString).value)
        return nil
    case .readline:
        assert(len(args) == 1)
        io.write_string(data.pipe.stdout, args[0].(RuntimeString).value)
        io.flush(data.pipe.stdout)
        bytes := make([dynamic]byte)
        for {
            b, err := io.read_byte(data.stdin)
            assert(err == nil)
            if b == '\n' {
                break
            }
            if b == '\r' {
                continue
            }
            append_elem(&bytes, b)
        }
        return RuntimeString{true, string(bytes[:])}
    case .read_file:
        panic("TODO")
    case .write_file:
        assert(len(args) == 2)
        path := handle_path(data.working_dir, args[0].(RuntimeString).value)
        defer delete(path)
        err := os.write_entire_file(path, transmute([]u8)args[1].(RuntimeString).value)
        if err != nil {
            panic(fmt.aprintf("Failed to write file at `%s`: %v", path, err))
        }
        return nil
    case .make_dir_all:
        assert(len(args) == 1)
        path := handle_path(data.working_dir, args[0].(RuntimeString).value)
        defer delete(path)
        err := os.make_directory_all(path)
        if err != nil && err != .Exist {
            panic(fmt.aprintf("Failed to make directory all `%s`: %v", path, err))
        }
        return nil
    case .clear:
        assert(len(args) == 0)
        fmt.wprint(data.pipe.stdout, utils.ansi_clear)
        return nil
    case .run_executable:
        panic("TODO")
    case .exit:
        assert(len(args) == 1)
        os.exit(expect_int(args[0].(f64)))
    case .get_os_args:
        panic("TODO")
    case .emit_js_code:
        // TODO: Tree shake globals which are not used by the globals in `globals_map`
        assert(len(args) == 2)
        globals_map := args[0].(RuntimeOrderedHashMap)
        glue := args[1].(RuntimeString)
        builder := emit_javascript(state.types, state.checked_funcs)
        for global_name in globals_map.order {
            strings.write_string(&builder, "let ")
            strings.write_string(&builder, global_name.(string))
            strings.write_string(&builder, "=")
            emit_js_runtime_value(&builder, globals_map.hashmap[global_name])
            strings.write_string(&builder, ";")
        }
        strings.write_string(&builder, glue.value)
        return RuntimeString{true, strings.to_string(builder)}
    case .cache_contains:
        assert(len(args) == 1)
        return args[0].(RuntimeString).value in state.l.cache
    case .cache_set:
        assert(len(args) == 2)
        state.l.cache[args[0].(RuntimeString).value] = args[1]
        return nil
    case .cache_get:
        assert(len(args) == 1)
        return state.l.cache[args[0].(RuntimeString).value]
    case .init_http_server:
        assert(len(args) == 0)

        server_index: uint = len(state.l.http_servers)

        fields := make([]RuntimeValue, 5)
        fields[0] = SetHttpServerHandler{server_index}
        fields[1] = HttpServerListenAndServe{server_index}
        fields[3] = SetWebsocketHandler{server_index}
        fields[4] = SendToWebsockets{server_index}

        endpoint := net.Endpoint{net.IP4_Address{0, 0, 0, 0}, 8080}
        // TODO: Implement upper limit on number of ports to try
        for {
            // TODO: Log that the port is being tried
            socket, err := net.listen_tcp(endpoint)
            if err == nil {
                err2 := net.set_blocking(socket, false)
                if err2 != nil {
                    utils.panicf("Failed to disable blocking: %v", err2)
                }
                fields[2] = f64(endpoint.port)
                append(
                    &state.l.http_servers,
                    HttpServer {
                        socket,
                        RuntimeFunc{compiler.CheckedFuncRef{max(uint)}, nil},
                        RuntimeFunc{compiler.CheckedFuncRef{max(uint)}, nil},
                    },
                )
                return RuntimeStruct{true, fields, .HttpServer}
            }
            if err != net.Bind_Error.Address_In_Use {
                // TODO: Better error reporting
                panic(fmt.aprintf("Failed create TCP socket and start listening: %v", err))
            }
            // TODO: Log that the port is already in use
            endpoint.port += 1
        }
    case .string_repeat:
        assert(len(args) == 2)
        return RuntimeString {
            true,
            strings.repeat(args[0].(RuntimeString).value, expect_int(args[1].(f64))),
        }
    case .save_cursor_pos:
        io.write_string(data.pipe.stdout, "\033[s")
        io.flush(data.pipe.stdout)
        return nil
    case .restore_cursor_pos:
        io.write_string(data.pipe.stdout, "\033[u")
        io.flush(data.pipe.stdout)
        return nil
    case .clear_after_cursor:
        io.write_string(data.pipe.stdout, "\033[0J")
        io.flush(data.pipe.stdout)
        return nil
    case .cast_func:
        panic("Unreachable")
    case .expect_uint:
        assert(len(args) == 1)
        arg := args[0].(f64)
        assert(math.floor(arg) == arg)
        assert(arg >= 0)
        return arg
    case:
        panic(fmt.aprintf("Unreachable (index is %d)", index))
    }
}

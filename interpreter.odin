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
import "utils"
import "webserver"

Frame :: struct {
    func:   compiler.CheckedFuncRef,
    scopes: [dynamic][]compiler.ExactValue,
}

BuiltinHandler :: struct {
    data:      rawptr,
    procedure: proc(
        state: InterpState,
        f: compiler.BuiltinFunction,
        args: []compiler.ExactValue,
    ) -> compiler.ExactValue,
}

ReturnFromFunction :: struct {
    value: compiler.ExactValue,
}

ControlFlowOperation :: union {
    compiler.CheckedLoopControlFlow,
    ReturnFromFunction,
}

HttpServer :: struct {
    socket:  net.TCP_Socket,
    handler: compiler.RuntimeFunc,
}

// Interpreter state that lasts when the program is restarted by the `-watch` flag
LongLivedInterpState :: struct {
    cache:        map[string]compiler.ExactValue,
    http_servers: [dynamic]HttpServer,
}

// Interpreter state that is reset when the program is restarted by the `-watch` flag
ShortLivedInterpState :: struct {
    a:                       utils.Arena, // TODO: Cleanup this arena when the interpreter finishes
    types:                   compiler.Types,
    globals_without_generic: []compiler.GlobalValueWithoutGeneric,
    globals_with_generic:    []compiler.GlobalValueWithGeneric,
    checked_funcs:           []compiler.CheckedFunction,
    func_ranges:             utils.Multi(utils.Range),
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
) -> compiler.ExactValue {
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

interp_execute_function :: proc(
    s: InterpState,
    c: compiler.CheckedFunctionCall,
) -> compiler.ExactValue {
    fn_val := interp_eval_value(s, c.function^)
    args := make([]compiler.ExactValue, len(c.args))
    for arg_val, i in c.args {
        args[i] = interp_clone_value(s.s^, interp_eval_value(s, arg_val))
    }

    #partial switch val in fn_val {
    /*
    // OLD(INITIALISING STRUCTS LIKE `StructType(fields...)`)
    case compiler.StructTypeInitFunc:
        return RuntimeStruct{true, args, val.return_type}
    */
    case compiler.CastFunction:
        assert(len(args) == 1)
        got_type := compiler.get_exact_value_type(s.checked_funcs, args[0])
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
    case compiler.RuntimeFunc:
        return interp_execute_function2(s, val, args)
    case compiler.SetHttpServerHandler:
        assert(len(args) == 1)
        s.l.http_servers[val.server].handler = args[0].(compiler.RuntimeFunc)
        return nil
    case compiler.HttpServerListenAndServe:
        assert(len(args) == 0)
        server := s.l.http_servers[val.server]
        if server.handler.ref.index.v == max(uint) {
            panic("`listen_and_serve` called when handler has not been set")
        }
        buf: [65536]byte
        for {
            // TODO: Set timeout on accept_tcp so it does not block the
            // automatic recompilation of the `-watch` flag
            client, _, accept_err := net.accept_tcp(server.socket)
            if accept_err != nil {
                // TODO: Better error handling
                panic(fmt.aprintf("Accept error: %v", accept_err))
            }
            defer net.close(client)

            n, receive_err := net.recv_tcp(client, buf[:])
            if receive_err != nil {
                // TODO: Better error handling
                panic(fmt.aprintf("Receive error: %v", receive_err))
            }

            data := buf[:n]

            if webserver.is_websocket_upgrade_request(data) {
                panic("TODO: Add support for websockets")
            } else {
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

                req_fields := make([]compiler.ExactValue, 2)
                req_fields[0] = compiler.StringValue(request.path)
                req_fields[1] = compiler.StringValue(request.method)

                handler_args := make([]compiler.ExactValue, 1)
                handler_args[0] = compiler.StructInitialisation(compiler.ExactValue) {
                    .HttpRequest,
                    req_fields,
                }

                response_raw := interp_execute_function2(s, server.handler, handler_args)
                if compiler.should_exit_early(s.exit_early) {
                    return nil
                }
                response := response_raw.(compiler.SumTypeInitialisation(^compiler.ExactValue))

                err := webserver.send_response(
                    client,
                    200,
                    "OK",
                    compiler.response_type_variant_index_to_content_type(response.variant_index),
                    transmute([]byte)(response.payload.(compiler.StringValue)),
                )
                if err != nil {
                    // TODO: Better error handling
                    panic("Failed to send response")
                }
            }
        }
        return nil
    case:
        panic("Unreachable")
    }
}

interp_execute_function2 :: proc(
    state: InterpState,
    func: compiler.RuntimeFunc,
    args: []compiler.ExactValue,
    loc := #caller_location,
) -> compiler.ExactValue {
    utils.call(loc, "interp_execute_function2", "", enable_debug = utils.debug_interpreter)
    checked_func := state.checked_funcs[func.ref.index.v]
    utils.debug("checked_func.body: %v", checked_func.body)

    frame := Frame {
        func   = func.ref,
        scopes = make([dynamic][]compiler.ExactValue),
    }
    append_elem(
        &frame.scopes,
        utils.multi_to_array(func.lambda_args, len(checked_func.inline_stuff.scope0.variables)),
    )
    append_elem(&frame.scopes, args)
    append_elem(&frame.scopes, make([]compiler.ExactValue, len(checked_func.variables)))
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
interp_default_value :: proc(state: ^InterpState, t: compiler.Type) -> compiler.ExactValue {
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
        return compiler.StringValue{false, ""}
    case:
        type_val := get_type(state.types, t)
        switch v in type_val {
        case OrderedHashMapTypeWithStringKey:
            return compiler.StringValueOrderedHashMap{}
        case OrderedHashMapTypeWithIntKey:
            return RuntimeIntOrderedHashMap{}
        case ArrayType:
            return RuntimeArray{true, make([dynamic]compiler.ExactValue)}
        case Struct(compiler.Type, compiler.Type):
            fields := make([]compiler.ExactValue, len(v.fields))
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
    scope := make([]compiler.ExactValue, len(variable_types))
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

interp_destroy_value :: proc(val: ^compiler.ExactValue, loc := #caller_location) {
    /*
        utils.call(loc, "interp_destroy_value")
    switch &v in val {
    case compiler.StringValueOrderedHashMap:
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
    case compiler.StringValue:
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
         compiler.StringValueOrderedHashMapInitFunc,
         RuntimeIntOrderedHashMapInitFunc:
    }
    */
}

// TODO: Be able to read the call stack from within comb for debugging
dump_call_stack :: proc(s: ShortLivedInterpState) {
    for frame in s.frames {
        checked_func := s.checked_funcs[frame.func.index.v]
        fmt.printfln("Function defined at %v", s.func_ranges.d[checked_func.definition.index])
        when ODIN_DEBUG {
            fmt.printfln("Reference index created at %v", frame.func.index.created_at)
        }
    }
}

interp_clone_value :: proc(
    s: ShortLivedInterpState,
    val: compiler.ExactValue,
    loc := #caller_location,
) -> compiler.ExactValue {
    utils.call(loc, "interp_clone_value", "")
    switch v in val {
    case compiler.Type,
         compiler.Import,
         compiler.GlobalValueWithGenericRef,
         compiler.UninitialisedOrderedHashMapType:
        panic("Unreachable")
    case nil:
        dump_call_stack(s)
        panic("Unreachable: Uninitialised")
    case compiler.ExactOrderedHashMap:
        out_hashmap := make(map[compiler.HashMapKey]compiler.ExactValue, len(v.value))
        for key, value in v.value {
            out_hashmap[key] = interp_clone_value(s, value)
        }
        out_order := slice.clone(v.order)
        return compiler.ExactOrderedHashMap{v.type, out_hashmap, out_order}
    case compiler.Array(compiler.ExactValue):
        new_elems := make([]compiler.ExactValue, len(v.elements))
        for elem, i in v.elements {
            new_elems[i] = interp_clone_value(s, elem)
        }
        return compiler.Array(compiler.ExactValue){v.type, new_elems}
    case compiler.StructInitialisation(compiler.ExactValue):
        new_fields := make([]compiler.ExactValue, len(v.fields))
        for field, i in v.fields {
            new_fields[i] = interp_clone_value(s, field)
        }
        return compiler.StructInitialisation(compiler.ExactValue){v.struct_type, new_fields}
    case compiler.SumTypeInitialisation(^compiler.ExactValue):
        out := compiler.SumTypeInitialisation(^compiler.ExactValue) {
            v.sum_type,
            v.variant_index,
            nil,
        }
        if v.payload != nil {
            out.payload = new_clone(interp_clone_value(s, v.payload^))
        }
        return out
    case compiler.StringValue:
        return compiler.StringValue(strings.clone(string(v)))
    case f64,
         compiler.BoolValue,
         compiler.RuntimeFunc,
         compiler.BuiltinFunction,
         compiler.HttpServerListenAndServe,
         compiler.SetHttpServerHandler,
         compiler.CastFunction:
        return val
    }
    return compiler.ExactValue{}
}

interp_exec_statement :: proc(state: InterpState, stmt: compiler.CheckedStatement) {
    switch s in stmt {
    case compiler.UnreachableStatement:
        dump_call_stack(state.s^)
        panic("Reached unreachable code")

    case compiler.CheckedReturn:
        if s.value != nil {
            state.control_flow_op = ReturnFromFunction {
                interp_clone_value(state.s^, interp_eval_value(state, s.value)),
            }
        } else {
            state.control_flow_op = ReturnFromFunction{nil}
        }
        utils.debug("state.control_flow_op set to %v", state.control_flow_op)

    case compiler.CheckedIf:
        cond := interp_eval_value(state, s.condition)
        cond_bool, cond_ok := cond.(compiler.BoolValue)
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
        ) -> ^compiler.ExactValue {
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
                case compiler.StringValueOrderedHashMap:
                    key_string := key.(compiler.StringValue).value
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
            arr = RuntimeArray{arr.type, true, make([dynamic]compiler.ExactValue)}
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
        val := state.frames[len(state.frames) - 1].scopes[s.value.nesting_level][s.value.index].(compiler.SumTypeInitialisation(
            ^compiler.ExactValue,
        ))
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

interp_is_equal :: proc(
    s: InterpState,
    lhs: compiler.ExactValue,
    val1: compiler.CheckedValue,
) -> bool {
    rhs := interp_eval_value(s, val1)
    #partial switch lhs_value in lhs {
    case f64:
        return lhs_value == rhs.(f64)
    case compiler.BoolValue:
        return lhs_value == rhs.(compiler.BoolValue)
    case:
        panic("Unreachable")
    }
}

// TODO: This function is probably unnecersarry
interp_eval_comptime_value :: proc(
    s: InterpState,
    value: compiler.ExactValue,
) -> compiler.ExactValue {
    switch comptime in value {
    case compiler.SetHttpServerHandler,
         compiler.HttpServerListenAndServe,
         compiler.SumTypeInitialisation(^compiler.ExactValue):
        panic("TODO")
    case compiler.Array(compiler.ExactValue):
        elems := make([]compiler.ExactValue, len(comptime.elements))
        for elem, i in comptime.elements {
            elems[i] = interp_eval_comptime_value(s, elem)
        }
        return compiler.Array(compiler.ExactValue){comptime.type, elems}
    case compiler.ExactOrderedHashMap:
        out_map: map[compiler.HashMapKey]compiler.ExactValue
        for key, v in comptime.value {
            out_map[key] = interp_eval_comptime_value(s, v)
        }
        return compiler.ExactOrderedHashMap{comptime.type, out_map, comptime.order}
    case compiler.CastFunction:
        return comptime
    case compiler.BuiltinFunction:
        return comptime
    case compiler.StructInitialisation(compiler.ExactValue):
        out_fields := make([]compiler.ExactValue, len(comptime.fields))
        for field, i in comptime.fields {
            out_fields[i] = interp_eval_comptime_value(s, field)
        }
        return compiler.StructInitialisation(compiler.ExactValue){comptime.struct_type, out_fields}
    case compiler.RuntimeFunc:
        length := len(s.checked_funcs[comptime.ref.index.v].inline_stuff.scope0.variables)
        lambda_args := utils.arena_make_multi(&s.s.a, utils.Multi(compiler.ExactValue), length)
        for i in 0 ..< length {
            lambda_args.d[i] = interp_eval_comptime_value(s, comptime.lambda_args.d[i])
        }
        return compiler.RuntimeFunc{comptime.ref, lambda_args}
    case compiler.StringValue:
        return compiler.StringValue(string(comptime))
    case f64:
        return comptime
    case compiler.BoolValue:
        return comptime
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
    v: compiler.ExactValue,
    subset_elems: []compiler.DerivationSubsetElement,
    alteration: compiler.DerivationAlteration,
) -> compiler.ExactValue {
    if len(subset_elems) == 0 {
        arg := interp_eval_value(s, alteration.arg^)
        switch alteration.kind {
        case .Replace:
            return arg
        case .PipeThroughFunction:
            args := make([]compiler.ExactValue, 1)
            args[0] = v
            return interp_execute_function2(s, arg.(compiler.RuntimeFunc), args)
        case:
            panic("Unreachable")
        }
    }

    switch elem in subset_elems[0] {
    case compiler.DerivationSubsetElementWithCheckedValue:
        HandlerData :: struct {
            s: InterpState,
            e: []compiler.DerivationSubsetElement,
            a: compiler.DerivationAlteration,
        }
        handler :: proc(data: HandlerData, value: compiler.ExactValue) -> compiler.ExactValue {
            return interp_derive_value(data.s, value, data.e, data.a)
        }
        return compiler.derive_subset_element_with_exact_value(
            v,
            elem.kind,
            interp_eval_value(s, elem.checked_value),
            HandlerData{s, subset_elems[1:], alteration},
            handler,
        )

    case compiler.FieldAccess:
        old := v.(compiler.StructInitialisation(compiler.ExactValue))
        new_fields := make([]compiler.ExactValue, len(old.fields))
        for old_field, i in old.fields {
            new_fields[i] = old_field
        }
        new_fields[elem.field_index] = interp_derive_value(
            s,
            old.fields[elem.field_index],
            subset_elems[1:],
            alteration,
        )
        return compiler.StructInitialisation(compiler.ExactValue){old.struct_type, new_fields}
    case:
        panic("Unreachable")
    }
}

interp_eval_value :: proc(s: InterpState, v: compiler.CheckedValue) -> compiler.ExactValue {
    switch value in v {
    case compiler.Func:
        length := len(s.checked_funcs[value.ref.index.v].inline_stuff.scope0.variables)
        lambda_args := utils.arena_make_multi(&s.a, utils.Multi(compiler.ExactValue), length)
        for i in 0 ..< length {
            var_ref := value.lambda_args.d[i]
            lambda_args.d[i] =
                s.frames[len(s.frames) - 1].scopes[var_ref.nesting_level][var_ref.index]
        }
        return compiler.RuntimeFunc{value.ref, lambda_args}
    case compiler.StructInitialisation(compiler.CheckedValue):
        out := compiler.StructInitialisation(compiler.ExactValue) {
            value.struct_type,
            make([]compiler.ExactValue, len(value.fields)),
        }
        for field, i in value.fields {
            out.fields[i] = interp_eval_value(s, field)
        }
        return out
    case compiler.SumTypeInitialisation(^compiler.CheckedValue):
        out := compiler.SumTypeInitialisation(^compiler.ExactValue) {
            value.sum_type,
            value.variant_index,
            nil,
        }
        if value.payload != nil {
            out.payload = new_clone(interp_eval_value(s, value.payload^))
        }
        return out
    case compiler.LengthOfString:
        return f64(len(interp_eval_value(s, value.str^).(compiler.StringValue)))
    case compiler.OrderedHashMapInitialisation:
        out_map: map[compiler.HashMapKey]compiler.ExactValue
        for k, val in value.compile_time_values {
            out_map[k] = interp_eval_comptime_value(s, val)
        }
        for k, val in value.runtime_values {
            out_map[k] = interp_eval_value(s, val)
        }
        return compiler.ExactOrderedHashMap{value.type, out_map, value.order}
    case compiler.ArrayLiteral:
        elems := make([dynamic]compiler.ExactValue)
        for segment in value.segments {
            switch seg in segment {
            case compiler.InlineArraySegment:
                append_elems(
                    &elems,
                    ..interp_eval_value(s, seg.array).(compiler.Array(compiler.ExactValue)).elements[:],
                )
            case compiler.SingleElemSegment:
                append_elem(&elems, interp_eval_value(s, seg.elem))
            case:
                panic("Unreachable")
            }
        }
        return compiler.Array(compiler.ExactValue){value.type, elems[:]}
    case compiler.CheckedDerivation:
        base_value := interp_eval_value(s, value.base^)
        return interp_derive_value(s, base_value, value.subset.elements, value.alteration)
    case compiler.CheckedOrderedHashMapAccess:
        hash_map := interp_eval_value(s, value.hash_map^).(compiler.ExactOrderedHashMap)
        key := interp_eval_value(s, value.key^)
        return hash_map.value[to_hashmap_key(key)]
    case compiler.KeysOfOrderedHashMap:
        keys := interp_eval_value(s, value.hash_map^).(compiler.ExactOrderedHashMap).order
        out := make([]compiler.ExactValue, len(keys))
        for key, i in keys {
            switch k in key {
            case string:
                out[i] = compiler.StringValue(k)
            case f64:
                out[i] = k
            case:
                panic("Unreachable")
            }
        }
        return compiler.Array(compiler.ExactValue) {
            compiler.create_type(&s.types, compiler.ArrayType{nil, .String}).type,
            out,
        }

    case compiler.ExactValue:
        return interp_eval_comptime_value(s, value)

    case compiler.ToString:
        inner := interp_eval_value(s, value.value^)
        switch inner_val in inner {
        case compiler.Type,
             compiler.Import,
             compiler.UninitialisedOrderedHashMapType,
             compiler.GlobalValueWithGenericRef:
            panic("Unreachable")
        case nil:
            panic("Unreachable: Uninitialised")
        case f64:
            if value.from_type == .FloatType {
                return compiler.StringValue(fmt.aprintf("%f", inner_val))
            }
            assert(math.floor(inner_val) == inner_val)
            return compiler.StringValue(fmt.aprintf("%d", i64(inner_val)))
        case compiler.BoolValue:
            return compiler.StringValue(inner_val ? "true" : "false")
        case compiler.StringValue:
            return inner_val
        case compiler.Array(compiler.ExactValue),
             compiler.StructInitialisation(compiler.ExactValue),
             compiler.SumTypeInitialisation(^compiler.ExactValue),
             compiler.RuntimeFunc,
             compiler.BuiltinFunction,
             compiler.ExactOrderedHashMap,
             compiler.HttpServerListenAndServe,
             compiler.SetHttpServerHandler,
             compiler.CastFunction:
            panic("Unreachable")
        }

    case compiler.VariableRef:
        return s.frames[len(s.frames) - 1].scopes[value.nesting_level][value.index]

    case compiler.BooleanNotValue:
        inner := interp_eval_value(s, value^)
        return !inner.(compiler.BoolValue)

    case compiler.CheckedJoinedValues:
        lhs := interp_eval_value(s, value.val0^)

        switch value.join_method {

        case .In:
            hashmap := interp_eval_value(s, value.val1^).(compiler.ExactOrderedHashMap)
            return compiler.BoolValue(to_hashmap_key(lhs) in hashmap.value)

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
            return compiler.BoolValue(interp_is_equal(s, lhs, value.val1^))

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
            if lhs.(compiler.BoolValue) == false {
                return false
            }
            return interp_eval_value(s, value.val1^).(compiler.BoolValue)

        case .BooleanOr:
            if lhs.(compiler.BoolValue) == true {
                return true
            }
            return interp_eval_value(s, value.val1^).(compiler.BoolValue)

        case .StringConcat:
            return compiler.StringValue(
                strings.concatenate(
                    []string {
                        string(lhs.(compiler.StringValue)),
                        string(interp_eval_value(s, value.val1^).(compiler.StringValue)),
                    },
                ),
            )

        }

    case compiler.CheckedFunctionCall:
        return interp_execute_function(s, value)

    /*
    // OLD(INITIALISING STRUCTS LIKE `StructType(fields...)`)
    case compiler.StructTypeInitFunc:
        // struct_type := get_type(state.checked.types, value.type).(Struct(compiler.Type, compiler.Type))
        // fields := make([dynamic]compiler.ExactValue, len(struct_type.fields))
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
            arr := base.(compiler.Array(compiler.ExactValue))
            if value.i.end_index != nil {
                end_index := expect_int(interp_eval_value(s, value.i.end_index^).(f64))
                // TODO: Using `arr.type` means that the result has the incorrect type if `arr` is fixed-size
                return compiler.Array(compiler.ExactValue) {
                    arr.type,
                    arr.elements[start_index:end_index],
                }
            }
            return base.(compiler.Array(compiler.ExactValue)).elements[start_index]
        case .String:
            str := base.(compiler.StringValue)
            if value.i.end_index != nil {
                end_index := expect_int(interp_eval_value(s, value.i.end_index^).(f64))
                return compiler.StringValue(str[start_index:end_index])
            }
            return f64(str[start_index])
        case:
            panic("Unreachable")
        }

    case compiler.CheckedFieldAccess:
        struct_val := interp_eval_value(s, value.value^)
        s, s_ok := struct_val.(compiler.StructInitialisation(compiler.ExactValue))
        if !s_ok {panic("Expected struct for field access")}
        return s.fields[value.field_index]

    case compiler.LengthOfArray:
        arr := interp_eval_value(s, value.array^).(compiler.Array(compiler.ExactValue))
        return f64(len(arr.elements))

    case compiler.LengthOfOrderedHashMap:
        hash_map := interp_eval_value(s, value.hash_map^)
        return f64(len(hash_map.(compiler.ExactOrderedHashMap).order))

    case compiler.StringsAreEqual:
        str0 := interp_eval_value(s, value.str0^)
        str1 := interp_eval_value(s, value.str1^)
        return str0.(compiler.StringValue) == str1.(compiler.StringValue)

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
    args: []compiler.ExactValue,
) -> compiler.ExactValue {
    data := cast(^DefaultBuiltinHandlerData)state.builtin_handler.data
    // TODO: Maybe we should use the definitions in glue.c
    // https://odin-lang.org/news/binding-to-c/
    switch index {
    case .print:
        assert(len(args) == 1)
        fmt.wprint(data.pipe.stdout, args[0].(compiler.StringValue))
        return nil
    case .println:
        assert(len(args) == 1)
        fmt.wprintln(data.pipe.stdout, args[0].(compiler.StringValue))
        return nil
    case .eprint:
        assert(len(args) == 1)
        fmt.wprint(data.pipe.stderr, args[0].(compiler.StringValue))
        return nil
    case .eprintln:
        assert(len(args) == 1)
        fmt.wprintln(data.pipe.stderr, args[0].(compiler.StringValue))
        return nil
    case .readline:
        assert(len(args) == 1)
        io.write_string(data.pipe.stdout, string(args[0].(compiler.StringValue)))
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
        return compiler.StringValue(bytes[:])
    case .read_file:
        panic("TODO")
    case .write_file:
        assert(len(args) == 2)
        path := handle_path(data.working_dir, string(args[0].(compiler.StringValue)))
        defer delete(path)
        err := os.write_entire_file(path, transmute([]u8)args[1].(compiler.StringValue))
        if err != nil {
            panic(fmt.aprintf("Failed to write file at `%s`: %v", path, err))
        }
        return nil
    case .make_dir_all:
        assert(len(args) == 1)
        path := handle_path(data.working_dir, string(args[0].(compiler.StringValue)))
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
        globals_map := args[0].(compiler.ExactOrderedHashMap)
        glue := args[1].(compiler.StringValue)
        state := emit_javascript(state.types, state.checked_funcs)
        for global_name in globals_map.order {
            strings.write_string(&state.b, "let ")
            strings.write_string(&state.b, global_name.(string))
            strings.write_string(&state.b, "=")
            emit_js_exact_value(&state, globals_map.value[global_name])
            strings.write_string(&state.b, ";")
        }
        strings.write_string(&state.b, string(glue))
        return compiler.StringValue(strings.to_string(state.b))
    case .cache_contains:
        assert(len(args) == 1)
        return compiler.BoolValue(string(args[0].(compiler.StringValue)) in state.l.cache)
    case .cache_set:
        assert(len(args) == 2)
        state.l.cache[string(args[0].(compiler.StringValue))] = args[1]
        return nil
    case .cache_get:
        assert(len(args) == 1)
        return state.l.cache[string(args[0].(compiler.StringValue))]
    case .init_http_server:
        assert(len(args) == 0)

        server_index: uint = len(state.l.http_servers)

        fields := make([]compiler.ExactValue, 3)
        fields[0] = compiler.SetHttpServerHandler{server_index}
        fields[1] = compiler.HttpServerListenAndServe{server_index}

        endpoint := net.Endpoint{net.IP4_Address{0, 0, 0, 0}, 8080}
        // TODO: Implement upper limit on number of ports to try
        for {
            // TODO: Log that the port is being tried
            socket, err := net.listen_tcp(endpoint)
            if err == nil {
                fields[2] = f64(endpoint.port)
                append(
                    &state.l.http_servers,
                    HttpServer {
                        socket,
                        compiler.RuntimeFunc {
                            compiler.CheckedFuncRef{utils.to_debug_value(max(uint))},
                            utils.Multi(compiler.ExactValue){nil},
                        },
                    },
                )
                return compiler.StructInitialisation(compiler.ExactValue){.HttpServer, fields}
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
        return compiler.StringValue(
            strings.repeat(string(args[0].(compiler.StringValue)), expect_int(args[1].(f64))),
        )
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

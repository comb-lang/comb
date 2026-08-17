package main

import "compiler"
import "core:fmt"
import "core:strings"
import "utils"

emit_js_func_call :: proc(s: ^GeneralEmitterState, c: compiler.CheckedFunctionCall) {
    emit_js_value(s, c.function^)
    strings.write_byte(&s.b, '(')
    for arg, i in c.args {
        emit_js_value(s, arg)
        if i + 1 < len(c.args) {
            strings.write_byte(&s.b, ',')
        }
    }
    strings.write_byte(&s.b, ')')
}

emit_js_comptime_value :: proc(s: ^GeneralEmitterState, v: compiler.CompileTimeValue) {
    switch comptime in v {
    case compiler.CompileTimeArray:
        strings.write_byte(&s.b, '[')
        for elem in comptime.elements {
            emit_js_comptime_value(s, elem)
            strings.write_byte(&s.b, ',')
        }
        strings.write_byte(&s.b, ']')
    case compiler.CompileTimeOrderedHashMapInitialisation:
        strings.write_string(&s.b, "new Map()")
        for key in comptime.order {
            strings.write_string(&s.b, ".set(\"")
            strings.write_string(&s.b, key)
            strings.write_string(&s.b, "\", ")
            emit_js_comptime_value(s, comptime.value[key])
            strings.write_byte(&s.b, ')')
        }
    case compiler.CastFunction:
        strings.write_string(&s.b, "/* TODO: Implement cast in JS emitter */ undefined")
    case compiler.BuiltinFunction:
        #partial switch comptime {
        case .print, .println:
            strings.write_string(&s.b, "console.log")
        case .eprint, .eprintln:
            strings.write_string(&s.b, "console.error")
        case:
            strings.write_string(&s.b, "builtin")
            strings.write_uint(&s.b, uint(comptime))
        }
    case compiler.CompileTimeStructInitialisation:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(comptime.func.return_type))
        strings.write_byte(&s.b, '(')
        first_arg := true
        for arg in comptime.args {
            if first_arg == false {
                strings.write_byte(&s.b, ',')
            }
            emit_js_comptime_value(s, arg)
            first_arg = false
        }
        strings.write_byte(&s.b, ')')

    case compiler.Func:
        strings.write_string(&s.b, "func")
        strings.write_uint(&s.b, comptime.ref.index)
        lambda_args_len := len(s.checked_funcs[comptime.ref.index].inline_stuff.scope0.variables)
        if lambda_args_len > 0 {
            strings.write_byte(&s.b, '(')
            for i in 0 ..< lambda_args_len {
                emit_variable(&s.b, comptime.lambda_args.d[i])
                strings.write_byte(&s.b, ',')
            }
            strings.write_byte(&s.b, ')')
        }
    case compiler.Type, compiler.UninitialisedOrderedHashMapType:
        panic("Unreachable")
    case compiler.GlobalValueWithGenericRef, compiler.Import:
        panic("Unreachable")
    case compiler.StringLiteralValue:
        strings.write_byte(&s.b, '"')
        for char in comptime {
            switch char {
            case '\n':
                strings.write_string(&s.b, "\\n")
            case '"':
                strings.write_string(&s.b, "\\\"")
            case '\\':
                strings.write_string(&s.b, "\\\\")
            case:
                strings.write_rune(&s.b, char)
            }
        }
        strings.write_byte(&s.b, '"')
    case compiler.BoolValue:
        strings.write_string(&s.b, comptime ? "true" : "false")
    case compiler.NumberValue:
        if comptime.is_negated {
            strings.write_byte(&s.b, '-')
        }
        strings.write_string(&s.b, utils.big_uint_to_string(comptime.whole_part))
        if comptime.fraction_part != "" {
            strings.write_byte(&s.b, '.')
            strings.write_string(&s.b, comptime.fraction_part)
        }
    }

}

// TODO: Deduplicate code between `emit_js_runtime_value` and `emit_js_value` / `emit_js_comptime_value`

emit_js_runtime_value :: proc(b: ^strings.Builder, value: RuntimeValue) {
    switch v in value {
    case RuntimeFunc:
        strings.write_string(b, "func")
        strings.write_uint(b, v.ref.index)
        if len(v.lambda_args) != 0 {
            strings.write_byte(b, '(')
            for arg in v.lambda_args {
                emit_js_runtime_value(b, arg)
                strings.write_byte(b, ',')
            }
            strings.write_byte(b, ')')
        }
    case RuntimeStruct:
        strings.write_byte(b, '{')
        for field, i in v.field_values {
            strings.write_string(b, "field")
            strings.write_int(b, i)
            strings.write_byte(b, ':')
            emit_js_runtime_value(b, field)
            strings.write_byte(b, ',')
        }
        strings.write_byte(b, '}')
    case RuntimeArray:
        strings.write_byte(b, '[')
        for elem in v.elems {
            emit_js_runtime_value(b, elem)
            strings.write_byte(b, ',')
        }
        strings.write_byte(b, ']')
    case f64:
        strings.write_f64(b, v, 'f')
    case bool:
        strings.write_string(b, v ? "true" : "false")
    case compiler.CastFunction,
         RuntimeIntOrderedHashMap,
         compiler.StructTypeInitFunc,
         compiler.BuiltinFunction,
         SetHttpServerHandler,
         HttpServerListenAndServe:
        panic("TODO")
    case RuntimeSumType:
        strings.write_string(b, "{variant:")
        strings.write_uint(b, uint(v.variant_index))
        if v.payload != nil {
            strings.write_string(b, ",payload:")
            emit_js_runtime_value(b, v.payload^)
        }
        strings.write_byte(b, '}')
    case RuntimeStringOrderedHashMap:
        strings.write_string(b, "new Map()")
        for key in v.order {
            strings.write_string(b, ".set(\"")
            strings.write_string(b, key)
            strings.write_string(b, "\", ")
            emit_js_runtime_value(b, v.hashmap[key])
            strings.write_byte(b, ')')
        }
    case RuntimeString:
        strings.write_byte(b, '"')
        strings.write_string(b, v.value)
        strings.write_byte(b, '"')
    case:
        panic("Unreachable")
    }
}

emit_js_map_keys_func :: proc(s: ^GeneralEmitterState, hash_map: compiler.CheckedValue) {
    strings.write_string(&s.b, "Map.prototype.keys.call(")
    emit_js_value(s, hash_map)
    strings.write_byte(&s.b, ')')
}

// Set `v` to `nil` to use `old`
emit_js_derivation :: proc(
    s: ^GeneralEmitterState,
    v: compiler.CheckedValue,
    subset_elems: []compiler.DerivationSubsetElement,
    alteration: compiler.DerivationAlteration,
) {
    if len(subset_elems) == 0 {
        switch alteration.kind {
        case .Replace:
            emit_js_value(s, alteration.arg^)
            return
        case .PipeThroughFunction:
            emit_js_value(s, alteration.arg^)
            strings.write_byte(&s.b, '(')
            if v == nil {
                strings.write_string(&s.b, "old")
            } else {
                emit_js_value(s, v)
            }
            strings.write_byte(&s.b, ')')
            return
        case:
            panic("Unreachable")
        }
    }

    switch elem in subset_elems[0] {
    case compiler.ArrayElementAccess:
        strings.write_string(&s.b, "with_update(")
        if v == nil {
            strings.write_string(&s.b, "old")
        } else {
            emit_js_value(s, v)
        }
        strings.write_byte(&s.b, ',')
        emit_js_value(s, elem.index)
    case compiler.StringOrderedHashMapAccess:
        strings.write_string(&s.b, "map_update(")
        if v == nil {
            strings.write_string(&s.b, "old")
        } else {
            emit_js_value(s, v)
        }
        strings.write_byte(&s.b, ',')
        emit_js_value(s, elem.key)
    case compiler.FieldAccess:
        strings.write_string(&s.b, "object_update(")
        if v == nil {
            strings.write_string(&s.b, "old")
        } else {
            emit_js_value(s, v)
        }
        strings.write_string(&s.b, ",\"field")
        strings.write_uint(&s.b, uint(elem.field_index))
        strings.write_byte(&s.b, '"')
    case:
        panic("Unreachable")
    }

    strings.write_byte(&s.b, ',')
    strings.write_string(&s.b, "(old) => ")
    emit_js_derivation(s, nil, subset_elems[1:], alteration)
    strings.write_byte(&s.b, ')')
}

emit_js_value :: proc(s: ^GeneralEmitterState, value: compiler.CheckedValue) {
    switch v in value {
    case compiler.SumTypeInitialisation:
        strings.write_string(&s.b, "{variant:")
        strings.write_uint(&s.b, uint(v.variant_index))
        if v.payload != nil {
            strings.write_string(&s.b, ",payload:")
            emit_js_value(s, v.payload^)
        }
        strings.write_byte(&s.b, '}')
    case compiler.LengthOfString:
        emit_js_value(s, v.str^)
        strings.write_string(&s.b, ".length")
    case compiler.OrderedHashMapInitialisation:
        strings.write_string(&s.b, "new Map()")
        for key in v.order {
            strings.write_string(&s.b, ".set(\"")
            strings.write_string(&s.b, key)
            strings.write_string(&s.b, "\", ")
            if key in v.compile_time_values {
                emit_js_comptime_value(s, v.compile_time_values[key])
            } else {
                emit_js_value(s, v.runtime_values[key])
            }
            strings.write_byte(&s.b, ')')
        }
    case compiler.CheckedDerivation:
        emit_js_derivation(s, v.base^, v.subset.elements, v.alteration)
    case compiler.ArrayLiteral:
        strings.write_byte(&s.b, '[')
        for segment in v.segments {
            switch seg in segment {
            case compiler.SingleElemSegment:
                emit_js_value(s, seg.elem)
            case compiler.InlineArraySegment:
                strings.write_string(&s.b, "...")
                emit_js_value(s, seg.array)
            case:
                panic("Unreachable")
            }
            strings.write_byte(&s.b, ',')
        }
        strings.write_byte(&s.b, ']')
    case compiler.KeysOfOrderedHashMapWithStringKey:
        emit_js_map_keys_func(s, v.hash_map^)
    case compiler.KeysOfOrderedHashMapWithIntKey:
        emit_js_map_keys_func(s, v.hash_map^)
    case compiler.CheckedOrderedHashMapAccess:
        strings.write_string(&s.b, "Map.prototype.get.call(")
        emit_js_value(s, v.hash_map^)
        strings.write_byte(&s.b, ',')
        emit_js_value(s, v.key^)
        strings.write_byte(&s.b, ')')
    case compiler.CompileTimeValue:
        emit_js_comptime_value(s, v)
    case compiler.ToString:
        strings.write_string(&s.b, "String(")
        emit_js_value(s, v.value^)
        strings.write_byte(&s.b, ')')
    case compiler.CheckedFieldAccess:
        emit_js_value(s, v.value^)
        strings.write_string(&s.b, ".field")
        strings.write_uint(&s.b, uint(v.field_index))
    case compiler.LengthOfArray:
        emit_js_value(s, v.array^)
        strings.write_string(&s.b, ".length")
    case compiler.LengthOfOrderedHashMapWithStringKey:
        panic("TODO")
    case compiler.LengthOfOrderedHashMapWithIntKey:
        panic("TODO")
    case compiler.CheckedIndexedAccess:
        emit_js_value(s, v.base^)
        if v.i.end_index != nil {
            strings.write_string(&s.b, ".slice(")
            emit_js_value(s, v.i.start_index^)
            strings.write_byte(&s.b, ',')
            emit_js_value(s, v.i.end_index^)
            strings.write_byte(&s.b, ')')
        } else {
            strings.write_byte(&s.b, '[')
            emit_js_value(s, v.i.start_index^)
            strings.write_byte(&s.b, ']')
        }
    case compiler.CheckedFunctionCall:
        emit_js_func_call(s, v)
    case compiler.StructTypeInitFunc:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(v.return_type))
    case compiler.BooleanNotValue:
        strings.write_byte(&s.b, '(')
        strings.write_byte(&s.b, '!')
        emit_js_value(s, v^)
        strings.write_byte(&s.b, ')')
    case compiler.StringsAreEqual:
        strings.write_byte(&s.b, '(')
        emit_js_value(s, v.str0^)
        strings.write_string(&s.b, "===")
        emit_js_value(s, v.str1^)
        strings.write_byte(&s.b, ')')
    case compiler.CheckedJoinedValues:
        if v.join_method == .In {
            strings.write_string(&s.b, "in_map(")
            emit_js_value(s, v.val0^)
            strings.write_string(&s.b, ", ")
            emit_js_value(s, v.val1^)
            strings.write_string(&s.b, ")")
            return
        }
        strings.write_byte(&s.b, '(')
        emit_js_value(s, v.val0^)
        switch v.join_method {
        case .Append, .Concat, .Arrow, .In:
            panic("Unreachable")
        case .BooleanAnd:
            strings.write_string(&s.b, "&&")
        case .BooleanOr:
            strings.write_string(&s.b, "||")
        case .IsEqual:
            strings.write_string(&s.b, "===")
        case .IsNotEqual:
            strings.write_string(&s.b, "!==")
        case .IsGreaterThan:
            strings.write_byte(&s.b, '>')
        case .IsGreaterThanOrEqual:
            strings.write_string(&s.b, ">=")
        case .IsLessThan:
            strings.write_byte(&s.b, '<')
        case .IsLessThanOrEqual:
            strings.write_string(&s.b, "<=")
        case .Addition, .StringConcat:
            strings.write_byte(&s.b, '+')
        case .Subtraction:
            strings.write_byte(&s.b, '-')
        case .Multiplication:
            strings.write_byte(&s.b, '*')
        case .Division:
            strings.write_byte(&s.b, '/')
        case .Modulo:
            strings.write_byte(&s.b, '%')
        }
        emit_js_value(s, v.val1^)
        strings.write_byte(&s.b, ')')
    case compiler.VariableRef:
        emit_variable(&s.b, v)
    }
}

emit_js_global_type :: proc(s: ^GeneralEmitterState, index: int) {
    name := fmt.aprintf("Type%d", index)
    defer delete(name)
    switch t in s.types.m.keys[index].key {
    case compiler.GlobalType:
    case compiler.OrderedHashMapTypeWithStringKey:
    case compiler.OrderedHashMapTypeWithIntKey:
    case compiler.ArrayType:
    case compiler.FuncType:
    case compiler.GenericTypeValue:
    case compiler.SumType:
    case compiler.StructType:
        strings.write_string(&s.b, "function init_")
        strings.write_string(&s.b, name)
        strings.write_byte(&s.b, '(')
        first_field := true
        for _, i in t.m.keys {
            if first_field {
                first_field = false
            } else {
                strings.write_byte(&s.b, ',')
            }
            strings.write_string(&s.b, "field")
            strings.write_int(&s.b, i)
        }
        strings.write_string(&s.b, ") {return {")
        first_field = true
        for _, i in t.m.keys {
            if first_field {
                first_field = false
            } else {
                strings.write_byte(&s.b, ',')
            }
            strings.write_string(&s.b, "field")
            strings.write_int(&s.b, i)
        }
        strings.write_string(&s.b, "}}")
    }
}

emit_js_block_body :: proc(
    s: ^GeneralEmitterState,
    nesting_level: uint,
    body: []compiler.CheckedStatement,
    loc := #caller_location,
) {
    for statement in body {
        switch stmt in statement {
        case compiler.UnreachableStatement:
            strings.write_string(&s.b, "throw new Error(\"Unreachable\")")
        case compiler.CheckedFunctionCall:
            emit_js_func_call(s, stmt)
            strings.write_byte(&s.b, ';')
        case compiler.CheckedReturn:
            strings.write_string(&s.b, "return ")
            emit_js_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        case compiler.CheckedIf:
            strings.write_string(&s.b, "if (")
            emit_js_value(s, stmt.condition)
            strings.write_string(&s.b, "){")
            emit_js_block(s, nesting_level + 1, stmt.if_block.variables, stmt.if_block.body)
            strings.write_string(&s.b, "} else {")
            emit_js_block(s, nesting_level + 1, stmt.else_block.variables, stmt.else_block.body)
            strings.write_byte(&s.b, '}')
        case compiler.CheckedMatch:
            strings.write_string(&s.b, "switch (")
            emit_variable(&s.b, stmt.value)
            strings.write_string(&s.b, ".variant) {")
            for tag_variant_index, branch in stmt.branches {
                strings.write_string(&s.b, "case ")
                strings.write_uint(&s.b, uint(tag_variant_index))
                strings.write_string(&s.b, ": {")
                emit_js_block_head(s, nesting_level + 1, branch.block.variables)
                if value_var, has_value_var := branch.value_var.(compiler.VariableRef);
                   has_value_var {
                    emit_variable(&s.b, value_var)
                    strings.write_string(&s.b, " = ")
                    emit_variable(&s.b, stmt.value) // TODO: Maybe create a copy without the `variant` field?
                    strings.write_byte(&s.b, ';')
                }
                emit_js_block_body(s, nesting_level + 1, branch.block.body)
                strings.write_string(&s.b, "break;}")
            }
            strings.write_string(&s.b, "}")
        case compiler.CheckedLoop:
            strings.write_byte(&s.b, '{')
            emit_js_block(s, nesting_level + 1, stmt.variables, stmt.enter)
            strings.write_string(&s.b, "loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, ": while (true) {loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "_body: do {")
            emit_js_block(s, nesting_level + 1, nil, stmt.body)
            strings.write_string(&s.b, "} while (false)")
            emit_js_block(s, nesting_level + 1, nil, stmt.continue_code)
            strings.write_string(&s.b, "}}")
        case compiler.CheckedLoopControlFlow:
            strings.write_string(&s.b, "break loop")
            strings.write_uint(&s.b, stmt.loop_index)
            switch stmt.kind {
            case .Continue:
                strings.write_string(&s.b, "_body;")
            case .Break:
                strings.write_byte(&s.b, ';')
            }
        /*
        case CheckedArrayMutation:
            emit_variable(&s.b, stmt.variable)
            strings.write_string(&s.b, "=[")
            first_segment := true
            for segment in stmt.segments {
                if first_segment {
                    first_segment = false
                } else {
                    strings.write_byte(&s.b, ',')
                }
                switch segment_value in segment {
                case SingleElemSegment:
                    emit_js_value(s, segment_value.elem)
                case InlineArraySegment:
                    strings.write_string(&s.b, "...")
                    emit_js_value(s, segment_value.array)
                }
            }
            strings.write_string(&s.b, "];")
            */
        case compiler.CheckedAssignment:
            emit_variable(&s.b, stmt.dest)
            strings.write_byte(&s.b, '=')
            emit_js_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        }
    }
}

emit_js_block_head :: proc(
    s: ^GeneralEmitterState,
    nesting_level: uint,
    variables: []compiler.Type,
    loc := #caller_location,
) {
    for _, index in variables {
        strings.write_string(&s.b, "var ")
        emit_variable(&s.b, compiler.VariableRef{nesting_level, uint(index)})
        strings.write_byte(&s.b, ';')
    }
}

emit_js_block :: proc(
    s: ^GeneralEmitterState,
    nesting_level: uint,
    variables: []compiler.Type,
    body: []compiler.CheckedStatement,
    loc := #caller_location,
) {
    utils.call(loc, "emit_js_block", "")
    emit_js_block_head(s, nesting_level, variables)
    emit_js_block_body(s, nesting_level, body)
}

emit_javascript :: proc(
    types: compiler.Types,
    checked_functions: []compiler.CheckedFunction,
    loc := #caller_location,
) -> strings.Builder {
    utils.call(loc, "emit_javascript", "", enable_debug = utils.debug_emitter)
    s := GeneralEmitterState{strings.builder_make(), types, checked_functions}
    strings.write_string(
        &s.b,
        "function builtin22(num) {" +
        "  if (!Number.isInteger(num)) {" +
        "    throw new Error(\"Attempted to convert float to UInt\")" +
        "  }" +
        "  if (num < 0) {" +
        "    throw new Error(\"Attempted to convert negative number to UInt\")" +
        "  }" +
        "  return num" +
        "}" +
        "function in_map(a, b) {return Map.prototype.has.call(b, a)}" +
        "function with_update(value, key, func) {return value.with(key, func(value[key]))}" +
        "function object_update(object, field, func) {" +
        "  const shallow_copy = {...object};" +
        "  shallow_copy[field] = func(shallow_copy[field]);" +
        "  return shallow_copy;" +
        "}" +
        "function map_update(map, key, func) {return new Map(map).set(key, func(map.get(key)))}",
    )

    for _, index in types.m.keys {
        emit_js_global_type(&s, index)
    }

    /*
    for _, i in c.types.values {
        tv := c.types.values[i].value
        gen_value, ok := tv.(GenericTypeValue)
        if !ok || !gen_value.is_initialised {
            continue
        }
        name := fmt.aprintf(
            generic_name_format,
            gen_value.generic_type_index,
            gen_value.generic_arg.index,
        )
        defer delete(name)
        emit_js_global_type(&s, name, gen_value.initialised_type)
    }
    */

    for func, index in checked_functions {
        utils.debug("emitting function index %d", index)
        strings.write_string(&s.b, "const func")
        strings.write_int(&s.b, index)
        strings.write_byte(&s.b, '=')
        if len(func.inline_stuff.scope0.variables) > 0 {
            strings.write_byte(&s.b, '(')
            for _, i in func.inline_stuff.scope0.variables {
                emit_variable(&s.b, compiler.VariableRef{0, uint(i)})
                strings.write_byte(&s.b, ',')
            }
            strings.write_string(&s.b, ") =>")
        }
        strings.write_byte(&s.b, '(')
        info := compiler.get_type(types, func.type).key.(compiler.FuncType)
        first_arg := true
        for _, i in info.args {
            if first_arg {
                first_arg = false
            } else {
                strings.write_byte(&s.b, ',')
            }
            emit_variable(&s.b, compiler.VariableRef{1, uint(i)})
        }
        strings.write_string(&s.b, ") => {")
        emit_js_block(&s, 2, func.variables, func.body.v)
        strings.write_string(&s.b, "};")
    }

    return s.b
}

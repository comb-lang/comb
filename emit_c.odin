package main

import "core:fmt"
import "core:strings"

GeneralEmitterState :: struct {
    b:             strings.Builder,
    types:         Types,
    checked_funcs: []CheckedFunction,
}

CEmitterState :: struct {
    forward_struct_definitions:    strings.Builder, // Several `typedef struct TypeStruct Type;`
    sum_type_definitions:          strings.Builder,
    other_type_definitions:        strings.Builder,
    sum_type_initialisation_funcs: strings.Builder,
    using s:                       GeneralEmitterState,
}

variable_format :: "nesting_level%dindex%d"

emit_variable :: proc(b: ^strings.Builder, variable: VariableRef) {
    var := fmt.aprintf(variable_format, variable.nesting_level, variable.index)
    strings.write_string(b, var)
    delete_string(var)
}

// Does not include the `struct`
emit_struct_type :: proc(b: ^strings.Builder, type: StructType, loc := #caller_location) {
    when debug_emitter {
        print_call(loc, "emit_struct_type")
    }
    strings.write_byte(b, '{')
    for _, index in type.m.keys {
        name := fmt.aprintf("field%d", index)
        emit_type(b, name, type.types.d[index])
        delete_string(name)
        strings.write_byte(b, ';')
    }
    strings.write_byte(b, '}')
}

emit_type :: proc(b: ^strings.Builder, name: string, type: Type) {
    #partial switch type {
    case .Bool:
        strings.write_string(b, "bool")
    case .String:
        strings.write_string(b, "char*")
    case .Int, .UInt, .Float:
        strings.write_string(b, "double")
    case .Char:
        strings.write_string(b, "uint8_t")
    case .Any:
        strings.write_string(b, "void*")
    case:
        if type > Type.MaxIndex {
            panic(fmt.aprintf("Type is %v", type))
        }
        strings.write_string(b, "Type")
        strings.write_uint(b, uint(type))
    }
    strings.write_byte(b, ' ')
    strings.write_string(b, name)
}

emit_c_func_call :: proc(s: ^CEmitterState, c: CheckedFunctionCall) {
    emit_c_value(s, c.function^)
    strings.write_byte(&s.b, '(')
    for arg, i in c.args {
        emit_c_value(s, arg)
        if i + 1 < len(c.args) {
            strings.write_byte(&s.b, ',')
        }
    }
    strings.write_byte(&s.b, ')')
}

emit_c_comptime_value :: proc(s: ^CEmitterState, value: CompileTimeValue) {
    switch comptime in value {
    case CompileTimeArray:
        panic("TODO")
    case CompileTimeOrderedHashMapInitialisation:
        panic("TODO")
    case CastFunction:
        panic("TODO")
    case BuiltinFunction:
        strings.write_string(&s.b, "builtin")
        strings.write_uint(&s.b, uint(comptime))
    case CompileTimeStructInitialisation:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(comptime.func.return_type))
        strings.write_string(&s.b, "(")
        first_arg := true
        for arg in comptime.args {
            if first_arg == false {
                strings.write_byte(&s.b, ',')
            }
            emit_c_comptime_value(s, arg)
            first_arg = false
        }
        strings.write_string(&s.b, ")")
    case Func:
        // TODO: Handle comptime.lambda_args
        strings.write_string(&s.b, "func")
        strings.write_uint(&s.b, comptime.ref.index)
    case NumberValue:
        if comptime.is_negated {
            strings.write_byte(&s.b, '-')
        }
        strings.write_string(&s.b, big_uint_to_string(comptime.whole_part))
        if comptime.fraction_part != "" {
            strings.write_byte(&s.b, '.')
            strings.write_string(&s.b, comptime.fraction_part)
        }
    case StringLiteralValue:
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
    case BoolValue:
        strings.write_string(&s.b, comptime ? "true" : "false")
    case Type:
        panic("Unreachable")
    case GlobalValueWithGenericRef, UninitialisedOrderedHashMapType, Import:
        panic("Unreachable")
    }
}

emit_c_value :: proc(s: ^CEmitterState, v: CheckedValue) {
    switch value in v {
    case LengthOfString:
        panic("TODO")
    case OrderedHashMapInitialisation:
        panic("TODO")
    case ArrayLiteral:
        panic("TODO: Handle array literal in C emitter")
    case CheckedDerivation:
        panic("TODO: Handle checked derivation in C emitter")
    case CheckedOrderedHashMapAccess,
         KeysOfOrderedHashMapWithStringKey,
         KeysOfOrderedHashMapWithIntKey:
        panic("TODO")
    case CompileTimeValue:
        emit_c_comptime_value(s, value)
    case ToString:
        strings.write_string(&s.b, "asprintf_value(")
        switch value.from_type {
        case .BoolType:
            strings.write_string(&s.b, "\"%b\"")
        case .IntType, .UIntType, .FloatType:
            // TODO: Only include decimal when it's a float
            strings.write_string(&s.b, "\"%f\"")
        case .CharType:
            strings.write_string(&s.b, "\"%\" PRIu8")
        }
        strings.write_byte(&s.b, ',')
        emit_c_value(s, value.value^)
        strings.write_string(&s.b, ")")
    case CheckedFieldAccess:
        emit_c_value(s, value.value^)
        strings.write_string(&s.b, ".field")
        strings.write_uint(&s.b, uint(value.field_index))
    //case CheckedJsFunctionCall:
    //    panic("Internal error: JsFunctionCall received by C emitter")
    //case ArrayValue:
    //    panic("Internal error: Unexpected array value")
    case LengthOfArray:
        emit_c_value(s, value.array^)
        strings.write_string(&s.b, ".length")
    case LengthOfOrderedHashMapWithStringKey:
        panic("TODO")
    case LengthOfOrderedHashMapWithIntKey:
        panic("TODO")
    case CheckedIndexedAccess:
        if value.base_type == .String {
            panic("TODO")
        }
        emit_c_value(s, value.base^)
        strings.write_string(&s.b, ".elems[(int)")
        emit_c_value(s, value.i.start_index^)
        if value.i.end_index != nil {
            panic("TODO")
        }
        strings.write_byte(&s.b, ']')
    case CheckedFunctionCall:
        emit_c_func_call(s, value)
    //case CheckedStructTypeInitialisation:
    //    emit_type(s, "", value.type)
    //    strings.write_byte(&s.b, '{')
    //    first_value := true
    //    for v in value.args {
    //        if !first_value {
    //            strings.write_byte(&s.b, ',')
    //        }
    //        first_value = false
    //        emit_c_value(s, v)
    //    }
    //    strings.write_byte(&s.b, '}')
    case StructTypeInitFunc:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(value.return_type))
    case SumTypeInitFunc:
        strings.write_string(&s.b, "init_Type")
        strings.write_uint(&s.b, uint(value.sum_type))
        strings.write_string(&s.b, "Variant")
        strings.write_uint(&s.b, uint(value.variant_index))
    case BooleanNotValue:
        strings.write_byte(&s.b, '(')
        strings.write_byte(&s.b, '!')
        emit_c_value(s, value^)
        strings.write_byte(&s.b, ')')
    case StringsAreEqual:
        strings.write_string(&s.b, "(strcmp(")
        emit_c_value(s, value.str0^)
        strings.write_byte(&s.b, ',')
        emit_c_value(s, value.str1^)
        strings.write_string(&s.b, ")==0)")
    case CheckedJoinedValues:
        if value.join_method == .StringConcat {
            strings.write_string(&s.b, "asprintf_value(\"%s%s\",")
            emit_c_value(s, value.val0^)
            strings.write_byte(&s.b, ',')
            emit_c_value(s, value.val1^)
            strings.write_byte(&s.b, ')')
            return
        } else if value.join_method == .In {
            strings.write_string(&s.b, "in_map(")
            emit_c_value(s, value.val0^)
            strings.write_byte(&s.b, ',')
            emit_c_value(s, value.val1^)
            strings.write_string(&s.b, ")")
            return
        }
        strings.write_byte(&s.b, '(')
        emit_c_value(s, value.val0^)
        switch value.join_method {
        case .Append, .Concat, .StringConcat, .Colon, .Arrow, .In:
            panic("Unreachable")
        case .BooleanAnd:
            strings.write_string(&s.b, "&&")
        case .BooleanOr:
            strings.write_string(&s.b, "||")
        case .IsEqual:
            strings.write_string(&s.b, "==")
        case .IsNotEqual:
            strings.write_string(&s.b, "!=")
        case .IsGreaterThan:
            strings.write_byte(&s.b, '>')
        case .IsGreaterThanOrEqual:
            strings.write_string(&s.b, ">=")
        case .IsLessThan:
            strings.write_byte(&s.b, '<')
        case .IsLessThanOrEqual:
            strings.write_string(&s.b, "<=")
        case .Addition:
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
        emit_c_value(s, value.val1^)
        strings.write_byte(&s.b, ')')
    case VariableRef:
        emit_variable(&s.b, value)
    //case CheckedReadFile:
    //    strings.write_string(&s.b, "compiler_read_file(")
    //    emit_c_value(s, value.file_name^)
    //    strings.write_byte(&s.b, ')')
    //case CheckedReadLine:
    //    strings.write_string(&s.b, "readline(")
    //    emit_c_value(s, value.prompt^)
    //    strings.write_byte(&s.b, ')')
    }
}

emit_c_block_head :: proc(
    s: ^CEmitterState,
    nesting_level: uint,
    variables: []Type,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block_head")
    }
    for type, index in variables {
        name := fmt.aprintf(variable_format, nesting_level, index)
        emit_type(&s.b, name, type)
        delete_string(name)
        strings.write_byte(&s.b, ';')
    }
}

unreachable_c_code :: "fprintf(stderr, \"Unreachable\");exit(1);"

emit_c_block_body :: proc(
    s: ^CEmitterState,
    nesting_level: uint,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block_body")
        print_arg("nesting_level", nesting_level)
        print_arg("body", body)
    }
    for statement in body {
        switch stmt in statement {
        //case CheckedJsFunctionCall, CheckedJsAssignment:
        //    panic("Internal error: JS received by C emitter")
        case UnreachableStatement:
            strings.write_string(&s.b, unreachable_c_code)
        case CheckedFunctionCall:
            emit_c_func_call(s, stmt)
            strings.write_byte(&s.b, ';')
        case CheckedReturn:
            strings.write_string(&s.b, "return ")
            emit_c_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        case CheckedIf:
            strings.write_string(&s.b, "if (")
            emit_c_value(s, stmt.condition)
            strings.write_string(&s.b, "){")
            emit_c_block(s, nesting_level + 1, stmt.if_block.variables, stmt.if_block.body)
            strings.write_string(&s.b, "} else {")
            emit_c_block(s, nesting_level + 1, stmt.else_block.variables, stmt.else_block.body)
            strings.write_byte(&s.b, '}')
        case CheckedMatch:
            strings.write_string(&s.b, "switch (")
            emit_variable(&s.b, stmt.value)
            strings.write_string(&s.b, ".variant) {")
            for branch, i in stmt.branches {
                strings.write_string(&s.b, "case ")
                strings.write_int(&s.b, i)
                strings.write_string(&s.b, ": {")
                emit_c_block_head(s, nesting_level + 1, branch.block.variables)
                if value_var, has_value_var := branch.value_var.(VariableRef); has_value_var {
                    emit_variable(&s.b, value_var)
                    strings.write_string(&s.b, " = *")
                    emit_variable(&s.b, stmt.value)
                    strings.write_string(&s.b, ".payload.variant")
                    strings.write_int(&s.b, i)
                    strings.write_byte(&s.b, ';')
                }
                emit_c_block_body(s, nesting_level + 1, branch.block.body)
                strings.write_string(&s.b, "break;}")
            }
            strings.write_string(&s.b, "default:" + unreachable_c_code + "}")
        case CheckedLoop:
            strings.write_byte(&s.b, '{')
            emit_c_block(s, nesting_level + 1, stmt.variables, stmt.enter)
            strings.write_string(&s.b, "while (1) {")
            emit_c_block(s, nesting_level + 1, nil, stmt.body)
            strings.write_string(&s.b, "loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "continue:")
            emit_c_block(s, nesting_level + 1, nil, stmt.continue_code)
            strings.write_string(&s.b, "}}loop")
            strings.write_uint(&s.b, stmt.loop_index)
            strings.write_string(&s.b, "end:;")
        case CheckedLoopControlFlow:
            strings.write_string(&s.b, "goto loop")
            strings.write_uint(&s.b, stmt.loop_index)
            switch stmt.kind {
            case .Continue:
                strings.write_string(&s.b, "continue;")
            case .Break:
                strings.write_string(&s.b, "end;")
            }
        /*
        case CheckedArrayMutation:
            if stmt.variable_type.length == 0 {
                emit_variable(&s.b, stmt.variable)
                strings.write_string(&s.b, ".length = 0;")
                number_of_single_elem_segments := 0
                for segment in stmt.segments {
                    switch segment_value in segment {
                    case SingleElemSegment:
                        number_of_single_elem_segments += 1
                    case InlineArraySegment:
                        emit_variable(&s.b, stmt.variable)
                        strings.write_string(&s.b, ".length += ")
                        emit_c_value(s, segment_value.array_length)
                        strings.write_byte(&s.b, ';')
                    }
                }
                if number_of_single_elem_segments > 0 {
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".length += ")
                    strings.write_int(&s.b, number_of_single_elem_segments)
                    strings.write_byte(&s.b, ';')
                }
                emit_variable(&s.b, stmt.variable)
                strings.write_string(&s.b, ".elems = malloc(")
                emit_variable(&s.b, stmt.variable)
                strings.write_string(&s.b, ".length * sizeof(")
                emit_type(&s.b, "", stmt.variable_type.item_type)
                strings.write_string(&s.b, "));")
            }
            strings.write_string(&s.b, "{uint64_t index = 0;")
            for segment in stmt.segments {
                switch segment_value in segment {
                case SingleElemSegment:
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".elems[index] = ")
                    emit_c_value(s, segment_value.elem)
                    strings.write_string(&s.b, "; index += 1;")
                case InlineArraySegment:
                    strings.write_string(&s.b, "{uint64_t index2 = 0; while (index2 < ")
                    emit_c_value(s, segment_value.array_length)
                    strings.write_string(&s.b, ") {")
                    emit_variable(&s.b, stmt.variable)
                    strings.write_string(&s.b, ".elems[index+index2] = ")
                    emit_c_value(s, segment_value.array)
                    strings.write_string(&s.b, ".elems[index2];index2 += 1;}index += index2;}")
                }
            }
            strings.write_byte(&s.b, '}')
            */
        case CheckedAssignment:
            emit_variable(&s.b, stmt.dest)
            strings.write_byte(&s.b, '=')
            emit_c_value(s, stmt.value)
            strings.write_byte(&s.b, ';')
        }
    }
}

emit_c_block :: proc(
    s: ^CEmitterState,
    nesting_level: uint,
    variables: []Type,
    body: []CheckedStatement,
    loc := #caller_location,
) {
    when debug_emitter {
        print_call(loc, "emit_c_block")
    }
    emit_c_block_head(s, nesting_level, variables)
    emit_c_block_body(s, nesting_level, body)
}

emit_forward_struct_definition :: proc(s: ^CEmitterState, name: string) {
    strings.write_string(&s.forward_struct_definitions, "typedef struct ")
    strings.write_string(&s.forward_struct_definitions, name)
    strings.write_string(&s.forward_struct_definitions, "Struct ")
    strings.write_string(&s.forward_struct_definitions, name)
    strings.write_byte(&s.forward_struct_definitions, ';')
}

emit_c_global_type :: proc(s: ^CEmitterState, index: int, loc := #caller_location) {
    when debug_emitter {
        print_call(loc, "emit_c_global_type")
    }
    name := fmt.aprintf("Type%d", index)
    defer delete(name)
    switch type in s.types.m.keys[index].key {
    case GlobalType:
        panic("TODO")
    case ArrayType:
        strings.write_string(&s.other_type_definitions, "struct ")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, "Struct")
        if type.length != 0 {
            strings.write_byte(&s.other_type_definitions, '{')
            emit_type(&s.other_type_definitions, "", type.item_type)
            strings.write_string(&s.other_type_definitions, " elems[")
            strings.write_uint(&s.other_type_definitions, uint(type.length))
            strings.write_string(&s.other_type_definitions, "];};")
        } else {
            strings.write_string(&s.other_type_definitions, "{uint64_t length;")
            emit_type(&s.other_type_definitions, "", type.item_type)
            strings.write_string(&s.other_type_definitions, "* elems;};")
        }
        emit_forward_struct_definition(s, name)
    case OrderedHashMapTypeWithStringKey:
        emit_forward_struct_definition(s, name)
        strings.write_string(&s.other_type_definitions, "typedef struct ")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(
            &s.other_type_definitions,
            "Struct {/* TODO: Ordered hash map with String key */}",
        )
        strings.write_string(&s.other_type_definitions, name)
        strings.write_byte(&s.other_type_definitions, ';')
    case OrderedHashMapTypeWithIntKey:
        emit_forward_struct_definition(s, name)
        strings.write_string(&s.other_type_definitions, "typedef struct ")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(
            &s.other_type_definitions,
            "Struct {/* TODO: Ordered hash map with Int key */}",
        )
        strings.write_string(&s.other_type_definitions, name)
        strings.write_byte(&s.other_type_definitions, ';')
    case FuncType:
        strings.write_string(&s.other_type_definitions, "typedef ")
        switch len(type.return_types) {
        case 0:
            strings.write_string(&s.other_type_definitions, "void")
        case 1:
            emit_type(&s.other_type_definitions, "", type.return_types[0])
        case:
            panic("TODO")
        }
        strings.write_string(&s.other_type_definitions, " (*")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, ")(")
        is_first_arg := true
        for arg, i in type.args {
            if !is_first_arg {
                strings.write_byte(&s.other_type_definitions, ',')
            }
            arg_name := fmt.aprintf("arg%d", i)
            defer delete(arg_name)
            emit_type(&s.other_type_definitions, arg_name, arg)
            is_first_arg = false
        }
        strings.write_string(&s.other_type_definitions, ");")
    case GenericTypeValue:
        strings.write_string(&s.other_type_definitions, "typedef ")
        emit_type(&s.other_type_definitions, name, s.types.values.d[index].type)
        strings.write_byte(&s.other_type_definitions, ';')
    case SumType:
        // Main struct type
        strings.write_string(&s.sum_type_definitions, "struct ")
        strings.write_string(&s.sum_type_definitions, name)
        strings.write_string(&s.sum_type_definitions, "Struct{uint64_t variant; union {")
        for _, i in type.m.keys {
            strings.write_string(&s.sum_type_definitions, "Type")
            strings.write_uint(&s.sum_type_definitions, uint(type.payloads.d[i]))
            strings.write_string(&s.sum_type_definitions, "* variant")
            strings.write_int(&s.sum_type_definitions, i)
            strings.write_byte(&s.sum_type_definitions, ';')
        }
        strings.write_string(&s.sum_type_definitions, "} payload;};")

        // Type def
        emit_forward_struct_definition(s, name)

        // Variant funcs
        for _, i in type.m.keys {
            payload_type := type.payloads.d[i]
            payload := get_type(s.types, payload_type).key.(StructType)
            strings.write_string(&s.sum_type_initialisation_funcs, name)
            strings.write_string(&s.sum_type_initialisation_funcs, " init_")
            strings.write_string(&s.sum_type_initialisation_funcs, name)
            strings.write_string(&s.sum_type_initialisation_funcs, "Variant")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_byte(&s.sum_type_initialisation_funcs, '(')
            first_arg := true
            for _, j in payload.m.keys {
                if !first_arg {
                    strings.write_byte(&s.sum_type_initialisation_funcs, ',')
                }
                first_arg = false
                field_name := fmt.aprintf("field%d", j)
                defer delete_string(field_name)
                emit_type(&s.sum_type_initialisation_funcs, field_name, payload.types.d[j])
            }
            strings.write_string(&s.sum_type_initialisation_funcs, ") {")
            strings.write_string(&s.sum_type_initialisation_funcs, name)
            strings.write_string(&s.sum_type_initialisation_funcs, " out;out.variant = ")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_string(&s.sum_type_initialisation_funcs, "; out.payload.variant")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_string(&s.sum_type_initialisation_funcs, " = malloc(sizeof(Type")
            strings.write_uint(&s.sum_type_initialisation_funcs, uint(payload_type))
            strings.write_string(&s.sum_type_initialisation_funcs, "));")
            strings.write_string(&s.sum_type_initialisation_funcs, "*out.payload.variant")
            strings.write_int(&s.sum_type_initialisation_funcs, i)
            strings.write_string(&s.sum_type_initialisation_funcs, " = init_Type")
            strings.write_uint(&s.sum_type_initialisation_funcs, uint(payload_type))
            strings.write_string(&s.sum_type_initialisation_funcs, "(")
            first_arg = true
            for _, j in payload.m.keys {
                if !first_arg {
                    strings.write_byte(&s.sum_type_initialisation_funcs, ',')
                }
                first_arg = false
                strings.write_string(&s.sum_type_initialisation_funcs, "field")
                strings.write_int(&s.sum_type_initialisation_funcs, j)
            }
            strings.write_string(&s.sum_type_initialisation_funcs, ");return out;}")
        }
    case StructType:
        // Type def
        emit_forward_struct_definition(s, name)

        // Struct def
        strings.write_string(&s.other_type_definitions, "struct ")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, "Struct")
        emit_struct_type(&s.other_type_definitions, type)
        strings.write_byte(&s.other_type_definitions, ';')
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, " init_")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_byte(&s.other_type_definitions, '(')
        first_field := true
        for _, i in type.m.keys {
            if first_field == false {
                strings.write_byte(&s.other_type_definitions, ',')
            } else {
                first_field = false
            }
            field_name := fmt.aprintf("field%d", i)
            defer delete(field_name)
            emit_type(&s.other_type_definitions, field_name, type.types.d[i])
        }
        strings.write_string(&s.other_type_definitions, ") {")
        strings.write_string(&s.other_type_definitions, name)
        strings.write_string(&s.other_type_definitions, " out;")
        for _, i in type.m.keys {
            strings.write_string(&s.other_type_definitions, "out.field")
            strings.write_int(&s.other_type_definitions, i)
            strings.write_string(&s.other_type_definitions, "=field")
            strings.write_int(&s.other_type_definitions, i)
            strings.write_byte(&s.other_type_definitions, ';')
        }
        strings.write_string(&s.other_type_definitions, "return out;}")
    }
}

emit_function_head :: proc(s: ^CEmitterState, func_index: int, type: Type) {
    when debug_emitter {
        debug("emitting function index %d", func_index)
    }
    info := get_type(s.types, type).key.(FuncType)
    switch len(info.return_types) {
    case 0:
        strings.write_string(&s.b, "void")
    case 1:
        emit_type(&s.b, "", info.return_types[0])
    case:
        panic("Unreachable")
    }
    strings.write_string(&s.b, " func")
    strings.write_int(&s.b, func_index)
    strings.write_byte(&s.b, '(')
    first_arg := true
    for arg, i in info.args {
        if !first_arg {
            strings.write_byte(&s.b, ',')
        }
        name := fmt.aprintf(variable_format, 1, i)
        emit_type(&s.b, name, arg)
        delete_string(name)
        first_arg = false
    }
    strings.write_byte(&s.b, ')')
}

emit_c :: proc(
    types: Types,
    checked_funcs: []CheckedFunction,
    main_func_ref: CheckedFuncRef,
) -> []byte {
    s := CEmitterState {
        strings.builder_make(),
        strings.builder_make(),
        strings.builder_make(),
        strings.builder_make(),
        GeneralEmitterState{strings.builder_make(), types, checked_funcs},
    }

    for _, i in types.m.keys {
        emit_c_global_type(&s, i)
    }

    for func, index in checked_funcs {
        emit_function_head(&s, index, func.type)
        strings.write_byte(&s.b, ';')
    }

    for func, index in checked_funcs {
        emit_function_head(&s, index, func.type)
        strings.write_byte(&s.b, '{')
        emit_c_block(&s, 2, func.variables, func.body)
        strings.write_byte(&s.b, '}')
    }

    strings.write_string(&s.b, "int main() {int ret = func")
    strings.write_uint(&s.b, main_func_ref.index)
    strings.write_string(&s.b, "();")
    strings.write_string(&s.b, "return ret;}")

    out := strings.builder_make()
    strings.write_string(&out, string(#load("glue.c")) + string(#load("ordered_hashmap.c")))
    strings.write_string(&out, strings.to_string(s.forward_struct_definitions))
    strings.write_string(&out, strings.to_string(s.sum_type_definitions))
    strings.write_string(&out, strings.to_string(s.other_type_definitions))
    strings.write_string(&out, strings.to_string(s.sum_type_initialisation_funcs))
    strings.write_string(&out, strings.to_string(s.b))

    strings.builder_destroy(&s.forward_struct_definitions)
    strings.builder_destroy(&s.sum_type_definitions)
    strings.builder_destroy(&s.other_type_definitions)
    strings.builder_destroy(&s.sum_type_initialisation_funcs)
    strings.builder_destroy(&s.b)

    return transmute([]byte)strings.to_string(out)
}

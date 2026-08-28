package compiler

import "../utils"

// This file may become an implementation of the node simplifier in a sea of nodes style optimizer
// See https://github.com/seaofnodes/simple

// TODO: Improve simplifications, for example:
// (Constant + Runtime) -> (Runtime + Constant)
// (Runtime + Constant) + Constant -> Runtime + (Constant + Constant)

create_not :: proc(value: CheckedValue) -> CheckedValue {
    comptime_value, is_comptime := value.(CompileTimeValue)
    if is_comptime {
        return CompileTimeValue(BoolValue(!comptime_value.(BoolValue)))
    }
    return BooleanNotValue(new_clone(value))
}

create_negation :: proc(value: CheckedValue) -> CheckedValue {
    return create_joined_values(.Subtraction, CompileTimeValue(utils.number_zero), value)
}

create_joined_values :: proc(
    method: UnitJoinMethod,
    val0: CheckedValue,
    val1: CheckedValue,
    loc := #caller_location,
) -> CheckedValue {
    when ODIN_DEBUG {
        utils.call(loc, "create_joined_values", "")
    }
    flip_values := false
    switch method {
    case .Assign, .Tilde, .PipeEquals, .Colon, .Append, .Concat, .Arrow, .Dot:
        panic("Unreachable")
    case .BooleanAnd, .BooleanOr:
        comptime0, val0_is_comptime := val0.(CompileTimeValue)
        comptime1, val1_is_comptime := val1.(CompileTimeValue)
        if val0_is_comptime && val1_is_comptime {
            if method == .BooleanAnd {
                return CompileTimeValue(BoolValue(comptime0.(BoolValue) && comptime1.(BoolValue)))
            }
            return CompileTimeValue(BoolValue(comptime0.(BoolValue) || comptime1.(BoolValue)))
        }
        flip_values = val0_is_comptime
    case .IsEqual,
         .IsNotEqual,
         .IsGreaterThan,
         .IsLessThan,
         .IsGreaterThanOrEqual,
         .IsLessThanOrEqual,
         .Modulo,
         .StringConcat,
         .In: // TODO
    case .Multiplication, .Division, .Addition, .Subtraction:
        comptime0, val0_is_comptime := val0.(CompileTimeValue)
        comptime1, val1_is_comptime := val1.(CompileTimeValue)
        if val0_is_comptime && val1_is_comptime {
            num0 := comptime0.(utils.NumberValue)
            num1 := comptime1.(utils.NumberValue)
            if num0.fraction_part == "" && num1.fraction_part == "" {
                n0 := utils.BigInt{num0.is_negated, num0.whole_part}
                n1 := utils.BigInt{num1.is_negated, num1.whole_part}
                ok :: proc(b: utils.BigInt) -> CheckedValue {
                    return CompileTimeValue(utils.NumberValue{b.is_negated, b.absolute_value, ""})
                }
                #partial switch method {
                case .Multiplication:
                    return ok(utils.mul_int(n0, n1))
                case .Division: // TODO
                case .Addition:
                    return ok(utils.add_int(n0, n1))
                case .Subtraction:
                    return ok(utils.sub_int(n0, n1))
                case:
                    panic("Unreachable")
                }
            } else {
                // TODO
            }
        }
        // TODO: Be able to move the constant right for non-commutative operations
        flip_values = val0_is_comptime && (method == .Multiplication || method == .Addition)
    }
    if flip_values {
        return CheckedJoinedValues{CheckedJoinMethod(method), new_clone(val1), new_clone(val0)}
    }
    return CheckedJoinedValues{CheckedJoinMethod(method), new_clone(val0), new_clone(val1)}
}

create_field_access :: proc(value: CheckedValue, field_index: u32) -> CheckedValue {
    #partial switch v in value {
    case CompileTimeValue:
        return v.(CompileTimeStructInitialisation).fields[field_index]
    case StructInitialisation:
    // Cannot simplify something like `{a: 5, b: do_stuff()}.a` to `5` because the `do_stuff` call may cause side effects
    // TODO: Be able to make simplifications like this and preserve side effects
    }
    return CheckedFieldAccess{new_clone(value), field_index}
}

create_struct :: proc(struct_type: Type, fields: []CheckedValue) -> CheckedValue {
    comptime_args := make([]CompileTimeValue, len(fields))
    for field, i in fields {
        comptime, is_comptime := field.(CompileTimeValue)
        if is_comptime == false {
            return StructInitialisation{struct_type, fields}
        }
        comptime_args[i] = comptime
    }
    return CompileTimeValue(CompileTimeStructInitialisation{struct_type, comptime_args})
}

/*
to_checked_value :: proc(func: union {
        CheckedFunctionCall,
        CompileTimeValue,
    }) -> CheckedValue {
    switch f in func {
    case CheckedFunctionCall:
        return f
    case CompileTimeValue:
        return f
    case nil:
        return nil
    case:
        panic("Unreachable")
    }
}

// OLD(INITIALISING STRUCTS LIKE `StructType(fields...)`)
create_checked_func_call :: proc(func: CheckedValue, args: []CheckedValue) -> union {
        CheckedFunctionCall,
        CompileTimeValue,
    } {
    #partial outer: switch func_value in func {
    case StructTypeInitFunc:
        comptime_args := make([]CompileTimeValue, len(args))
        for arg, i in args {
            comptime, is_comptime := arg.(CompileTimeValue)
            if is_comptime == false {
                break outer
            }
            comptime_args[i] = comptime
        }
        return CompileTimeValue(CompileTimeStructInitialisation{func_value, comptime_args})
    }
    return CheckedFunctionCall{new_clone(func), args}
}
*/

iterate_array :: proc(
    loop_index: uint,
    index_variable: VariableRef,
    value_variable: VariableRef,
    body: ^utils.DoubleDynamic(CheckedStatement),
    body_variables: []Type,
    array_value: CheckedValue,
    array_type: ArrayType,
) -> CheckedLoop {
    loop_enter := make([]CheckedStatement, 1)
    loop_enter[0] = CheckedAssignment {
        index_variable,
        CompileTimeValue(utils.NumberValue{false, utils.uint_zero, ""}),
    }

    if_block := make([]CheckedStatement, 1)
    if_block[0] = CheckedLoopControlFlow{loop_index, .Break}
    utils.dynamic_insert(
        body,
        CheckedIf {
            create_joined_values(
                .IsGreaterThanOrEqual,
                index_variable,
                length_of_array(array_type, array_value),
            ),
            CheckedBlock{nil, if_block},
            CheckedBlock{},
        },
        CheckedAssignment {
            value_variable,
            CheckedIndexedAccess {
                .Array,
                new_clone(array_value),
                CheckedIndex{new_clone(CheckedValue(index_variable)), nil},
            },
        },
    )
    continue_code := make([]CheckedStatement, 1)
    continue_code[0] = CheckedAssignment {
        index_variable,
        create_joined_values(
            .Addition,
            index_variable,
            CompileTimeValue(utils.NumberValue{false, utils.big_uint_from_u64(1), ""}),
        ),
    }
    return CheckedLoop {
        loop_index,
        body_variables,
        loop_enter,
        continue_code,
        utils.to_debug_value(utils.dynamic_to_fixed(body^)),
    }
}

iterate_start_end_step :: proc(
    loop_index: uint,
    index_variable: VariableRef,
    type: NumericIteratorType,
    start: CheckedValue,
    end: CheckedValue,
    step: CheckedValue,
    body: ^utils.DoubleDynamic(CheckedStatement),
    body_variables: []Type,
) -> CheckedLoop {
    // TODO: Handle when `step` is negative
    loop_enter := make([]CheckedStatement, 1)
    loop_enter[0] = CheckedAssignment{index_variable, start}
    if_block := make([]CheckedStatement, 1)
    if_block[0] = CheckedLoopControlFlow{loop_index, .Break}
    utils.dynamic_insert(
        body,
        CheckedIf {
            create_joined_values(
                type == .IncludeEndValue ? .IsGreaterThan : .IsGreaterThanOrEqual,
                index_variable,
                end,
            ),
            CheckedBlock{nil, if_block},
            CheckedBlock{},
        },
    )
    loop_continue := make([]CheckedStatement, 1)
    loop_continue[0] = CheckedAssignment {
        index_variable,
        create_joined_values(.Addition, index_variable, step),
    }
    return CheckedLoop {
        loop_index,
        body_variables,
        loop_enter,
        loop_continue,
        utils.to_debug_value(utils.dynamic_to_fixed(body^)),
    }
}

iterate_ordered_hash_map :: proc(
    loop_index: uint,
    hash_map: CheckedValue,
    index_variable: VariableRef,
    key_variable: VariableRef,
    value_variable: VariableRef,
    body: ^utils.DoubleDynamic(CheckedStatement),
    body_variables: []Type,
    loc := #caller_location,
) -> CheckedLoop {
    when ODIN_DEBUG {
        utils.call(loc, "iterate_ordered_hash_map", "")
    }
    keys := KeysOfOrderedHashMap{new_clone(hash_map)}
    utils.dynamic_insert(
        body,
        CheckedAssignment {
            value_variable,
            CheckedOrderedHashMapAccess {
                new_clone(hash_map),
                new_clone(CheckedValue(key_variable)),
            },
        },
    )
    return iterate_array(
        loop_index,
        index_variable,
        key_variable,
        body,
        body_variables,
        keys,
        ArrayType{nil, .String},
    )
}

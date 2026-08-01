package main

import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"

VariableRef :: struct {
    nesting_level: uint,
    index:         uint,
}

ScopeVariable :: struct {
    type:            Type,
    is_reassignable: bool,
}

Scope :: struct {
    // The length of these arrays should be the same
    variables: #soa[dynamic]ScopeVariable,
}

ArrayType :: struct {
    length:    u32, // 0 means dynamic length
    item_type: Type,
}

OrderedHashMapTypeWithStringKey :: struct {
    value_type: Type,
}

OrderedHashMapTypeWithIntKey :: struct {
    value_type: Type,
}

CheckerGlobalValueWithoutGeneric :: struct {
    ast_node: GlobalValueWithoutGeneric,
    v:        CheckedGlobalValue,
}

CheckerGlobalValue :: struct {
    ast_node: GlobalValueWithoutGeneric,
    value:    CheckerGlobalValueWithoutGeneric,
}

LabelRef :: struct {
    nesting_level: uint,
    loop_index:    uint,
}

GenericInitialisation :: struct {
    global: GlobalValueWithGenericRef,
    args:   []Type,
}

CheckedGlobalValue :: struct {
    type:  Type,
    value: CompileTimeValue,
}

GenericInitialisations :: struct {
    m:      KeyToIndex(GenericInitialisation),
    values: Multi(CheckedGlobalValue),
}

CheckerScopeState :: struct {
    return_types:      []Type,
    loop_index:        uint,
    parent_loop_index: uint, // Set to max(uint) when there is no parent loop

    // The following fields depend on which variables are in scope
    scopes:            [dynamic]Scope,
    variables_map:     map[string]VariableRef,
    labels_map:        map[string]LabelRef,
}

CheckerState :: struct {
    // The following fields do not change while checking
    parsed_files:                  []map[string]ParsedGlobal, // len(parsed_files) == len(r.files)
    global_values_without_generic: #soa[]CheckerGlobalValueWithoutGeneric,
    global_values_with_generics:   []GlobalValueWithGeneric,
    func_defs:                     []FunctionDefinition,

    // The following fields change while checking
    a:                             ^Arena,
    using r:                       DiagnosticReporter,
    generic_initialisations:       GenericInitialisations,
    checked_functions:             [dynamic]CheckedFunction,
    first_unchecked_function:      uint,
    types:                         Types,

    // Depend on which function is being checked
    using scope_state:             CheckerScopeState,
}

InlineFuncFields :: struct {
    variables_from_outer_scope: map[string]VariableRef,
    scope0:                     Scope,
}

CheckedFunction :: struct {
    type:         Type, // Always a function type
    definition:   FuncDefinitionRef,
    generic_args: map[string]Type,
    variables:    []Type,
    body:         []CheckedStatement,
    inline_stuff: InlineFuncFields,
}

StringLiteralValue :: distinct string
CharValue :: distinct u8
IntValue :: distinct i64
BooleanNotValue :: distinct ^CheckedValue
CheckedJoinedValues :: struct {
    join_method: HierarchyUnitJoinMethod,
    val0:        ^CheckedValue,
    val1:        ^CheckedValue,
}
CheckedFunctionCall :: struct {
    function: ^CheckedValue,
    args:     []CheckedValue,
}
StructTypeInitFunc :: struct {
    return_type: Type,
}
SumTypeInitFunc :: struct {
    sum_type:      Type,
    variant_index: u32,
}
LengthOfString :: struct {
    str: ^CheckedValue,
}
LengthOfArray :: struct {
    array: ^CheckedValue,
}
LengthOfOrderedHashMapWithStringKey :: struct {
    hash_map: ^CheckedValue,
}
LengthOfOrderedHashMapWithIntKey :: struct {
    hash_map: ^CheckedValue,
}
KeysOfOrderedHashMapWithStringKey :: struct {
    hash_map: ^CheckedValue,
}
KeysOfOrderedHashMapWithIntKey :: struct {
    hash_map: ^CheckedValue,
}
CheckedOrderedHashMapAccess :: struct {
    hash_map: ^CheckedValue,
    key:      ^CheckedValue,
}
CheckedIndex :: struct {
    // The code emitter might not emit code to sanity check the index
    start_index: ^CheckedValue,
    end_index:   ^CheckedValue, // May be nil
}
CheckedIndexedAccess :: struct {
    base_type: enum {
        String,
        Array,
    },
    base:      ^CheckedValue,
    i:         CheckedIndex,
}
CheckedFieldAccess :: struct {
    value:       ^CheckedValue,
    field_index: u32,
}
BoolValue :: distinct bool
StringsAreEqual :: struct {
    str0: ^CheckedValue,
    str1: ^CheckedValue,
}
NumberValue :: struct {
    is_negated:    bool,
    whole_part:    BigUint,
    fraction_part: string,
}
ImportedFile :: struct {
    file_index: uint,
}
// UninitialisedGlobalWithGenerics :: struct {
// global: GlobalValueWithGenericRef,
// generic_args: []Type,
// }
UninitialisedOrderedHashMapType :: struct {}
CompileTimeStructInitialisation :: struct {
    func: StructTypeInitFunc,
    args: []CompileTimeValue,
}
CastFunction :: struct {
    type: Type,
}
CompileTimeOrderedHashMapInitialisation :: struct {
    type:  Type,
    value: map[string]CompileTimeValue,
    order: []string,
}
OrderedHashMapInitialisation :: struct {
    type:                Type,
    compile_time_values: map[string]CompileTimeValue,
    runtime_values:      map[string]CheckedValue,
    order:               []string,
}
CompileTimeArray :: struct {
    type:     Type,
    elements: []CompileTimeValue,
}
CompileTimeValue :: union {
    CompileTimeArray,
    StringLiteralValue,
    NumberValue,
    BoolValue,
    Type,
    GlobalValueWithGenericRef, // For an uninitialised global value with generics
    UninitialisedOrderedHashMapType,
    Import,
    Func,
    CompileTimeStructInitialisation,
    CompileTimeOrderedHashMapInitialisation,
    BuiltinFunction,
    CastFunction,
}
Func :: struct {
    ref:         CheckedFuncRef,
    // For when variables defined in one function are accessible from an inline
    // function
    lambda_args: Multi(VariableRef),
}
CheckedValue :: union {
    CompileTimeValue,
    ToString,
    VariableRef,
    BooleanNotValue,
    CheckedJoinedValues,
    CheckedFunctionCall,
    StructTypeInitFunc,
    SumTypeInitFunc,
    CheckedIndexedAccess,
    CheckedOrderedHashMapAccess,
    CheckedFieldAccess,
    // CheckedJsFunctionCall,
    LengthOfArray,
    LengthOfString,
    LengthOfOrderedHashMapWithStringKey,
    LengthOfOrderedHashMapWithIntKey,
    KeysOfOrderedHashMapWithStringKey,
    KeysOfOrderedHashMapWithIntKey,
    StringsAreEqual,
    ArrayLiteral,
    CheckedDerivation,
    OrderedHashMapInitialisation,
}


ArrayLiteral :: struct {
    type:     Type,
    segments: []ArraySegment,
}

FuncType :: struct {
    args:         []Type,
    return_types: []Type,
}

TypeAndPos :: struct {
    type: Type,
    pos:  Pos,
}

expect_number :: proc(s: ^CheckerState, t: TypeAndPos) -> bool {
    #partial switch t.type {
    case .int_type, .uint_type, .float_type:
        return true
    case:
        diagnostic(
            s,
            t.pos,
            "Expected a number type, but got the type `%s`",
            type_to_string(s, t.type),
        )
        return false
    }
}

most_general_number_type :: proc(s: ^CheckerState, first_type: Type, types: ..TypeAndPos) -> Type {
    out := TypeAndPos{first_type, unknown_pos}
    for type in types {
        ok := expect_number(s, type)
        if !ok {
            return .invalid_type
        }
        if type.type < out.type {
            out = type
        }
    }
    return out.type
}

CharGroup :: enum {
    Underscore,
    LowerCase,
    UpperCase,
    Digit,
    Unknown,
}

get_character_group :: proc(c: byte) -> CharGroup {
    if 'a' <= c && c <= 'z' {
        return .LowerCase
    } else if c == '_' {
        return .Underscore
    } else if 'A' <= c && c <= 'Z' {
        return .UpperCase
    } else if '0' <= c && c <= '9' {
        return .Digit
    } else {
        return .Unknown
    }
}

expect_snake_case :: proc(
    s: ^CheckerState,
    expected: string,
    ident: TextAndPos,
    can_have_dollar_postfix: bool,
) {
    i: uint = 0
    state: enum {
        InUppercaseBlock,
        InLowercaseBlock,
        NotInBlock,
    } = .NotInBlock
    for i < len(ident.text) {
        switch get_character_group(ident.text[i]) {
        case .LowerCase:
            switch state {
            case .NotInBlock:
                state = .InLowercaseBlock
            case .InLowercaseBlock:
            case .InUppercaseBlock:
                diagnostic(
                    &s.r,
                    Pos{ident.pos.index + i, ident.pos.file},
                    "Expected %s to be `snake_case`, got `%s`\nUnexpected lowercase letter '%c' in an uppercase block of a snake case identifier\nExpected an underscore, a number, or an uppercase letter",
                    expected,
                    ident.text,
                    ident.text[i],
                    type = .Warning,
                )
                return
            }
        case .UpperCase:
            switch state {
            case .NotInBlock:
                state = .InUppercaseBlock
            case .InUppercaseBlock:
            case .InLowercaseBlock:
                diagnostic(
                    s,
                    Pos{ident.pos.index + i, ident.pos.file},
                    "Expected %s to be `snake_case`, got `%s`\nUnexpected uppercase letter '%c' in a lowercase block of a snake case identifier\nExpected an underscore, a number, or a lowercase letter",
                    expected,
                    ident.text,
                    ident.text[i],
                    type = .Warning,
                )
                return
            }
        case .Digit:
        case .Underscore:
            state = .NotInBlock
        case .Unknown:
            assert(i + 1 == len(ident.text))
            assert(ident.text[i] == '$')
            if !can_have_dollar_postfix {
                diagnostic(
                    s,
                    Pos{ident.pos.index + uint(i) + 1, ident.pos.file},
                    "Cannot have '$' post fix in %s",
                    expected,
                    type = .Warning,
                )
            }
            return
        }
        i += 1
    }
    return
}

// The boolean returned is whether the identifier is camel case
expect_camel_case :: proc(s: ^CheckerState, expected: string, ident: TextAndPos) {
    if get_character_group(ident.text[0]) != .UpperCase {
        diagnostic(
            s,
            ident.pos,
            "Expected %s to be `CamelCase`, got `%s`\nFirst character in a camel case identifier must be an uppercase letter\nGot '%c'",
            expected,
            ident.text,
            ident.text[0],
            type = .Warning,
        )
        return
    }
    for i: uint = 1; i < len(ident.text); i += 1 {
        switch get_character_group(ident.text[i]) {
        case .Underscore:
            diagnostic(
                s,
                Pos{ident.pos.index + i, ident.pos.file},
                "Expected %s to be `CamelCase`, got `%s`\nCannot have `_` in a camel case identifier",
                expected,
                ident.text,
                type = .Warning,
            )
            return
        case .LowerCase, .UpperCase, .Digit:
        case .Unknown:
            assert(i + 1 == len(ident.text))
            assert(ident.text[i] == '$')
            diagnostic(
                s,
                Pos{ident.pos.index + i, ident.pos.file},
                "Cannot have '$' post fix in `CamalCase` identifier `%s`",
                ident.text,
                type = .Warning,
            )
            return
        }
    }
    return
}

no_generic_args :: map[string]Type{}

check_struct_type :: proc(
    s: ^CheckerState,
    type: StructUnit,
    generic_args: map[string]Type,
) -> Type {
    field_types := arena_make_multi(s.a, Multi(Type), len(type.m.keys))
    ok := true
    for field, i in type.m.keys {
        expect_snake_case(
            s,
            "the name of a struct field",
            TextAndPos{field.key, type.positions.d[i]},
            can_have_dollar_postfix = false,
        )
        field_types.d[i] = check_type(s, type.types.d[i], generic_args)
        if field_types.d[i] == .invalid_type {
            ok = false
        }
    }
    if !ok {
        return .invalid_type
    }

    created := create_type(&s.types, StructType{type.m, type.positions, field_types})
    if created.type_value.type == .unknown_type {
        init_struct_type(&s.types, created.type, field_types.d[:len(type.m.keys)])
    }
    assert(get_type(s.types, created.type).value.type != .unknown_type)
    return created.type
}

// Returns `FuncType{}, false` on failure
check_function_type :: proc(
    s: ^CheckerState,
    inputs: []Unit,
    output: ^Unit, // if the function has no output, then `output` is `nil`
    generic_args: map[string]Type,
) -> (
    FuncType,
    bool,
) {
    ok := true

    args := make([]Type, len(inputs))
    for input, i in inputs {
        args[i] = check_type(s, input, generic_args)
        if args[i] == .invalid_type {
            ok = false
        }
    }

    outputs: []Unit = ---
    if output == nil {
        outputs = nil
    } else if tuple, is_tuple := output.first_unit.(Tuple); is_tuple {
        outputs = tuple.elements
    } else {
        outputs = make([]Unit, 1)
        outputs[0] = output^
    }
    return_types := make([]Type, len(outputs))
    for output, i in outputs {
        return_types[i] = check_type(s, output, generic_args)
        if return_types[i] == .invalid_type {
            ok = false
        }
    }

    if !ok {
        return FuncType{}, false
    }

    return FuncType{args, return_types}, true
}

// Returns nil if there are errors in the type
check_array_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    type: CallWithFrontedSquareBrackets,
    generic_args: map[string]Type,
) -> (
    ArrayType,
    bool,
) {
    length: u32 = 0
    if len(type.args) == 0 {
        length = 0
    } else if len(type.args) == 1 {
        body := make([dynamic]CheckedStatement)
        value := expect_runtime_value(
            s,
            type.args[0].pos,
            check_value(s, type.args[0], CheckValueArgs{&body, .uint_type, generic_args, nil}),
        )
        if value == nil {
            return ArrayType{}, false
        }
        compile_time_value, ok := value.(CompileTimeValue)
        if !ok {
            diagnostic(s, type.args[0].pos, "Expected a compile time value got a runtime value")
            return ArrayType{}, false
        }
        number := compile_time_value.(NumberValue)
        assert(len(body) == 0)
        assert(number.fraction_part == "")
        length, ok = big_uint_to_u32(number.whole_part)
        if number.is_negated || !ok || length == 0 {
            diagnostic(s, type.args[0].pos, "Expected an integer, n, where 0 < n <= max(u32)")
            return ArrayType{}, false
        }
    } else {
        diagnostic(s, pos, "Expected either 0 or 1 unit inside `[]`, got %d units", len(type.args))
        return ArrayType{}, false
    }
    item_type := check_initial_type(s, type.unit_being_called^, generic_args)
    if item_type == .invalid_type {
        return ArrayType{}, false
    }
    return ArrayType{length, item_type}, true
}

// Returns `invalid_type` if there are errors in the type
check_type :: proc(
    s: ^CheckerState,
    type: Unit,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> Type {
    when debug_checker {
        print_call(loc, "check_type")
    }
    body := make([dynamic]CheckedStatement)
    value := check_value(s, type, CheckValueArgs{&body, .type_type, generic_args, nil})
    if value == nil {
        return .invalid_type
    }
    assert(len(body) == 0)
    return value.(CompileTimeValue).(Type)
}

check_initial_type :: proc(
    s: ^CheckerState,
    type: UnitWithPos,
    generic_args: map[string]Type,
) -> Type {
    body := make([dynamic]CheckedStatement)
    value := check_initial_value(
        s,
        type.pos,
        type.unit,
        CheckValueArgs{&body, .type_type, generic_args, nil},
    )
    if value == nil {
        return .invalid_type
    }
    assert(len(body) == 0)
    return value.(CompileTimeValue).(Type)

}

// A "runtime value" is any value which can be used at runtime
expect_runtime_value :: proc(
    s: ^CheckerState,
    pos: Pos,
    v: CheckedValue,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "expect_runtime_value")
    }
    if comptime_value, is_comptime_value := v.(CompileTimeValue); is_comptime_value {
        #partial switch _ in comptime_value {
        case Type, GlobalValueWithGenericRef, UninitialisedOrderedHashMapType, Import:
            diagnostic(s, pos, "This value can only be used at run time")
            return nil
        }
    }
    return v
}

CheckedReturn :: struct {
    value: CheckedValue,
}

TwoValueOperation :: enum {
    IsEqual,
    LessThan,
    LessThanOrEqual,
}

CheckedIf :: struct {
    condition:  CheckedValue,
    if_block:   CheckedBlock,
    else_block: CheckedBlock,
}

// JsValue :: struct {
//     value: ^CheckedValue, // can be nil
//     str:   string,
// }

// CheckedJsFunctionCall :: struct {
//     function:  JsValue,
//     arguments: []CheckedValue,
// }
//
// CheckedJsAssignment :: struct {
//     destination: JsValue,
//     value:       CheckedValue,
// }

CheckedLoop :: struct {
    loop_index:    uint,
    variables:     []Type,
    enter:         []CheckedStatement,
    continue_code: []CheckedStatement,
    body:          []CheckedStatement,
}

ContinueLoop :: struct {
    loop_index: uint,
}
BreakLoop :: struct {
    loop_index: uint,
}

CheckedBlock :: struct {
    variables: []Type,
    body:      []CheckedStatement,
}

ArrayElementAccess :: struct {
    index: CheckedValue,
}

StringOrderedHashMapAccess :: struct {
    key: CheckedValue,
}

FieldAccess :: struct {
    field_index: u32,
}

DerivationSubsetElement :: union #no_nil {
    StringOrderedHashMapAccess,
    ArrayElementAccess,
    FieldAccess,
}

DerivationSubset :: struct {
    elements: []DerivationSubsetElement,
}

DerivationAlteration :: struct {
    kind: enum {
        Replace,
        PipeThroughFunction,
    },
    arg:  ^CheckedValue,
}

CheckedDerivation :: struct {
    base:       ^CheckedValue,
    subset:     DerivationSubset,
    alteration: DerivationAlteration,
}

InlineArraySegment :: struct {
    array: CheckedValue, // an array that should be copied into the `ArrayValue`
}

SingleElemSegment :: struct {
    elem: CheckedValue, // a scalar value for an element in the `ArrayValue`
}

ArraySegment :: union {
    InlineArraySegment,
    SingleElemSegment,
}

ToStringFromType :: enum {
    BoolType,
    IntType,
    UIntType,
    FloatType,
    CharType,
}

ToString :: struct {
    from_type: ToStringFromType,
    value:     ^CheckedValue,
}

CheckedMatchBranch :: struct {
    block:     CheckedBlock,
    value_var: union {
        VariableRef,
    }, // May be nil
}

CheckedMatch :: struct {
    value:    VariableRef,
    branches: []CheckedMatchBranch, // The branch index is the variant index
}

CheckedAssignment :: struct {
    dest:  VariableRef,
    value: CheckedValue,
}

CheckedStatement :: union {
    CheckedReturn,
    CheckedIf,
    CheckedLoop,
    ContinueLoop,
    BreakLoop,
    CheckedAssignment,
    CheckedFunctionCall,
    CheckedMatch,

    // TODO: Store where the statement is and tell the user where the statement is when it is reached
    UnreachableStatement,
}

non_compiletime_global_err :: "This value is not a compile time known constant\nAll global values must be compile time known constants"

generic_initialisation_to_index_procs :: KeyToIndexProcs(GenericInitialisation) {
    proc(g: GenericInitialisation) -> u32 {
        return g.global.index ~ get_hash_of_array_of_types(g.args)
    },
    proc(v0: GenericInitialisation, v1: GenericInitialisation) -> bool {
        if v0.global != v1.global {
            return false
        }
        if len(v0.args) != len(v1.args) {
            return false
        }
        for arg, i in v0.args {
            if arg != v1.args[i] {
                return false
            }
        }
        return true
    },
}

check_comptime_func_call :: proc(
    s: ^CheckerState,
    pos: Pos,
    global: GlobalValueWithGenericRef,
    generic_args: []Type,
    type: ExpectedType,
    loc := #caller_location,
) -> CheckedValue {
    // return CompileTimeValue(UninitialisedGlobalWithGenerics{global,generic_args})
    generic := &s.global_values_with_generics[global.index]
    if len(generic_args) != len(generic.generics) {
        argument_count_mismatch(s, pos, len(generic_args), len(generic.generics), generic.name)
        return nil
    }

    ref, res := lookup_or_insert(
        &s.generic_initialisations.m,
        GenericInitialisation{global, generic_args},
        generic_initialisation_to_index_procs,
    )
    if res == .LookedUp {
        value := s.generic_initialisations.values.d[ref.index]
        if value.type == .unknown_type {
            panic("TODO: Handle cycles")
        }
        return finish_checking_value(s, pos, type, value.value, value.type, "")
    } else {
        resize_multi(&s.generic_initialisations.values, len(s.generic_initialisations.m.keys))
        s.generic_initialisations.values.d[ref.index] = CheckedGlobalValue{.unknown_type, nil}
    }

    generic_args_map := make(map[string]Type)
    for arg, i in generic.generics {
        assert(!(arg.text in generic_args_map))
        generic_args_map[arg.text] = generic_args[i]
    }

    body: [dynamic]CheckedStatement
    value_type := Type.invalid_type
    old_scope_state := s.scope_state
    s.scope_state = CheckerScopeState{}
    checked_value := check_value(
        s,
        generic.value,
        CheckValueArgs {
            &body,
            AnyType{&value_type},
            generic_args_map,
            GenericTypeValue{global, generic_args},
        },
    )
    s.scope_state = old_scope_state
    if checked_value == nil {
        s.generic_initialisations.values.d[ref.index] = CheckedGlobalValue{.invalid_type, nil}
        return nil
    }
    comptime_value, ok := checked_value.(CompileTimeValue)
    s.generic_initialisations.values.d[ref.index] = CheckedGlobalValue{value_type, comptime_value}
    if !ok {
        diagnostic(s, generic.value.pos, non_compiletime_global_err)
        return nil
    }
    assert(len(body) == 0)

    out := finish_checking_value(s, pos, type, checked_value, value_type, "")

    if value_type == .type_type {
        type_value := comptime_value.(Type)
        initialised_type := check_value(
            s,
            generic.value,
            CheckValueArgs{nil, AnyType{&value_type}, generic_args_map, nil},
        )
        assert(value_type == .type_type)
        assert(
            type_key_is_equal(
                s.types.m.keys[type_value].key,
                GenericTypeValue{global, generic_args},
            ),
        )
        s.types.values.d[type_value].type =
            initialised_type == nil ? .invalid_type : initialised_type.(CompileTimeValue).(Type)
    }

    return out
    /*

    s.generic_initialisations.values[ref.index].value.v = CheckedGlobalValue {
        checked_value_type,
        comptime_value,
    }

    if expect_value_of_type(s, pos, type, &checked_value, checked_value_type, "") {
        return checked_value
    }
    return nil
    */
    /*

    generic_args_map := make(map[string]Type)
    for arg, i in generic.generics {
        assert(!(arg.ident in generic_args_map))
        generic_args_map[arg.ident] = generic_args[i]
    }
    */
}

/*
check_generic_type :: proc(
    s: ^CheckerState,
    pos: uint,
    generic_type_index: u32,
    generic_args: []Type,
    loc := #caller_location,
) -> Type {
    generic := s.global_types_with_generics[generic_type_index]
    if len(generic_args) != len(generic.generics) {
        argument_count_mismatch(s, pos, len(generic_args), len(generic.generics), generic.name)
        return invalid_type
    }

    created := create_type(
        &s.types,
        GenericTypeValue{generic_type_index, generic_args, unknown_type},
    )
    if created.result == .Merged {
        if created.type_value.(GenericTypeValue).initialised_type == invalid_type {
            return invalid_type
        }
        return created.type
    }

    old_file := s.file
    defer s.file = old_file
    s.file = generic.file
    generic_args_map := make(map[string]Type)
    for arg, i in generic.generics {
        assert(!(arg.ident in generic_args_map))
        generic_args_map[arg.ident] = generic_args[i]
    }
    initialised_type := check_type(s, generic.value, generic_args_map)
    created2 := create_type(
        &s.types,
        GenericTypeValue{generic_type_index, generic_args, initialised_type},
    )
    assert(created.type == created2.type)
    if initialised_type == invalid_type {
        return invalid_type
    }
    return created.type
}

initialise_global_type_without_generic :: proc(
    s: ^CheckerState,
    i: uint,
    loc := #caller_location,
) -> Type {
    when true {
        print_call(loc, "initialise_global_type_without_generic")
    }
    // TODO: Check for cycles
    type := s.global_values_without_generic[i]
    if type.v.type == type_type {
        return type.v.value.(Type)
    }
    if type.v.type != unknown_type {
        diagnostic(s, type.ast_node.unit.pos, "TODO: FIX") // TODO FIX
    }
    checked_type := check_type(s, type.ast_node.unit, no_generic_args)
    s.global_values_without_generic[i].v.value = CompileTimeValue(checked_type)
    return checked_type
}
*/

simplify_type :: proc(s: ^CheckerState, type: Type, loc := #caller_location) -> Type {
    when debug_checker {
        print_call(loc, "simplify_type")
        print_arg("type", type)
    }
    cur_type := type
    for {
        got := get_type(s.types, cur_type)
        #partial switch key in got.key {
        case GenericTypeValue, GlobalType:
            cur_type = got.value.type
            assert(cur_type != .unknown_type)
        case:
            return cur_type
        }
    }
}

// For `get_sum_type`, `get_struct_type`, and `get_func_type`, set pos to
// `max(uint)` to not report an error if it is not a sum/struct type

get_sum_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    type: Type,
    loc := #caller_location,
) -> (
    SumType,
    Type,
    bool,
) {
    when debug_checker {
        print_call(loc, "get_sum_type")
        print_arg("pos", pos)
        print_arg("type", type)
    }
    simplified := simplify_type(s, type)
    sum_type, is_sum_type := get_type(s.types, simplified).key.(SumType)
    if is_sum_type {
        when debug_checker {
            debug("returned SumType(StructType) is %#v", sum_type)
        }
        return sum_type, simplified, true
    }
    if pos != unknown_pos {
        diagnostic(s, pos, "Expected a sum type, but got the type `%s`", type_to_string(s, type))
    }
    return SumType{}, .unknown_type, false
}

get_struct_type :: proc(s: ^CheckerState, pos: Pos, type: Type) -> (StructType, bool) {
    simplified := simplify_type(s, type)
    struct_type, is_struct_type := get_type(s.types, simplified).key.(StructType)
    if is_struct_type {
        return struct_type, true
    }
    if pos != unknown_pos {
        got := type_to_string(s, type)
        diagnostic(s, pos, "Expected a struct type, but got the type `%s`", got)
    }
    return StructType{}, false
}

// Always returns a function type
// Returns `invalid_type` on failure
get_func_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    value: ^CheckedValue,
    type: Type,
    loc := #caller_location,
) -> Type {
    when debug_checker {
        print_call(loc, "get_func_type")
        print_arg("type", type_to_string(s, type))
    }
    simplified := simplify_type(s, type)
    if simplified == .type_type && value != nil {
        value_type_unsimplified := value.(CompileTimeValue).(Type)
        value_type := simplify_type(s, value_type_unsimplified)
        got := get_type(s.types, value_type)
        #partial switch type in got.key {
        case StructType:
            value^ = StructTypeInitFunc{value_type}
            return got.value.type
        }
        diagnostic(
            s,
            pos,
            "The type `%s` cannot be converted to a function type",
            type_to_string(s, value_type_unsimplified),
        )
    } else if _, is_func := get_type(s.types, simplified).key.(FuncType); is_func {
        return simplified
    }
    if pos != unknown_pos {
        if simplified == .unknown_type && value != nil {
            // TODO: Also have this better error message for other functions:
            // - `get_struct_type`
            // - `get_sum_type`
            // - `expect_value_of_type`
            // - `expect_exact_type`
            global_value_with_generic_ref, ok := value.(CompileTimeValue).(GlobalValueWithGenericRef)
            if ok {
                global_value_with_generic :=
                    s.global_values_with_generics[global_value_with_generic_ref.index]
                initialisation := strings.builder_make()
                defer strings.builder_destroy(&initialisation)
                strings.write_string(&initialisation, global_value_with_generic.name)
                strings.write_byte(&initialisation, '[')
                first_arg := true
                for generic in global_value_with_generic.generics {
                    if first_arg == false {
                        strings.write_byte(&initialisation, ',')
                    }
                    strings.write_string(&initialisation, generic.text)
                    first_arg = false
                }
                strings.write_byte(&initialisation, ']')
                diagnostic(
                    s,
                    pos,
                    "Expected a func type, but got an uninitialised global value with generics\nHint: Try initialising the global value with something like `%s`",
                    strings.to_string(initialisation),
                )
                return .invalid_type
            }
        }
        diagnostic(s, pos, "Expected a func type, but got the type `%s`", type_to_string(s, type))
    }
    return .invalid_type
}

type_is_subset :: proc(
    s: ^CheckerState,
    type: Type,
    superset: Type,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "type_is_subset")
        debug("type: %v", get_type(s.types, type))
        debug("superset: %v", get_type(s.types, superset))
    }
    if type == superset {
        return true
    }
    if superset == .any_type {
        return true
    }
    if superset == .float_type {
        return type == .int_type || type == .uint_type
    }
    if superset == .int_type {
        return type == .uint_type
    }
    if superset > .max_index {
        return false
    }
    superset_type := get_type(s.types, superset)
    #partial switch superset_value in superset_type.key {
    case nil:
        panic("Unreachable")
    case:
        return false
    case SumType:
        for _, i in superset_value.m.keys {
            if superset_value.payloads.d[i] == type {
                return true
            }
        }
        return false
    case GenericTypeValue, GlobalType:
        assert(superset_type.value.type != .unknown_type)
        return type_is_subset(s, type, superset_type.value.type)
    }
}

guess_number_type :: proc(n: NumberValue) -> Type {
    // TODO: Check that `n` is in range
    if n.fraction_part != "" {
        return .float_type
    }
    if n.is_negated {
        return .int_type
    }
    return .uint_type
}

finish_checking_value :: proc(
    s: ^CheckerState,
    pos: Pos,
    type: ExpectedType,
    got_value: CheckedValue,
    got_type: Type,
    extra_text: string,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "finish_checking_value")
    }
    got_value_mut := got_value
    if expect_value_of_type(s, pos, type, &got_value_mut, got_type, extra_text) {
        return got_value_mut
    }
    return nil
    /*
    switch value in hint {
    case ExpectedType:
    case ValueWithGenericHint:
        global_value := &s.generic_initialisations.values[value.initialisations_ref.index].value.v
        assert(global_value.type == unknown_type)
        assert(global_value.value == nil)
        global_value^ = CheckedGlobalValue{got_type, nil}
        comptime_value, ok := got_value.(CompileTimeValue)
        if !ok {
            diagnostic(s, pos, non_compiletime_global_err)
            return nil
        }
        global_value^ = CheckedGlobalValue{got_type, comptime_value}
        return nil
    case GlobalValueWithoutGenericRef:
        panic("TODO")
    case:
        panic("Unreachable")
    case nil:
        panic("Unreachable")
    }
    */
}

// For both `expect_value_of_type` and `expect_exact_type`
// - The boolean returned is whether the `got` type matches the `expected` type
// - TODO: Specify `extra_text` in all cases

expect_value_of_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    expected: ExpectedType,
    got_value: ^CheckedValue,
    got_type: Type,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "expect_value_of_type")
        print_arg("expected", expected)
        print_arg("got_type", type_to_string(s, got_type))
    }
    switch e in expected {
    case AnyType:
        e.store^ = got_type
        return true
    case Type:
        return expect_exact_type(s, pos, e, got_type, extra_text)
    case FunctionWithExpectedReturnTypes:
        func_type := get_func_type(s, pos, got_value, got_type)
        if func_type == .invalid_type {
            return false
        }
        func_info := get_type(s.types, func_type).key.(FuncType)
        if len(func_info.return_types) != len(e.expected_return_types) {
            diagnostic(
                s,
                pos,
                "Expected a function with %d return types but got one with %d return types",
                len(e.expected_return_types),
                len(func_info.return_types),
            )
            return false
        }
        for return_type, i in func_info.return_types {
            if !expect_value_of_type(
                s,
                pos,
                e.expected_return_types[i],
                nil,
                return_type,
                extra_text,
            ) {
                return false
            }
        }
        e.args_store^ = func_info.args
        return true
    }
    panic("unreachable")
}

expect_exact_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    expected: Type,
    got: Type,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "expect_exact_type")
    }
    if !type_is_subset(s, got, expected) {
        diagnostic(
            s,
            pos,
            "Expected the type `%s` but got the type `%s`%s",
            type_to_string(s, expected),
            type_to_string(s, got),
            extra_text,
        )
        return false
    }
    return true
}

get_variable_type :: proc(
    s: ^CheckerState,
    variable: VariableRef,
    loc := #caller_location,
) -> Type {
    when debug_checker {
        print_call(loc, "get variable type")
    }
    return s.scopes[variable.nesting_level].variables[variable.index].type
}

type_to_string :: proc(s: ^CheckerState, t: Type, loc := #caller_location) -> string {
    return type_to_string2(
        s.types,
        s.global_values_without_generic.ast_node[:len(s.global_values_without_generic)],
        s.global_values_with_generics,
        t,
        loc,
    )
}

type_to_string2 :: proc(
    types: Types,
    globals_without_generic: []GlobalValueWithoutGeneric,
    globals_with_generic: []GlobalValueWithGeneric,
    t: Type,
    loc := #caller_location,
) -> string {
    when debug_checker {
        print_call(loc, "type_to_string2")
    }
    builder := strings.builder_make()
    build_type_string(types, globals_without_generic, globals_with_generic, &builder, t)
    return strings.to_string(builder)
}

build_struct_string :: proc(
    types: Types,
    globals_without_generic: []GlobalValueWithoutGeneric,
    globals_with_generic: []GlobalValueWithGeneric,
    b: ^strings.Builder,
    type: StructType,
) {
    strings.write_byte(b, '{')
    first_field := true
    for field, i in type.m.keys {
        if !first_field {
            strings.write_string(b, ", ")
        }
        first_field = false
        strings.write_string(b, field.key)
        strings.write_string(b, ": ")
        build_type_string(types, globals_without_generic, globals_with_generic, b, type.types.d[i])
    }
    strings.write_byte(b, '}')
}

build_type_string :: proc(
    types: Types,
    globals_without_generic: []GlobalValueWithoutGeneric,
    globals_with_generic: []GlobalValueWithGeneric,
    b: ^strings.Builder,
    t: Type,
    loc := #caller_location,
) {
    when debug_checker {
        print_call(loc, "build type string")
    }
    // TODO: Format the string better
    #partial switch t {
    case .string_type:
        strings.write_string(b, "String")
    case .int_type:
        strings.write_string(b, "Int")
    case .uint_type:
        strings.write_string(b, "UInt")
    case .float_type:
        strings.write_string(b, "Float")
    case .char_type:
        strings.write_string(b, "Char")
    case .bool_type:
        strings.write_string(b, "Bool")
    case .invalid_type:
        strings.write_string(b, "invalid_type")
    case .unknown_type:
        strings.write_string(b, "unknown_type")
    case .imported_file_type:
        strings.write_string(b, "ImportedFile")
    case .type_type:
        strings.write_string(b, "Type")
    case .any_type:
        strings.write_string(b, "Any")
    case:
        // TODO: For `GlobalType` and `StructType`, put the right namespace before the type
        switch tv in get_type(types, t).key {
        case GlobalType:
            strings.write_string(b, globals_without_generic[tv.global.index].name)
        case StructType:
            build_struct_string(types, globals_without_generic, globals_with_generic, b, tv)
        case SumType:
            strings.write_byte(b, '<')
            first_variant := true
            for variant, i in tv.m.keys {
                if !first_variant {
                    strings.write_string(b, ", ")
                }
                variant_type := get_type(types, tv.payloads.d[i]).key.(StructType)
                strings.write_string(b, variant.key)
                build_struct_string(
                    types,
                    globals_without_generic,
                    globals_with_generic,
                    b,
                    variant_type,
                )
                first_variant = false
            }
            strings.write_byte(b, '>')
        case GenericTypeValue:
            strings.write_string(b, globals_with_generic[tv.global.index].name)
            strings.write_byte(b, '[')
            first_arg := true
            for arg in tv.generic_args {
                if !first_arg {
                    strings.write_string(b, ", ")
                }
                build_type_string(types, globals_without_generic, globals_with_generic, b, arg)
                first_arg = false
            }
            strings.write_byte(b, ']')
        case FuncType:
            strings.write_byte(b, '(')
            for arg, index in tv.args {
                // TODO: Print the name and whether the arg is mutable
                build_type_string(types, globals_without_generic, globals_with_generic, b, arg)
                if index + 1 != len(tv.args) {
                    strings.write_string(b, ", ")
                }
            }
            strings.write_string(b, ") -> ")
            if len(tv.return_types) == 1 {
                build_type_string(
                    types,
                    globals_without_generic,
                    globals_with_generic,
                    b,
                    tv.return_types[0],
                )
            } else {
                strings.write_byte(b, '(')
                first_return_type := true
                for return_type in tv.return_types {
                    if first_return_type == false {
                        strings.write_string(b, ", ")
                    }
                    build_type_string(
                        types,
                        globals_without_generic,
                        globals_with_generic,
                        b,
                        return_type,
                    )
                    first_return_type = false
                }
                strings.write_byte(b, ')')
            }
        case OrderedHashMapTypeWithIntKey:
            strings.write_string(b, "OrderedHashMap[Int, ")
            build_type_string(
                types,
                globals_without_generic,
                globals_with_generic,
                b,
                tv.value_type,
            )
            strings.write_string(b, "]")
        case OrderedHashMapTypeWithStringKey:
            strings.write_string(b, "OrderedHashMap[String, ")
            build_type_string(
                types,
                globals_without_generic,
                globals_with_generic,
                b,
                tv.value_type,
            )
            strings.write_string(b, "]")
        case ArrayType:
            strings.write_byte(b, '[')
            if tv.length != 0 {
                strings.write_uint(b, uint(tv.length))
            }
            strings.write_byte(b, ']')
            build_type_string(
                types,
                globals_without_generic,
                globals_with_generic,
                b,
                tv.item_type,
            )
        case nil:
            panic("Unreachable")
        }
    }
}

pop_scope :: proc(s: ^CheckerState, loc := #caller_location) {
    when debug_checker {
        print_call(loc, "pop_scope")
    }
    pop(&s.scopes)
    for var_name, var_ref in s.variables_map {
        if var_ref.nesting_level == len(s.scopes) {
            delete_key(&s.variables_map, var_name)
        } else {
            assert(var_ref.nesting_level < len(s.scopes))
        }
    }
    for label_name, label_ref in s.labels_map {
        if label_ref.nesting_level == len(s.scopes) {
            delete_key(&s.labels_map, label_name)
        } else {
            assert(label_ref.nesting_level < len(s.scopes))
        }
    }
}

get_array_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    description: string,
    type_unsimplified: Type,
) -> (
    ArrayType,
    bool,
) {
    type := simplify_type(s, type_unsimplified)
    if out, is_array := get_type(s.types, type).key.(ArrayType); is_array {
        return out, true
    }
    diagnostic(
        s,
        pos,
        "%s is of type `%s`\nExpected an array type",
        description,
        type_to_string(s, type_unsimplified),
    )
    return ArrayType{}, false
}

bounds_checks_warning :: "This array access is not bounds checked\nTODO: Bounds checks"

/*
// The `Type` returned is the expected type of the source value
// The `CheckedValue` returned is the value of the destination
check_mutation_destination :: proc(
    s: ^CheckerState,
    var_name: Ident,
    var_ref: VariableRef,
    key: ^Unit,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
) -> (
    Type,
    CheckedValue,
) {
    var_type := get_variable_type(s, var_ref)
    if key == nil {
        return var_type, var_ref
    }
    #partial switch var_type_value in get_type(s.types, simplify_type(s, var_type)).key {
    case ArrayType:
        diagnostic(
            s,
            key.pos,
            bounds_checks_warning,
            type = .Warning,
        )
        index_value := check_runtime_value(s, key^, body, i64_type, generic_args)
        if index_value == nil {
            return var_type_value.item_type, nil
        }
        index_variable: CheckedValue = add_unnamed_variable(s, i64_type, false)
        append_elem(body, CheckedMutation{index_variable, index_value})
        return var_type_value.item_type, CheckedArrayAccess{new_clone(CheckedValue(var_ref)), new_clone(index_variable)}

    case OrderedHashMapTypeWithIntKey:
        panic("TODO")

    case OrderedHashMapTypeWithStringKey:
        key_value := check_runtime_value(s, key^, body, string_type, generic_args)
        if key_value == nil {
            return var_type_value.value_type, nil
        }
        key_variable: CheckedValue = add_unnamed_variable(s, string_type, false)
        append_elem(body, CheckedMutation{key_variable, key_value})
        return var_type_value.value_type, CheckedOrderedHashMapAccess{new_clone(CheckedValue(var_ref)), new_clone(key_variable)}

    }
    diagnostic(s, key.pos, "Cannot use a key with the type `%s`", type_to_string(s, var_type))
    return invalid_type, nil
}
*/

check_mutation :: proc(
    s: ^CheckerState,
    unit_being_mutated: UnitWithPos,
    new_value_unit: Unit,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> bool {
    when debug_checker {
        print_call(loc, "check_mutation")
    }
    ident, is_ident := unit_being_mutated.unit.(IdentNode)
    if !is_ident || len(ident.segments) != 1 {
        diagnostic(
            &s.r,
            unit_being_mutated.pos,
            "Expected an identifier with one segment for the unit being mutated",
        )
        return false
    }
    if ident.has_re_before && !ident.segments[0].has_dollar_at_end {
        diagnostic(
            &s.r,
            ident.segments[0].pos,
            "The name of a reassignable variable must have a `$` postfix",
        )
        return false
    }
    if !ident.has_re_before && ident.segments[0].has_dollar_at_end {
        var_ref, ok := s.variables_map[ident.segments[0].ident]
        if !ok {
            diagnostic(
                s,
                unit_being_mutated.pos,
                "The variable `%s` is not defined",
                ident.segments[0].ident,
            )
            return false
        }
        var := s.scopes[var_ref.nesting_level].variables[var_ref.index]
        if !var.is_reassignable {
            diagnostic(
                s,
                unit_being_mutated.pos,
                "The variable `%s` is not reassignable",
                ident.segments[0].ident,
            )
            return false
        }

        new_value := check_value(
            s,
            new_value_unit,
            CheckValueArgs{body, var.type, generic_args, nil},
        )
        if new_value == nil {
            return false
        }

        append_elem(body, CheckedAssignment{var_ref, new_value})
        return true
    }

    value_type := Type.any_type
    new_value := check_value(
        s,
        new_value_unit,
        CheckValueArgs{body, AnyType{&value_type}, generic_args, nil},
    )
    if new_value == nil {
        return false
    }

    variable, variable_ok := add_variable(s, value_type, ident.segments[0])
    if !variable_ok {
        return false
    }

    append_elem(body, CheckedAssignment{variable, new_value})
    return true
}

// The boolean returned is whether the block checked successfully
check_block :: proc(
    s: ^CheckerState,
    block: []Statement,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> (
    []Type,
    bool,
) {
    when debug_checker {
        print_call(loc, "check_block")
    }
    for stmt, stmt_index in block {
        switch value in stmt.value {

        /*
        case VariableManagement:
            value_type := unknown_type
            checked_value := check_runtime_value(
                s,
                value.value,
                body,
                AnyType{&value_type},
                generic_args,
            )
            if len(value.destination) != 1 {
                diagnostic(
                    s,
                    stmt.position,
                    "TODO: Handle variable management where len(value.destination) != 1",
                )
                return nil, false
            }
            if checked_value == nil {
                return nil, false
            }
            mutation, mutation_ok := check_mutation(
                s,
                value.destination[0],
                value.mutation_type,
                checked_value,
                value_type,
                value.value.pos,
                body,
                generic_args,
            )
            if !mutation_ok {
                return nil, false
            }
            append_elem(body, mutation)
        */

        case Unit:
            if len(value.extra_units) != 0 {
                if value.extra_units[0].join_method != .Assign {
                    diagnostic(
                        s,
                        value.extra_units[0].join_method_pos,
                        "First join method must be `=`",
                    )
                    return nil, false
                }
                ok := check_mutation(
                    s,
                    UnitWithPos{value.first_unit, value.pos},
                    Unit {
                        value.extra_units[0].unit.pos,
                        value.extra_units[0].unit.unit,
                        value.extra_units[1:],
                    },
                    body,
                    generic_args,
                )
                if !ok {
                    return nil, false
                }
            } else {
                #partial switch unit in value.first_unit {
                case CallWithBrackets:
                    call := check_function_call(s, value.pos, unit, body, nil, generic_args)
                    if call == nil {
                        return nil, false
                    }
                    // Call cannot be a `CompileTimeValue` because `expected_return_types` is set to `nil`
                    append_elem(body, call.(CheckedFunctionCall))
                case:
                    diagnostic(s, value.pos, "Cannot use this kind of unit as a statement")
                    return nil, false
                }
            }

        case ConditionControlledLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            s.parent_loop_index = loop_index
            s.loop_index += 1
            condition := expect_runtime_value(
                s,
                value.condition.pos,
                check_value(
                    s,
                    value.condition,
                    CheckValueArgs{body, Type.bool_type, generic_args, nil},
                ),
            )

            loop_body_array := make([dynamic]CheckedStatement)
            exit_loop := make([]CheckedStatement, 1)
            exit_loop[0] = BreakLoop{loop_index}
            condition_check := CheckedIf{condition, CheckedBlock{}, CheckedBlock{nil, exit_loop}}
            if value.type == .WhileLoop {
                append_elem(&loop_body_array, condition_check)
            }

            loop_variables, loop_body_ok := check_block(
                s,
                value.body,
                &loop_body_array,
                generic_args,
            )
            if condition == nil || !loop_body_ok {
                return nil, false
            }

            if value.type == .DoWhileLoop {
                append_elem(&loop_body_array, condition_check)
            }

            append_elem(
                body,
                CheckedLoop{loop_index, loop_variables, nil, nil, loop_body_array[:]},
            )

        case ForInLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            if value.label.text != "" {
                if value.label.text in s.labels_map {
                    diagnostic(
                        s,
                        value.label.pos,
                        "The label `%s` is already defined",
                        value.label.text,
                    )
                    return nil, false
                }
                s.labels_map[value.label.text] = LabelRef{len(s.scopes) - 1, loop_index}
            }
            s.parent_loop_index = loop_index
            s.loop_index += 1
            loop_body_array := make([dynamic]CheckedStatement)
            outer: switch iter in value.iterator {
            case Unit:
                type := Type.unknown_type
                v := expect_runtime_value(
                    s,
                    iter.pos,
                    check_value(s, iter, CheckValueArgs{body, AnyType{&type}, generic_args, nil}),
                )
                if v == nil {
                    return nil, false
                }
                #partial switch t in get_type(s.types, simplify_type(s, type)).key {
                case ArrayType:
                    array_item_type := t.item_type
                    if value.variables[2].text != "" {
                        diagnostic(
                            s,
                            stmt.position,
                            "You can only capture at most 2 variables from iterating over an array",
                        )
                        return nil, false
                    }
                    elem_ref, elem_ok := add_variable(
                        s,
                        array_item_type,
                        Ident{value.variables[0].text, value.variables[0].pos, false},
                    )
                    index_ref, index_ok := add_variable(
                        s,
                        .uint_type,
                        Ident{value.variables[1].text, value.variables[1].pos, false},
                    )
                    if !elem_ok || !index_ok {
                        return nil, false
                    }
                    loop_variables, loop_body_ok := check_block(
                        s,
                        value.body,
                        &loop_body_array,
                        generic_args,
                    )
                    if !loop_body_ok {
                        return nil, false
                    }
                    append_elem(
                        body,
                        iterate_array(
                            loop_index,
                            index_ref,
                            elem_ref,
                            &DoubleDynamic(CheckedStatement){loop_body_array, 0},
                            loop_variables,
                            v,
                            t,
                        ),
                    )
                    break outer
                case OrderedHashMapTypeWithStringKey:
                    key, key_ok := add_variable(
                        s,
                        .string_type,
                        Ident{value.variables[0].text, value.variables[0].pos, false},
                    )
                    value_var, value_var_ok := add_variable(
                        s,
                        t.value_type,
                        Ident{value.variables[1].text, value.variables[1].pos, false},
                    )
                    index, index_ok := add_variable(
                        s,
                        .uint_type,
                        Ident{value.variables[2].text, value.variables[2].pos, false},
                    )
                    if !key_ok || !value_var_ok || !index_ok {
                        return nil, false
                    }
                    loop_variables, loop_body_ok := check_block(
                        s,
                        value.body,
                        &loop_body_array,
                        generic_args,
                    )
                    if !loop_body_ok {
                        return nil, false
                    }
                    append_elem(
                        body,
                        iterate_ordered_hash_map(
                            loop_index,
                            v,
                            index,
                            key,
                            value_var,
                            &DoubleDynamic(CheckedStatement){loop_body_array, 0},
                            loop_variables,
                        ),
                    )
                    break outer
                }
                diagnostic(
                    s,
                    iter.pos,
                    "Expected an array or an `OrderedHashMap`, got the type `%s`",
                    type_to_string(s, type),
                )

            case NumericIterator:
                if value.variables[1].text != "" || value.variables[2].text != "" {
                    diagnostic(
                        s,
                        stmt.position,
                        "You can only capture at most one variable in a numeric iterator",
                    )
                    return nil, false
                }
                index_variable, var_ok := add_variable(
                    s,
                    .int_type, // TODO: Support types other than Int
                    Ident{value.variables[0].text, value.variables[0].pos, false},
                )
                expected_type: Type = .int_type
                start := expect_runtime_value(
                    s,
                    iter.start.pos,
                    check_value(
                        s,
                        iter.start,
                        CheckValueArgs{&loop_body_array, expected_type, generic_args, nil},
                    ),
                )
                end := expect_runtime_value(
                    s,
                    iter.end.pos,
                    check_value(
                        s,
                        iter.end,
                        CheckValueArgs{&loop_body_array, expected_type, generic_args, nil},
                    ),
                )
                step: CheckedValue = ---
                if iter.step == nil {
                    step = CompileTimeValue(NumberValue{false, big_uint_from_u64(1), ""})
                } else {
                    step = expect_runtime_value(
                        s,
                        iter.step.pos,
                        check_value(
                            s,
                            iter.step^,
                            CheckValueArgs{&loop_body_array, expected_type, generic_args, nil},
                        ),
                    )
                }
                if !var_ok || start == nil || end == nil || step == nil {
                    return nil, false
                }
                loop_variables, loop_body_ok := check_block(
                    s,
                    value.body,
                    &loop_body_array,
                    generic_args,
                )
                if !loop_body_ok {
                    return nil, false
                }
                append_elem(
                    body,
                    iterate_start_end_step(
                        loop_index,
                        index_variable,
                        iter.type,
                        start,
                        end,
                        step,
                        &DoubleDynamic(CheckedStatement){loop_body_array, 0},
                        loop_variables,
                    ),
                )
            }

        case IfElseStatement:
            expected_type: Type = .bool_type
            condition := expect_runtime_value(
                s,
                value.condition.pos,
                check_value(
                    s,
                    value.condition,
                    CheckValueArgs{body, expected_type, generic_args, nil},
                ),
            )

            append_elem(&s.scopes, Scope{})
            if_block_array := make([dynamic]CheckedStatement)
            if_variables, if_block_ok := check_block(
                s,
                value.if_block,
                &if_block_array,
                generic_args,
            )
            if_block := CheckedBlock{if_variables, if_block_array[:]}
            pop_scope(s)

            append_elem(&s.scopes, Scope{})
            else_block_array := make([dynamic]CheckedStatement)
            else_variables, else_block_ok := check_block(
                s,
                value.else_block,
                &else_block_array,
                generic_args,
            )
            else_block := CheckedBlock{else_variables, else_block_array[:]}
            pop_scope(s)

            if condition == nil || !if_block_ok || !else_block_ok {
                return nil, false
            }
            append_elem(body, CheckedIf{condition, if_block, else_block})

        case ContinueStatement:
            if stmt_index + 1 != len(block) {
                diagnostic(s, stmt.position, "Continue statement must be last statement in block")
                return nil, false
            }
            if s.parent_loop_index == max(uint) {
                diagnostic(s, stmt.position, "Continue statement must go inside a loop")
                return nil, false
            }
            if value.label.text == "" {
                append_elem(body, ContinueLoop{s.parent_loop_index})
            } else {
                loop_ref, ok := s.labels_map[value.label.text]
                if !ok {
                    diagnostic(
                        s,
                        value.label.pos,
                        "There is no parent loop labelled with `%s`",
                        value.label.text,
                    )
                    return nil, false
                }
                append_elem(body, ContinueLoop{loop_ref.loop_index})
            }

        case UnreachableStatement:
            if stmt_index + 1 != len(block) {
                diagnostic(
                    s,
                    stmt.position,
                    "Unreachable statement must be last statement in block",
                )
                return nil, false
            }
            append_elem(body, UnreachableStatement{})

        case ReturnStatement:
            if stmt_index + 1 != len(block) {
                diagnostic(s, stmt.position, "Return statement must be last statement in block")
                return nil, false
            }
            if len(value) != len(s.return_types) {
                diagnostic(
                    s,
                    stmt.position,
                    "Function returns %d values, but %d values given",
                    len(s.return_types),
                    len(value),
                )
                return nil, false
            }
            switch len(value) {
            case 0:
                append_elem(body, CheckedReturn{nil})
            case 1:
                v := expect_runtime_value(
                    s,
                    value[0].pos,
                    check_value(
                        s,
                        value[0],
                        CheckValueArgs{body, s.return_types[0], generic_args, nil},
                    ),
                )
                if v == nil {
                    return nil, false
                }
                append_elem(body, CheckedReturn{v})
            case:
                diagnostic(
                    s,
                    stmt.position,
                    "Can only have <=1 value in return statement (TODO: add support for returning >1 values)",
                )
            }

        case YieldStatement:
            diagnostic(s, stmt.position, "TODO: Handle yield statement")
            return nil, false

        case MatchStatement:
            val_type := Type.unknown_type
            val := expect_runtime_value(
                s,
                value.value.pos,
                check_value(
                    s,
                    value.value,
                    CheckValueArgs{body, AnyType{&val_type}, generic_args, nil},
                ),
            )
            if val == nil {
                return nil, false
            }

            val_sum_type, _, val_sum_type_ok := get_sum_type(s, value.value.pos, val_type)
            if !val_sum_type_ok {
                return nil, false
            }

            variable_ref := add_unnamed_variable(s, val_type, false)
            append_elem(body, CheckedAssignment{variable_ref, val})

            variant_has_branch := make([]bool, len(val_sum_type.m.keys))
            variant_branch_positions := make([]Pos, len(val_sum_type.m.keys))

            branches := arena_make(s.a, []CheckedMatchBranch, len(val_sum_type.m.keys))
            for branch in value.branches {
                append_elem(&s.scopes, Scope{})
                defer pop_scope(s)

                branch_type: Unit = ---
                variable_name: ^Unit = nil
                if joined, is_joined := branch.label.first_unit.(HierarchyJoinedUnits); is_joined {
                    if joined.join_method != .Colon {
                        diagnostic(
                            s,
                            branch.label.pos,
                            "Expected the join method to be `:`, got %v",
                            joined.join_method,
                        )
                        return nil, false
                    }
                    variable_name = joined.unit0
                    branch_type = joined.unit1^
                } else {
                    branch_type = branch.label
                }

                type_variable, is_variable := branch_type.first_unit.(IdentNode)
                if !is_variable ||
                   len(type_variable.segments) != 2 ||
                   type_variable.segments[0].ident != "" ||
                   type_variable.has_re_before {
                    diagnostic(
                        s,
                        branch_type.pos,
                        "Expected type variable without a generic type that starts with `.`",
                    )
                    return nil, false
                }

                variant_name := type_variable.segments[1].ident
                variant := lookup(val_sum_type.m, variant_name, string_to_index_procs)
                if variant == does_not_exist {
                    diagnostic(
                        s,
                        branch_type.pos,
                        "The sum type `%s` does not have the variant `.%s`",
                        type_to_string(s, val_type),
                        variant_name,
                    )
                    return nil, false
                }

                if variant_has_branch[variant.index] {
                    diagnostic(
                        s,
                        branch_type.pos,
                        "The variant `.%s` already has a branch defined at %v",
                        variant_name,
                        variant_branch_positions[variant.index],
                    )
                    return nil, false
                }

                var: union {
                        VariableRef,
                    } = nil
                if variable_name != nil {
                    ident, is_ident := variable_name.first_unit.(IdentNode)
                    if !is_ident ||
                       len(ident.segments) != 1 ||
                       ident.segments[0].has_dollar_at_end ||
                       ident.has_re_before {
                        diagnostic(s, variable_name.pos, "Expected " + plain_ident_normal)
                        return nil, false
                    }
                    var_ok: bool = ---
                    var, var_ok = add_variable(
                        s,
                        val_sum_type.payloads.d[variant.index],
                        ident.segments[0],
                    )
                    if !var_ok {
                        return nil, false
                    }
                }

                body := make([dynamic]CheckedStatement)
                variables, block_ok := check_block(s, branch.body, &body, generic_args)
                if !block_ok {
                    return nil, false
                }

                branches[variant.index] = CheckedMatchBranch{CheckedBlock{variables, body[:]}, var}
                variant_has_branch[variant.index] = true
                variant_branch_positions[variant.index] = branch.label.pos
            }

            unhandled_variants := false
            for has_branch, i in variant_has_branch {
                if !has_branch {
                    diagnostic(
                        s,
                        stmt.position,
                        "Unhandled variant `.%s`",
                        val_sum_type.m.keys[i].key,
                    )
                    unhandled_variants = true
                }
            }
            if unhandled_variants {
                return nil, false
            }
            append_elem(body, CheckedMatch{variable_ref, branches})

        }

        when debug_checker {
            debug("length of body is %d", len(body))
        }
    }
    variables := s.scopes[len(s.scopes) - 1].variables
    return variables.type[:len(variables)], true
}

value_err1 :: "Compiler cannot generate a `.` function without knowing the return type of the function"

check_namespaced_var_ref :: proc(
    s: ^CheckerState,
    namespace: ^CompilerFile,
    segments: #soa[]Ident,
    index: int,
) -> (
    CheckedValue,
    Type,
    int,
) {
    namespace_index := get_file_index(s.files, namespace)
    file_globals := s.parsed_files[namespace_index]
    parsed_global, global_exists := file_globals[segments[index].ident]
    if !global_exists {
        diagnostic(
            s,
            segments[index].pos,
            "The variable `%s` is not defined in the file `%s`",
            segments[index].ident,
            s.files.d[namespace_index].file_path,
        )
        return nil, .invalid_type, 0
    }
    if parsed_global.has_generics {
        return CompileTimeValue(GlobalValueWithGenericRef{parsed_global.index}),
            .unknown_type,
            index + 1
    } else {
        global_value := check_global_value_without_generic(
            s,
            GlobalValueWithoutGenericRef{uint(parsed_global.index)},
        )
        if global_value.type == .invalid_type {
            assert(global_value.value == nil)
            return nil, .invalid_type, 0
        }
        // if global_value.type == imported_file_type && index + 1 < len(ref.segments) {
        // return check_namespaced_var_ref(s, global_value.value.(Import).file, ref, index + 1)
        // }
        return global_value.value, global_value.type, index + 1
        // switch value in global.value {
        // case:
        //     panic("Unreachable")
        // case nil:
        //     diagnostic(
        //         s,
        //         ref[index].pos,
        //         "Either this global has not been defined yet, there was an error checking this global, or this type of global is not yet supported (TODO)",
        //     )
        //     return nil, invalid_type, 0
        // case CheckerGlobalValueWithoutGeneric:
        //     return value.inline_value, value.type, index + 1
        // case Import:
        //     if index + 1 >= len(ref) {
        //         diagnostic(s, ref[index].pos, import_use_err)
        //         return nil, invalid_type, 0
        //     }
        //     return check_namespaced_var_ref(s, value.file, ref, index + 1)
        // }
        // initialised := initialise_global_type_without_generic(s, global_value.index)
        // if initialised == invalid_type {
        //     return nil, invalid_type, 0
        // }
        // return CompileTimeValue(initialised), type_type, index + 1
        /*
    switch global_value in global.value {
    case:
        panic("Unreachable")
    case nil:
        panic("Unreachable")
    case GlobalValueRef:
        switch value in s.global_values[global_value.index].value {
        case:
            panic("Unreachable")
        case nil:
            diagnostic(
                s,
                ref[index].pos,
                "Either this global has not been defined yet, there was an error checking this global, or this type of global is not yet supported (TODO)",
            )
            return nil, invalid_type, 0
        case CheckedGlobalRuntimeValue:
            return value.inline_value, value.type, index + 1
        case Import:
            if index + 1 >= len(ref) {
                diagnostic(s, ref[index].pos, import_use_err)
                return nil, invalid_type, 0
            }
            return check_namespaced_var_ref(s, value.file, ref, index + 1)
        }
    case GlobalTypeWithGenericRef:
        return CompileTimeValue(global_value), unknown_type, index + 1
    case GlobalTypeWithoutGenericRef:
        initialised := initialise_global_type_without_generic(s, global_value.index)
        if initialised == invalid_type {
            return nil, invalid_type, 0
        }
        return CompileTimeValue(initialised), type_type, index + 1
        */
    }
}

// Returns `nil, invalid_type, 0` if there was an error in the ref start
check_var_ref_start :: proc(
    s: ^CheckerState,
    pos: Pos,
    segments: #soa[]Ident,
    generic_args: map[string]Type,
) -> (
    CheckedValue,
    Type,
    int,
) {
    if segments[0].ident != "" && segments[0].ident in generic_args {
        return CompileTimeValue(generic_args[segments[0].ident]), .type_type, 1
    }
    if builtin_func, builtin_func_type := get_builtin_func_from_name(segments[0].ident);
       builtin_func != .invalid_builtin {
        return CompileTimeValue(builtin_func), builtin_func_type, 1
    }
    if builtin_type := get_builtin_type_from_name(segments[0].ident);
       builtin_type != .unknown_type {
        return CompileTimeValue(builtin_type), .type_type, 1
    }
    if segments[0].ident == "OrderedHashMap" {
        return CompileTimeValue(UninitialisedOrderedHashMapType{}), .unknown_type, 1
    }
    /*
    if ref.segments[0].ident == "compiler" {
        compiler_funcs :: "`compiler.emit_js_code`"
        if len(ref.segments) == 1 {
            diagnostic(s, pos, "Expected " + compiler_funcs + " got just `compiler`")
            return nil, invalid_type, 0
        }
        switch ref.segments[1].ident {
        case "emit_js_code":
            return .emit_js_code, string_any_ordered_hashmap_and_string_to_string_type, 2
        case:
            diagnostic(s, pos, "Expected " + compiler_funcs + " got `compiler.%s`", ref.segments[1].ident)
            return nil, invalid_type, 0
        }
    }
    */
    if var_ref, ok := s.variables_map[segments[0].ident]; ok {
        return var_ref, get_variable_type(s, var_ref), 1
    }
    return check_namespaced_var_ref(s, pos.file, segments, 0)
}

check_var_ref :: proc(
    s: ^CheckerState,
    segments: #soa[]Ident,
    pos: Pos,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_var_ref")
        print_arg("segments", segments)
        print_arg("a", a)
    }
    if len(segments) == 2 && segments[0].ident == "" {
        expected_return_type: Type = ---
        switch expected in a.type {
        case AnyType:
            diagnostic(s, pos, value_err1)
            return nil
        case Type:
            diagnostic(s, pos, "TODO: Generate `.` functions better")
            return nil
        case FunctionWithExpectedReturnTypes:
            if len(expected.expected_return_types) != 1 {
                diagnostic(
                    s,
                    pos,
                    "Compiler cannot generate a `.` function which generates %d return types",
                    len(expected.expected_return_types),
                )
                return nil
            }
            switch expected_return in expected.expected_return_types[0] {
            case AnyType, FunctionWithExpectedReturnTypes:
                diagnostic(s, pos, value_err1)
            case Type:
                expected_return_type = expected_return
            }
        }

        sum_type, type_type, sum_type_ok := get_sum_type(s, pos, expected_return_type)
        if !sum_type_ok {
            return nil
        }

        variant := lookup(sum_type.m, segments[1].ident, string_to_index_procs)
        if variant == does_not_exist {
            diagnostic(
                s,
                pos,
                "The sum type `%s` does not have a variant called `%s`",
                type_to_string(s, expected_return_type),
                segments[1].ident,
            )
            return nil
        }
        got := get_type(s.types, sum_type.payloads.d[variant.index])
        _, is_struct := got.key.(StructType)
        assert(is_struct)
        func_type := got.value.type
        assert(func_type != .unknown_type)
        // TODO: Use `StructTypeInitFunc` instead of `SumTypeInitFunc` if `type` is the struct type rather than the sum type
        return finish_checking_value(
            s,
            pos,
            a.type,
            SumTypeInitFunc{type_type, variant.index},
            func_type,
            "",
        )
        /*
        if len(variant.fields) != len(call.args) {
            argument_count_mismatch(
                s,
                pos,
                len(call.args),
                len(variant.fields),
                ..function_segments.ident[:len(function_segments)],
            )
            return nil
        }

        checked_args := make([]CheckedValue, len(call.args))
        args_ok := true
        for arg, i in call.args {
            expected_type := variant.fields[i].type
            when debug_checker {
                debug("expected_type is %#v", expected_type)
            }
            checked_args[i] = check_value(s, arg, body, &expected_type)
            if checked_args[i] == nil {
                args_ok = false
            }
        }
        if !args_ok {
            return nil
        }
        dest := add_unnamed_variable(s, type^, false)
        append_elem(body, CheckedSumTypeInitialisation{dest, type^, variant_index, checked_args})
        return dest
        */
    }

    out, out_type, start_i := check_var_ref_start(s, pos, segments, a.generic_args)
    if out == nil {
        return nil
    }
    for i := start_i; i < len(segments); i += 1 {
        extra_segment := segments[i]
        if extra_segment.ident == "len" {
            simplified := simplify_type(s, out_type)
            if simplified == .string_type {
                out_type = .uint_type
                out = LengthOfString{new_clone(out)}
                continue
            }
            #partial switch type in get_type(s.types, simplified).key {
            case ArrayType:
                out_type = .uint_type
                out = length_of_array(type, out)
                continue
            case OrderedHashMapTypeWithIntKey:
                out_type = .uint_type
                out = LengthOfOrderedHashMapWithIntKey{new_clone(out)}
                continue
            case OrderedHashMapTypeWithStringKey:
                out_type = .uint_type
                out = LengthOfOrderedHashMapWithStringKey{new_clone(out)}
                continue
            }
            diagnostic(
                s,
                extra_segment.pos,
                "The value before `.len` is of type `%s`\nExpected a string type, an array type, or an OrderedHashSet type",
                type_to_string(s, out_type),
            )
            return nil
        } else if extra_segment.ident == "to_str" {
            converted := to_str(s, extra_segment.pos, out, out_type)
            if converted == nil {
                return nil
            }
            out_type = .string_type
            out = converted
            continue
        } else if out_type == .imported_file_type {
            out, out_type, i = check_namespaced_var_ref(
                s,
                out.(CompileTimeValue).(Import).file,
                segments,
                i,
            )
            continue
        }
        struct_type, ok := get_struct_type(s, segments[i].pos, out_type)
        if !ok {
            return nil
        }
        field := lookup(struct_type.m, extra_segment.ident, string_to_index_procs)
        if field == does_not_exist {
            diagnostic(
                s,
                extra_segment.pos,
                "The field `%s` does not exist on the struct type `%s`",
                extra_segment.ident,
                type_to_string(s, out_type),
            )
            return nil
        }
        out_type = struct_type.types.d[field.index]
        out = create_field_access(out, field.index)
    }
    return finish_checking_value(s, pos, a.type, out, out_type, "")
}

check_array_initialisation :: proc(
    s: ^CheckerState,
    pos: Pos,
    array_type_node: CallWithFrontedSquareBrackets,
    array_type_pos: Pos,
    args: []Unit,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_array_initialisation")
    }
    array_type_value, ok := check_array_type(s, array_type_pos, array_type_node, a.generic_args)
    if !ok {
        return nil
    }
    array_type := create_type(&s.types, array_type_value).type
    if array_type_value.length != 0 && len(args) != int(array_type_value.length) {
        diagnostic(
            s,
            pos,
            "Type initialisation provides %d values\nType expects %d values",
            len(args),
            array_type_value.length,
        )
        return nil
    }
    compile_time_elems := make([dynamic]CompileTimeValue)
    for i := 0; i < len(args); i += 1 {
        value := expect_runtime_value(
            s,
            args[i].pos,
            check_value(
                s,
                args[i],
                CheckValueArgs{a.body, array_type_value.item_type, a.generic_args, nil},
            ),
        )
        if value == nil {
            ok = false
            append_elem(&compile_time_elems, nil)
        } else if comptime, is_comptime := value.(CompileTimeValue); is_comptime {
            append_elem(&compile_time_elems, comptime)
        } else {
            array_segments := make([]ArraySegment, len(args))
            for elem, j in compile_time_elems {
                array_segments[j] = SingleElemSegment{elem}
            }
            array_segments[i] = SingleElemSegment{value}
            for i += 1; i < len(args); i += 1 {
                value = expect_runtime_value(
                    s,
                    args[i].pos,
                    check_value(
                        s,
                        args[i],
                        CheckValueArgs{a.body, array_type_value.item_type, a.generic_args, nil},
                    ),
                )
                if value == nil {
                    ok = false
                } else {
                    array_segments[i] = SingleElemSegment{value}
                }
            }
            if !ok {
                return nil
            }
            return finish_checking_value(
                s,
                array_type_pos,
                a.type,
                ArrayLiteral{array_type, array_segments},
                array_type,
                "",
            )
        }
    }
    if !ok {
        return nil
    }
    return finish_checking_value(
        s,
        array_type_pos,
        a.type,
        CompileTimeValue(CompileTimeArray{array_type, compile_time_elems[:]}),
        array_type,
        "",
    )
}

// Returns `nil` on failure
check_function_call :: proc(
    s: ^CheckerState,
    pos: Pos,
    call: CallWithBrackets,
    body: ^[dynamic]CheckedStatement,
    expected_return_types: []ExpectedType,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> union {
        CheckedFunctionCall,
        CompileTimeValue,
    } {
    when debug_checker {
        print_call(loc, "check_function_call")
        print_arg("expected_return_types", expected_return_types)
    }

    func_args: []Type = ---
    when debug_checker {
        func_args = nil // So that `func_args` can be printed by `debug_arg` without causing a segfault
    }
    expected_type := FunctionWithExpectedReturnTypes{&func_args, expected_return_types}
    value := expect_runtime_value(
        s,
        call.unit_being_called.pos,
        check_initial_value(
            s,
            call.unit_being_called.pos,
            call.unit_being_called.unit,
            CheckValueArgs{body, expected_type, generic_args, nil},
        ),
    )
    if value == nil {
        return nil
    }

    if len(call.args) != len(func_args) {
        argument_count_mismatch(s, pos, len(call.args), len(func_args), "TODO")
        return nil
    }

    checked_args := make([]CheckedValue, len(call.args))
    for arg, i in call.args {
        arg_value := expect_runtime_value(
            s,
            arg.pos,
            check_value(s, arg, CheckValueArgs{body, Type(func_args[i]), generic_args, nil}),
        )
        if arg_value == nil {
            return nil
        }
        checked_args[i] = arg_value
    }

    return create_checked_func_call(value, checked_args)
}

AnyType :: struct {
    store: ^Type,
}

FunctionWithExpectedReturnTypes :: struct {
    args_store:            ^[]Type,
    expected_return_types: []ExpectedType,
}

ExpectedType :: union {
    AnyType,
    Type,
    FunctionWithExpectedReturnTypes,
}

check_value_with_markers :: proc(
    s: ^CheckerState,
    v: Unit,
    markers: []TextAndPos,
    a: CheckValueArgs,
) -> CheckedValue {
    if len(markers) == 0 {
        return check_value(s, v, a)
    }
    switch markers[0].text {
    case "load":
        value := check_value_with_markers(
            s,
            v,
            markers[1:],
            CheckValueArgs{a.body, .string_type, a.generic_args, nil},
        )
        if value == nil {
            return nil
        }
        comptime_value, is_comptime := value.(CompileTimeValue)
        if !is_comptime {
            diagnostic(s, v.pos, "Expected a compile time known value")
            return nil
        }

        joined, join_err := filepath.join(
            []string{v.pos.file.dir_path, string(comptime_value.(StringLiteralValue))},
            context.allocator,
        )
        if join_err != nil {
            diagnostic(s, v.pos, "Failed to join strings: %v", join_err)
            return nil
        }
        data, data_err := os.read_entire_file(joined, context.allocator)
        if data_err != nil {
            diagnostic(s, markers[0].pos, "Failed to read `%s`: %#v\n", joined, data_err)
            return nil
        }
        return finish_checking_value(
            s,
            markers[0].pos,
            a.type,
            CompileTimeValue(StringLiteralValue(data)),
            .string_type,
            "",
        )
    case "debug_ast":
        debug_unit(nil, v)
    case:
        diagnostic(
            s,
            markers[0].pos,
            "TODO: Handle the `%s` marker",
            markers[0].text,
            type = .Warning,
        )
    }

    return check_value_with_markers(s, v, markers[1:], a)
}

// For `check_value` and `check_joined_unit_value`:
// - Returns `nil` if there are errors in the value
// - The `body` arg may be appended to with statements that should be executed
//   before the value is accessed

check_joined_unit_value :: proc(
    s: ^CheckerState,
    pos: Pos,
    value: HierarchyJoinedUnits,
    a: CheckValueArgs,
) -> CheckedValue {
    // TODO: In lots of this code, `check_runtime_value` is used when the
    // operations should be performable on values that can only be used at
    // compile time, like a value of the type `type_type`
    array_err :: "Expected an array type\nGot the type `%s`"
    switch value.join_method {

    case .Colon:
        diagnostic(s, pos, "Cannot use `:` to join values")
        return nil

    case .In:
        val0_type := Type.unknown_type
        val0 := expect_runtime_value(
            s,
            value.unit0.pos,
            check_value(
                s,
                value.unit0^,
                CheckValueArgs{a.body, AnyType{&val0_type}, a.generic_args, nil},
            ),
        )
        val1_type := Type.unknown_type
        val1 := expect_runtime_value(
            s,
            value.unit1.pos,
            check_value(
                s,
                value.unit1^,
                CheckValueArgs{a.body, AnyType{&val1_type}, a.generic_args, nil},
            ),
        )
        if val0 == nil || val1 == nil {
            return nil
        }
        val0_expected_type := Type.invalid_type
        #partial switch t in get_type(s.types, simplify_type(s, val1_type)).key {
        case OrderedHashMapTypeWithIntKey:
            val0_expected_type = .int_type
        case OrderedHashMapTypeWithStringKey:
            val0_expected_type = .string_type
        }
        if val0_expected_type == .invalid_type {
            diagnostic(
                s,
                value.unit1.pos,
                "Expected an ordered hash map type\nGot the type %s",
                type_to_string(s, val1_type),
            )
            return nil
        }
        if !expect_exact_type(s, value.unit0.pos, val0_expected_type, val0_type, "") {
            return nil
        }
        out: CheckedValue = CheckedJoinedValues{.In, new_clone(val0), new_clone(val1)}
        return finish_checking_value(s, value.unit0.pos, a.type, out, .bool_type, "")

    case .Arrow:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, pos, a)
        }
        tuple, is_tuple := value.unit0.first_unit.(Tuple)
        if !is_tuple {
            diagnostic(
                s,
                value.unit1.pos,
                "While checking function type: The unit before the `->` should be a tuple (for example `(String, U64)`)",
            )
            return CompileTimeValue(Type.invalid_type)
        }
        assert(value.unit1 != nil)
        t, ok := check_function_type(s, tuple.elements, value.unit1, a.generic_args)
        if !ok {
            return nil
        }
        out: CheckedValue = CompileTimeValue(create_type(&s.types, t).type)
        return finish_checking_value(s, pos, a.type, out, .type_type, "")

    case .BooleanAnd, .BooleanOr:
        val0 := check_value(
            s,
            value.unit0^,
            CheckValueArgs{a.body, .bool_type, a.generic_args, nil},
        )
        val1 := check_value(
            s,
            value.unit1^,
            CheckValueArgs{a.body, .bool_type, a.generic_args, nil},
        )
        if val0 == nil || val1 == nil {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            .bool_type,
            "",
        )

    case .IsEqual, .IsNotEqual:
        t := Type.invalid_type
        val0 := expect_runtime_value(
            s,
            value.unit0.pos,
            check_value(s, value.unit0^, CheckValueArgs{a.body, AnyType{&t}, a.generic_args, nil}),
        )
        if val0 == nil {
            return nil
        }
        val1 := expect_runtime_value(
            s,
            value.unit1.pos,
            check_value(s, value.unit1^, CheckValueArgs{a.body, t, a.generic_args, nil}),
        )
        if val1 == nil {
            return nil
        }
        t_simplified := simplify_type(s, t)
        if t_simplified == .string_type {
            str_comp: CheckedValue = StringsAreEqual{new_clone(val0), new_clone(val1)}
            if value.join_method == .IsNotEqual {
                return create_not(str_comp)
            }
            return str_comp
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            .bool_type,
            "",
        )

    case .Append:
        t: Type = .unknown_type
        val0 := expect_runtime_value(
            s,
            value.unit0.pos,
            check_value(s, value.unit0^, CheckValueArgs{a.body, AnyType{&t}, a.generic_args, nil}),
        )
        if val0 == nil {
            return nil
        }
        length, item_type := check_array(s, value.unit0.pos, val0, t, array_err)
        if length == nil {
            return nil
        }
        val1 := expect_runtime_value(
            s,
            value.unit1.pos,
            check_value(
                s,
                value.unit1^,
                CheckValueArgs{a.body, Type(item_type), a.generic_args, nil},
            ),
        )
        if val1 == nil {
            return nil
        }
        return_type1 := ArrayType{0, item_type}
        return_type0 := create_type(&s.types, return_type1).type // TODO: Maybe `::` should be able to output fixed size arrays
        segments := make([]ArraySegment, 2)
        segments[0] = InlineArraySegment{val0}
        segments[1] = SingleElemSegment{val1}
        return finish_checking_value(
            s,
            pos,
            a.type,
            ArrayLiteral{return_type0, segments},
            return_type0,
            "",
        )

    case .StringConcat:
        val0 := expect_runtime_value(
            s,
            value.unit0.pos,
            check_value(
                s,
                value.unit0^,
                CheckValueArgs{a.body, .string_type, a.generic_args, nil},
            ),
        )
        val1 := expect_runtime_value(
            s,
            value.unit1.pos,
            check_value(
                s,
                value.unit1^,
                CheckValueArgs{a.body, .string_type, a.generic_args, nil},
            ),
        )
        if val0 == nil || val1 == nil {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(.StringConcat, val0, val1),
            .string_type,
            "",
        )

    case .Concat:
        type0: Type = ---
        type1: Type = ---
        val0 := expect_runtime_value(
            s,
            value.unit0.pos,
            check_value(
                s,
                value.unit0^,
                CheckValueArgs{a.body, AnyType{&type0}, a.generic_args, nil},
            ),
        )
        val1 := expect_runtime_value(
            s,
            value.unit1.pos,
            check_value(
                s,
                value.unit1^,
                CheckValueArgs{a.body, AnyType{&type1}, a.generic_args, nil},
            ),
        )
        if val0 == nil || val1 == nil {
            return nil
        }
        length0, item_type0 := check_array(s, value.unit0.pos, val0, type0, array_err)
        length1, item_type1 := check_array(s, value.unit1.pos, val1, type1, array_err)
        if length0 == nil || length1 == nil {
            return nil
        }
        if item_type0 != item_type1 {
            diagnostic(
                s,
                pos,
                "Array item type mismatch:\nItem type on left is %s\nItem type on right is %s",
                type_to_string(s, item_type0),
                type_to_string(s, item_type1),
            )
            return nil
        }
        return_type1 := ArrayType{0, item_type0}
        return_type := create_type(&s.types, return_type1).type // TODO: Maybe `++` should be able to output fixed size arrays
        segments := make([]ArraySegment, 2)
        segments[0] = InlineArraySegment{val0}
        segments[1] = InlineArraySegment{val1}
        return finish_checking_value(
            s,
            pos,
            a.type,
            ArrayLiteral{return_type, segments},
            return_type,
            "",
        )

    case .IsGreaterThan, .IsGreaterThanOrEqual, .IsLessThan, .IsLessThanOrEqual:
        // TODO: Do not assume number types
        val0 := expect_runtime_value(
            s,
            value.unit0.pos,
            check_value(s, value.unit0^, CheckValueArgs{a.body, .float_type, a.generic_args, nil}),
        )
        val1 := expect_runtime_value(
            s,
            value.unit1.pos,
            check_value(s, value.unit1^, CheckValueArgs{a.body, .float_type, a.generic_args, nil}),
        )
        if val0 == nil || val1 == nil {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            .bool_type,
            "",
        )

    case .Multiplication, .Subtraction, .Division, .Addition, .Modulo:
        get_output_type :: proc(m: HierarchyUnitJoinMethod) -> Type {
            #partial switch m {
            case .Multiplication, .Addition, .Modulo:
                return .uint_type
            case .Subtraction:
                return .int_type
            case .Division:
                return .float_type
            case:
                panic("Unreachable")
            }
        }
        // TODO: Do not assume number types
        val0_type := Type.invalid_type
        val1_type := Type.invalid_type
        val0 := expect_runtime_value(
            s,
            value.unit0.pos,
            check_value(
                s,
                value.unit0^,
                CheckValueArgs{a.body, AnyType{&val0_type}, a.generic_args, nil},
            ),
        )
        val1 := expect_runtime_value(
            s,
            value.unit1.pos,
            check_value(
                s,
                value.unit1^,
                CheckValueArgs{a.body, AnyType{&val1_type}, a.generic_args, nil},
            ),
        )
        if val0 == nil || val1 == nil {
            return nil
        }
        out_type := most_general_number_type(
            s,
            get_output_type(value.join_method),
            TypeAndPos{val0_type, value.unit0.pos},
            TypeAndPos{val1_type, value.unit1.pos},
        )
        if out_type == .invalid_type {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            create_joined_values(value.join_method, val0, val1),
            out_type,
            "",
        )

    case:
        panic(fmt.aprintf("Unreachable (join method is %v)", value.join_method))
    }

}

import_use_err :: "Cannot use an import as a runtime value"
mut_then_ident_use_err :: "Cannot use `mut` followed by an identifier as a value"
units_in_square_brackets_use_err :: "Cannots use `[...]` as a value"

/*
ValueWithGenericHint :: struct {
    ref:                 GlobalValueWithGenericRef,
    initialisations_ref: OrderedHashSetSlotRef,
    args:                []Type,
}

ValueHint :: union {
    ExpectedType,

    // Used if the value is a global value
    // If `ValueHint` is one of these variants, then the type of the `GlobalValue` is set by `check_value`
    ValueWithGenericHint,
    GlobalValueWithoutGenericRef,
}

// The `bool` returned is whether `check_value` should return early
start_checking_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    hint: ValueHint,
    generic_args: map[string]Type,
) -> (
    CheckedValue,
    bool,
) {
    switch value in hint {
    case ExpectedType:
        if expect_value_of_type(s, pos, value, nil, type_type, "") {
            return nil, false
        }
        return nil, true
    case ValueWithGenericHint:
        global_value := &s.generic_initialisations.values[value.initialisations_ref.index].value.v
        assert(global_value.type == unknown_type)
        assert(global_value.value == nil)
        global_value^ = CheckedGlobalValue{type_type, nil}
        created := create_type(&s.types, GenericTypeValue{value.ref, value.args, unknown_type})
        if created.result == .Merged {
            if created.type_value.(GenericTypeValue).initialised_type == invalid_type {
                return invalid_type, true
            }
            return created.type, true
        }
        initialised_type := check_type(
            s,
            s.global_values_with_generics[value.ref.index].value,
            generic_args,
        )
        created2 := create_type(
            &s.types,
            GenericTypeValue{value.ref, value.args, initialised_type},
        )
        assert(created.type == created2.type)
        if initialised_type == invalid_type {
            return invalid_type, true
        }
        return created.type, true
    case GlobalValueWithoutGenericRef:
        panic("TODO")
    case:
        panic("Unreachable")
    }
}
*/

CheckValueArgs :: struct {
    // Used if the value is a runtime value
    body:                        ^[dynamic]CheckedStatement,

    // TODO: Update the compiler so all type information flows from source to
    // destination and remove this field and
    type:                        ExpectedType,

    // Used if the value is defined inside a generic global value definition
    generic_args:                map[string]Type,

    // Used to prevent infinite cycles
    // Normally set to `nil`
    // If the value is a type and `early_exit_if_value_is_type != nil`, the
    // check value function returns
    // `finish_checking_early_return_type(s, v.pos, a)`
    early_exit_if_value_is_type: TypeKey,
}

finish_checking_early_return_type :: proc(
    s: ^CheckerState,
    pos: Pos,
    a: CheckValueArgs,
) -> CheckedValue {
    out := CompileTimeValue(create_type(&s.types, a.early_exit_if_value_is_type).type)
    return finish_checking_value(s, pos, a.type, out, .type_type, "")
}

index_type :: Type.int_type // TODO: Maybe uint_type should be used instead

// `CheckedIndex.start_index == nil` on failure
check_index :: proc(
    s: ^CheckerState,
    u: Unit,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
) -> CheckedIndex {
    joined, is_joined := u.first_unit.(HierarchyJoinedUnits)
    if len(u.extra_units) != 0 || !is_joined || joined.join_method != .Colon {
        start_index := expect_runtime_value(
            s,
            u.pos,
            check_value(s, u, CheckValueArgs{body, index_type, generic_args, nil}),
        )
        if start_index == nil {
            return CheckedIndex{}
        }
        return CheckedIndex{new_clone(start_index), nil}
    }
    start_index := expect_runtime_value(
        s,
        joined.unit0.pos,
        check_value(s, joined.unit0^, CheckValueArgs{body, index_type, generic_args, nil}),
    )
    end_index := expect_runtime_value(
        s,
        joined.unit1.pos,
        check_value(s, joined.unit1^, CheckValueArgs{body, index_type, generic_args, nil}),
    )
    if start_index == nil || end_index == nil {
        return CheckedIndex{}
    }
    return CheckedIndex{new_clone(start_index), new_clone(end_index)}
}

check_initial_value :: proc(
    s: ^CheckerState,
    pos: Pos,
    v: UnitWithoutPos,
    a: CheckValueArgs,
) -> CheckedValue {
    switch value in v {
    case:
        diagnostic(s, pos, "Internal error: got nil value in check_value")
        return nil

    case StructUnit:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, pos, a)
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            CompileTimeValue(check_struct_type(s, value, a.generic_args)),
            .type_type,
            "",
        )

    case CallWithFrontedSquareBrackets:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, pos, a)
        }
        array, ok := check_array_type(s, pos, value, a.generic_args)
        if !ok {
            return nil
        }
        return CompileTimeValue(create_type(&s.types, array).type)

    case SumUnit:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, pos, a)
        }
        variant_payloads := arena_make_multi(s.a, Multi(Type), len(value.m.keys))
        ok := true
        for key, i in value.m.keys {
            expect_camel_case(
                s,
                "the name of a sum type variant",
                TextAndPos{key.key, value.positions.d[i]},
            )
            variant_payloads.d[i] = check_struct_type(s, value.payloads.d[i], a.generic_args)
            if variant_payloads.d[i] == .invalid_type {
                ok = false
            }
        }
        if !ok {
            return nil
        }
        return finish_checking_value(
            s,
            pos,
            a.type,
            CompileTimeValue(
                create_type(&s.types, SumType{value.m, value.positions, variant_payloads}).type,
            ),
            .type_type,
            "",
        )
    case Import:
        diagnostic(s, pos, import_use_err)
        return nil

    case UnitsInSquareBrackets:
        diagnostic(s, pos, units_in_square_brackets_use_err)
        return nil

    case MarkedUnit:
        return check_value_with_markers(s, value.value^, value.markers, a)

    case Tuple:
        if len(value.elements) != 1 {
            diagnostic(
                s,
                pos,
                "Only tuples with one element are supported\nThis tuple has %d elements",
                len(value.elements),
            )
            return nil
        }
        return check_value(s, value.elements[0], a)

    case CallWithSquareBrackets:
        being_called_type := Type.invalid_type
        being_called_value := check_initial_value(
            s,
            value.unit_being_called.pos,
            value.unit_being_called.unit,
            CheckValueArgs{a.body, AnyType{&being_called_type}, a.generic_args, nil},
        )
        if being_called_value == nil {
            return nil
        }
        being_called_type = simplify_type(s, being_called_type)
        if being_called_type == .unknown_type {
            checked_args := make([]Type, len(value.args))
            ok := true
            for arg, i in value.args {
                checked_args[i] = check_type(s, arg, a.generic_args)
                if checked_args[i] == .invalid_type {
                    ok = false
                }
            }
            if !ok {
                return nil
            }
            #partial switch comptime_value in being_called_value.(CompileTimeValue) {
            case GlobalValueWithGenericRef:
                return check_comptime_func_call(s, pos, comptime_value, checked_args, a.type)
            case UninitialisedOrderedHashMapType:
                if a.early_exit_if_value_is_type != nil {
                    return finish_checking_early_return_type(s, pos, a)
                }
                if len(checked_args) != 2 {
                    argument_count_mismatch(s, pos, len(checked_args), 2, "OrderedHashMap")
                    return nil
                }
                key := simplify_type(s, checked_args[0])
                type_key: TypeKey
                if key == .string_type {
                    type_key = OrderedHashMapTypeWithStringKey{checked_args[1]}
                } else if key == .int_type {
                    type_key = OrderedHashMapTypeWithIntKey{checked_args[1]}
                } else {
                    diagnostic(
                        s,
                        pos,
                        "The key of an `OrderedHashMap` must be a `String` or an `Int`\nGot the key `%s`\nTODO: Support `OrderedHashMap`s with keys other than `String`s and `Int`s",
                        type_to_string(s, checked_args[0]),
                    )
                    return nil
                }
                out: CheckedValue = CompileTimeValue(create_type(&s.types, type_key).type)
                return finish_checking_value(s, pos, a.type, out, .type_type, "")
            case BuiltinFunction:
                assert(comptime_value == .cast_func)
                if len(checked_args) != 1 {
                    argument_count_mismatch(s, pos, len(checked_args), 1, "cast")
                    return nil
                }
                args := make([]Type, 1)
                args[0] = .any_type
                return_types := make([]Type, 1)
                return_types[0] = checked_args[0]
                return finish_checking_value(
                    s,
                    pos,
                    a.type,
                    CompileTimeValue(CastFunction{checked_args[0]}),
                    create_type(&s.types, FuncType{args, return_types}).type,
                    "",
                )
            }
            panic("Unreachable")
        } else if being_called_type == .type_type {
            // TODO: This function could expect 0 args, and you would
            // still be able to use the dervation syntax to create an ordered
            // hashmap value, so maybe all this code is unnecersarry
            type := simplify_type(s, being_called_value.(CompileTimeValue).(Type))
            type_value, ok := get_type(s.types, type).key.(OrderedHashMapTypeWithStringKey)
            if !ok {
                diagnostic(
                    s,
                    value.unit_being_called.pos,
                    "Got the type `%s`\nExpected an ordered hash map with a string key type (TODO: Support ordered hash maps with i64 key) for hash map creation",
                    type_to_string(s, type),
                )
                return nil
            }
            compile_time_items: map[string]CompileTimeValue
            runtime_items: map[string]CheckedValue
            order := make([dynamic]string)
            for arg in value.args {
                // Check structure
                if len(arg.extra_units) == 0 {
                    diagnostic(
                        s,
                        arg.pos,
                        "Expected `key = value` so there is an extra %d `= value` after this",
                        len(arg.extra_units),
                    )
                    return nil
                }
                if arg.extra_units[0].join_method != .Assign {
                    diagnostic(
                        s,
                        arg.extra_units[0].join_method_pos,
                        "Expected `key = value`, so the first join method is `=`\nGot join method `%v`",
                        arg.extra_units[0].join_method,
                    )
                    return nil
                }

                // Check key
                body := make([dynamic]CheckedStatement)
                key_value := check_initial_value(
                    s,
                    arg.pos,
                    arg.first_unit,
                    CheckValueArgs{&body, .string_type, a.generic_args, nil},
                )
                if key_value == nil {
                    return nil
                }
                key_comptime, is_comptime := key_value.(CompileTimeValue)
                if !is_comptime {
                    diagnostic(s, arg.pos, "Key must be comptile-time known value")
                    return nil
                }
                assert(len(body) == 0)
                key := string(key_comptime.(StringLiteralValue))
                if key in compile_time_items || key in runtime_items {
                    diagnostic(s, arg.pos, "The key `%s` is already specified in this map", key)
                    return nil
                }

                // Check value
                value := check_value(
                    s,
                    Unit {
                        arg.extra_units[0].unit.pos,
                        arg.extra_units[0].unit.unit,
                        arg.extra_units[1:],
                    },
                    CheckValueArgs{a.body, type_value.value_type, a.generic_args, nil},
                )
                if value == nil {
                    return nil
                }

                // Insert
                if value_comptime, value_is_comptime := value.(CompileTimeValue);
                   value_is_comptime {
                    compile_time_items[key] = value_comptime
                } else {
                    runtime_items[key] = value
                }
                append_elem(&order, key)
            }
            if len(runtime_items) == 0 {
                return finish_checking_value(
                    s,
                    pos,
                    a.type,
                    CompileTimeOrderedHashMapInitialisation{type, compile_time_items, order[:]},
                    type,
                    "",
                )
            }
            return finish_checking_value(
                s,
                pos,
                a.type,
                OrderedHashMapInitialisation{type, compile_time_items, runtime_items, order[:]},
                type,
                "",
            )
        }
        if len(value.args) != 1 {
            diagnostic(
                s,
                pos,
                "Indexed accesses into an array or ordered hash map must pass one value into the square brackets\nGot %d values",
                len(value.args),
            )
            return nil
        }
        if being_called_type == .string_type {
            index := check_index(s, value.args[0], a.body, a.generic_args)
            if index.start_index == nil {
                return nil
            }
            return finish_checking_value(
                s,
                pos,
                a.type,
                CheckedIndexedAccess{.String, new_clone(being_called_value), index},
                index.end_index == nil ? .char_type : .string_type,
                "",
            )
        }
        #partial switch t in get_type(s.types, being_called_type).key {
        case ArrayType:
            diagnostic(s, pos, bounds_checks_warning, type = .Warning)
            index := check_index(s, value.args[0], a.body, a.generic_args)
            if index.start_index == nil {
                return nil
            }
            //if t.length == 0 {
            //    diagnostic(
            //        s,
            //        value.array.pos,
            //        "TODO: Implement element access for dynamically sized arrays",
            //    )
            //    return nil, false
            //}
            return finish_checking_value(
                s,
                pos,
                a.type,
                CheckedIndexedAccess{.Array, new_clone(being_called_value), index},
                // TODO: Gives wrong type if being_called is a fixed-size array
                index.end_index == nil ? t.item_type : being_called_type,
                "",
            )
        case OrderedHashMapTypeWithIntKey:
            panic("TODO")
        case OrderedHashMapTypeWithStringKey:
            key_value := expect_runtime_value(
                s,
                value.args[0].pos,
                check_value(
                    s,
                    value.args[0],
                    CheckValueArgs{a.body, .string_type, a.generic_args, nil},
                ),
            )
            if key_value == nil {
                return nil
            }
            return finish_checking_value(
                s,
                pos,
                a.type,
                CheckedOrderedHashMapAccess{new_clone(being_called_value), new_clone(key_value)},
                t.value_type,
                "",
            )
        }
        diagnostic(
            s,
            value.unit_being_called.pos,
            "The value is of type `%s`\nExpected a string type, an array type or an `OrderedHashMap` type for indexed/keyed access",
            type_to_string(s, being_called_type),
        )
        return nil

    case Bool:
        return finish_checking_value(
            s,
            pos,
            a.type,
            CompileTimeValue(BoolValue(value)),
            .bool_type,
            "",
        )
    case FuncDefinitionRef:
        out_func, out_type := check_anonymous_func_head(s, value, a.generic_args)
        return finish_checking_value(s, pos, a.type, out_func, out_type, "")
    case CallWithBrackets:
        if array_type, is_array := value.unit_being_called.unit.(CallWithFrontedSquareBrackets);
           is_array {
            return check_array_initialisation(
                s,
                pos,
                array_type,
                value.unit_being_called.pos,
                value.args,
                CheckValueArgs{a.body, a.type, a.generic_args, nil},
            )
        }
        expected_return_types := make([]ExpectedType, 1)
        expected_return_types[0] = a.type
        call := check_function_call(s, pos, value, a.body, expected_return_types, a.generic_args)
        delete(expected_return_types)
        switch c in call {
        case nil:
            return nil
        case CompileTimeValue:
            return c
        case CheckedFunctionCall:
            return c
        case:
            panic("Unreachable")
        }

    case HierarchyJoinedUnits:
        return check_joined_unit_value(s, pos, value, a)

    case IdentNode:
        if value.has_re_before {
            diagnostic(s, pos, mut_then_ident_use_err)
            return nil
        }
        return check_var_ref(s, value.segments, pos, a)

    case Number:
        whole_part: BigUint = ---
        fraction_part: string = ---
        switch num in value.absolute_value {
        case WholeNonNegativeNumber:
            whole_part = big_uint_from_string(num.digits)
            fraction_part = ""
        case DecimalNonNegativeNumber:
            whole_part = big_uint_from_string(num.integer_part)
            fraction_part = num.fractional_part
        case:
            panic("Unreachable")
        }
        n := NumberValue{value.is_negated, whole_part, fraction_part}
        return finish_checking_value(s, pos, a.type, CompileTimeValue(n), guess_number_type(n), "")

    case String:
        out := CompileTimeValue(StringLiteralValue(strings.join(([]string)(value), "")))
        return finish_checking_value(s, pos, a.type, out, .string_type, "")

    case Char:
        out := CompileTimeValue(NumberValue{false, big_uint_from_u64(u64(value)), ""})
        return finish_checking_value(s, pos, a.type, out, .char_type, "")
    }
}

// Returns `ArrayElementAccess{}` on failure
check_array_index_derivation_subset :: proc(
    s: ^CheckerState,
    pos: Pos,
    args: []Unit,
    body: ^[dynamic]CheckedStatement,
    generic_args: map[string]Type,
) -> ArrayElementAccess {
    if len(args) != 1 {
        diagnostic(s, pos, "Expected 1 value in square brackets\nGot %d values", len(args))
        return ArrayElementAccess{}
    }
    index := check_value(s, args[0], CheckValueArgs{body, index_type, generic_args, nil})
    diagnostic(&s.r, pos, bounds_checks_warning, type = .Warning)
    return ArrayElementAccess{index}
}

// Returns `nil, .invalid_type` on failure
// The type returned is the type of the derivation alteration's value
check_derivation_subset :: proc(
    s: ^CheckerState,
    derivation_base_type: Type,
    unit: UnitWithPos,
    generic_args: map[string]Type,
    body: ^[dynamic]CheckedStatement,
) -> (
    DoubleDynamic(DerivationSubsetElement),
    Type,
) {
    if call, is_call := unit.unit.(CallWithSquareBrackets); is_call {
        subset, type := check_derivation_subset(
            s,
            derivation_base_type,
            call.unit_being_called^,
            generic_args,
            body,
        )
        if type == .invalid_type {
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        array_type, is_array := get_type(s.types, simplify_type(s, type)).key.(ArrayType)
        if !is_array {
            diagnostic(
                s,
                unit.pos,
                "Square bracket call expects an array\nGot the type `%s`",
                type_to_string(s, type),
            )
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        subset_elem := check_array_index_derivation_subset(
            s,
            unit.pos,
            call.args,
            body,
            generic_args,
        )
        if subset_elem.index == nil {
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        dynamic_append_elem(&subset, subset_elem)
        return subset, array_type.item_type
    }
    #partial switch t in get_type(s.types, simplify_type(s, derivation_base_type)).key {
    case ArrayType:
        args: []Unit = ---
        unit_being_called: ^UnitWithPos = ---
        #partial switch u in unit.unit {
        case UnitsInSquareBrackets:
            args = u.elements
            unit_being_called = nil
        case CallWithFrontedSquareBrackets:
            args = u.args
            unit_being_called = u.unit_being_called
        case:
            diagnostic(
                s,
                unit.pos,
                "For array type `%s`\nCan only use unit in square brackets as derivation subset\nGot %v",
                type_to_string(s, derivation_base_type),
                unit.unit,
            )
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        subset_elem := check_array_index_derivation_subset(s, unit.pos, args, body, generic_args)
        if subset_elem.index == nil {
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        if unit_being_called != nil {
            elems, type := check_derivation_subset(
                s,
                t.item_type,
                unit_being_called^,
                generic_args,
                body,
            )
            dynamic_insert(&elems, subset_elem)
            return elems, type
        } else {
            elems := DoubleDynamic(DerivationSubsetElement){}
            dynamic_append_elem(&elems, subset_elem)
            return elems, t.item_type
        }
    case OrderedHashMapTypeWithStringKey:
        unit_in_square_brackets, ok := unit.unit.(UnitsInSquareBrackets)
        if !ok {
            diagnostic(
                s,
                unit.pos,
                "For ordered hash map type `%s`\nCan only use unit in square brackets as derivation subset",
                type_to_string(s, derivation_base_type),
            )
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        if len(unit_in_square_brackets.elements) != 1 {
            diagnostic(
                s,
                unit.pos,
                "Expected 1 value in square brackets\nGot %d values",
                len(unit_in_square_brackets.elements),
            )
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        key := check_value(
            s,
            unit_in_square_brackets.elements[0],
            CheckValueArgs{body, .string_type, generic_args, nil},
        )
        if key == nil {
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        elements := DoubleDynamic(DerivationSubsetElement){}
        dynamic_append_elem(&elements, StringOrderedHashMapAccess{key})
        return elements, t.value_type
    case StructType:
        field, ok := unit.unit.(IdentNode)
        if !ok ||
           field.has_re_before ||
           len(field.segments) != 2 ||
           field.segments[0].ident != "" {
            diagnostic(
                s,
                unit.pos,
                "For struct type `%s`\nCan only use ident with 2 segments where first segment is empty and `re` is not before the ident as derivation subset",
                type_to_string(s, derivation_base_type),
            )
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        field_name := field.segments[1]
        field_index := lookup(t.m, field_name.ident, string_to_index_procs)
        if field_index == does_not_exist {
            diagnostic(
                s,
                unit.pos,
                "The field `%s` dost not exist in the struct type `%s`",
                field_name.ident,
                type_to_string(s, derivation_base_type),
            )
            return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
        }
        elements := DoubleDynamic(DerivationSubsetElement){}
        dynamic_append_elem(&elements, FieldAccess{field_index.index})
        return elements, t.types.d[field_index.index]
    case:
        diagnostic(
            s,
            unit.pos,
            "Cannot have derivation subset when the type of the derivation base is `%s`",
            type_to_string(s, derivation_base_type),
        )
        return DoubleDynamic(DerivationSubsetElement){}, .invalid_type
    }
}

check_value :: proc(
    s: ^CheckerState,
    v: Unit,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckedValue {
    when debug_checker {
        print_call(loc, "check_value")
        print_arg("v", v)
    }

    if len(v.extra_units) == 0 {
        return check_initial_value(s, v.pos, v.first_unit, a)
    }

    type := Type.any_type
    value := check_initial_value(
        s,
        v.pos,
        v.first_unit,
        CheckValueArgs{a.body, AnyType{&type}, a.generic_args, nil},
    )
    if value == nil {
        return nil
    }

    i := 0
    for i < len(v.extra_units) {
        extra_unit := v.extra_units[i]
        if extra_unit.join_method != .Tilde {
            diagnostic(
                s,
                extra_unit.join_method_pos,
                "Expected join method to be `~` to set the derivation subset",
            )
            return nil
        }
        derivation_subset, derivation_alteration_type := check_derivation_subset(
            s,
            type,
            extra_unit.unit,
            a.generic_args,
            a.body,
        )
        if derivation_alteration_type == .invalid_type {
            return nil
        }

        i += 1
        if i >= len(v.extra_units) {
            diagnostic(s, extra_unit.join_method_pos, "Expected a derivation alteration")
            return nil
        }

        extra_unit = v.extra_units[i]
        #partial switch extra_unit.join_method {
        case .Assign:
            new_value := check_initial_value(
                s,
                extra_unit.unit.pos,
                extra_unit.unit.unit,
                CheckValueArgs{a.body, derivation_alteration_type, a.generic_args, nil},
            )
            if new_value == nil {
                return nil
            }

            value = CheckedDerivation {
                new_clone(value),
                DerivationSubset{dynamic_to_fixed(derivation_subset)},
                DerivationAlteration{.Replace, new_clone(new_value)},
            }
        case .PipeEquals:
            // TODO: Support `|=` without curried functions
            arr := make([]Type, 1)
            arr[0] = derivation_alteration_type
            func := check_initial_value(
                s,
                extra_unit.unit.pos,
                extra_unit.unit.unit,
                CheckValueArgs {
                    a.body,
                    create_type(&s.types, FuncType{arr, arr}).type,
                    a.generic_args,
                    nil,
                },
            )
            if func == nil {
                return nil
            }
            value = CheckedDerivation {
                new_clone(value),
                DerivationSubset{dynamic_to_fixed(derivation_subset)},
                DerivationAlteration{.PipeThroughFunction, new_clone(func)},
            }
        case:
            diagnostic(
                s,
                extra_unit.join_method_pos,
                "Expected join method to be `=` to set the subset's new value or `|=` to update the subset's value",
            )
            return nil
        }

        i += 1
    }

    return finish_checking_value(s, v.pos, a.type, value, type, "")
}

get_inline_func_fields :: proc(s: ^CheckerState) -> (InlineFuncFields, Multi(VariableRef)) {
    if len(s.variables_map) == 0 {
        return InlineFuncFields{}, Multi(VariableRef){nil}
    }
    variables_from_outer_scope: map[string]VariableRef
    scope0: Scope
    lambda_args := arena_make_multi(s.a, Multi(VariableRef), 0, resizable = true)
    defer fix_resizable_multi(lambda_args)

    for var_name, var_ref in s.variables_map {
        variable := s.scopes[var_ref.nesting_level].variables[var_ref.index]

        if variable.is_reassignable {
            // Reassignable variables defined in an outer function are not accessible from an inline function
            continue
        }

        variables_from_outer_scope[var_name] = VariableRef{0, len(scope0.variables)}
        append_multi_dynamic(&lambda_args, len(scope0.variables), var_ref)
        append(&scope0.variables, variable)
    }

    return InlineFuncFields{variables_from_outer_scope, scope0}, lambda_args
}

// Returns `nil, invalid_type` on failure
check_anonymous_func_head :: proc(
    s: ^CheckerState,
    ref: FuncDefinitionRef,
    generic_args: map[string]Type,
) -> (
    CheckedValue,
    Type,
) {
    func := s.func_defs[ref.index]
    inline_func_fields, lambda_args := get_inline_func_fields(s)
    checked_func_type, ok := check_function_type(
        s,
        func.inputs.value_type[:len(func.inputs)],
        func.output,
        generic_args,
    )
    if !ok {
        return nil, .invalid_type
    }
    type := create_type(&s.types, checked_func_type).type
    checked_ref := CheckedFuncRef{len(s.checked_functions)}
    append(
        &s.checked_functions,
        CheckedFunction{type, ref, generic_args, nil, nil, inline_func_fields},
    )
    return Func{checked_ref, lambda_args}, type
}

// Returns `false` on failure
check_anonymous_func_body :: proc(s: ^CheckerState, ref: CheckedFuncRef) -> bool {
    checked_func := s.checked_functions[ref.index]
    generic_args := checked_func.generic_args
    func := s.func_defs[checked_func.definition.index]
    func_type := get_type(s.types, checked_func.type).key.(FuncType)

    s.return_types = make([]Type, len(func_type.return_types))
    s.loop_index = 0
    s.parent_loop_index = max(uint)
    assert(len(s.scopes) == 0)
    assert(len(s.variables_map) == 0)
    // We do not need to shallow clone
    // `checked_func.inline_stuff.variables_from_outer_scope` because we are the
    // only consumer of `checked_func.inline_stuff.variables_from_outer_scope`
    s.variables_map = checked_func.inline_stuff.variables_from_outer_scope
    assert(len(s.labels_map) == 0)
    for return_type, i in func_type.return_types {
        s.return_types[i] = return_type
    }
    append(&s.scopes, checked_func.inline_stuff.scope0)
    defer pop_scope(s)
    append(&s.scopes, Scope{})
    defer pop_scope(s)
    ok := true
    for arg_type, i in func_type.args {
        arg := func.inputs[i]
        _, var_ok := add_variable(s, arg_type, arg.name)
        if !var_ok {
            ok = false
        }
    }
    if !ok {
        return false
    }
    append(&s.scopes, Scope{})
    defer pop_scope(s)
    // TODO: Check that the function always returns if it has a return type
    body := make([dynamic]CheckedStatement)
    variables, block_ok := check_block(s, func.body, &body, generic_args)
    if !block_ok {
        return false
    }
    s.checked_functions[ref.index].variables = variables
    s.checked_functions[ref.index].body = body[:]
    return true
}

// Returns `CheckedGlobalValue{invalid_type, nil}` on failure
check_global_value_without_generic :: proc(
    s: ^CheckerState,
    ref: GlobalValueWithoutGenericRef,
    loc := #caller_location,
) -> CheckedGlobalValue {
    when debug_checker {
        print_call(loc, "check_global_value_without_generic")
    }
    global := &s.global_values_without_generic[ref.index]
    if global.v.type != .unknown_type {
        return global.v
    }
    // defer global.v = out
    value := global.ast_node
    //if func_ref, is_func := value.unit.value.(FuncDefinitionRef); is_func {
    //    // func := s.func_defs[func_ref.index]
    //    ref, type, func_type := check_anonymous_func_head(s, func_ref, no_generic_args)
    //    s.global_values_without_generic[i].type = type
    //    if ref.index == max(uint) {
    //        return false
    //    }
    //    s.global_values_without_generic[i].value = ref
    //    return check_anonymous_func_body(s, func, func_type, ref, no_generic_args)
    //}
    if import_value, is_import := value.unit.first_unit.(Import); is_import {
        global.v = CheckedGlobalValue{.imported_file_type, import_value}
        return global.v
    }
    body: [dynamic]CheckedStatement = nil
    early_exit_if_value_is_type: TypeKey = GlobalType{ref}
    type: Type = .unknown_type
    old_scope_state := s.scope_state
    s.scope_state = CheckerScopeState{}
    checked_value := check_value(
        s,
        value.unit,
        CheckValueArgs{&body, AnyType{&type}, no_generic_args, early_exit_if_value_is_type},
    )
    s.scope_state = old_scope_state
    when debug_checker {
        debug(
            "Checked global with name `%s` and type `%v`",
            global.ast_node.name,
            type_to_string(s, type),
        )
    }
    if checked_value == nil {
        global.v = CheckedGlobalValue{.invalid_type, nil}
        return global.v
    }
    comptime_value, ok := checked_value.(CompileTimeValue)
    if !ok {
        diagnostic(s, value.unit.pos, non_compiletime_global_err)
        global.v = CheckedGlobalValue{.invalid_type, nil}
        return global.v
    }
    assert(len(body) == 0)
    if type == .invalid_type {
        assert(comptime_value == nil)
    }
    global.v = CheckedGlobalValue{type, comptime_value}
    if type == .type_type {
        type_value := comptime_value.(Type)
        assert(type_key_is_equal(s.types.m.keys[type_value].key, early_exit_if_value_is_type))
        initialised_type := check_value(
            s,
            value.unit,
            CheckValueArgs{nil, AnyType{&type}, no_generic_args, nil},
        )
        assert(type == .type_type)
        if initialised_type != nil {
            s.types.values.d[type_value].type = initialised_type.(CompileTimeValue).(Type)
        }
    }
    return global.v
}

length_of_array :: proc(type: ArrayType, value: CheckedValue) -> CheckedValue {
    if type.length != 0 {
        return CompileTimeValue(NumberValue{false, big_uint_from_u64(u64(type.length)), ""})
    }
    return LengthOfArray{new_clone(value)}
}

// Returns `nil, Type{}` if there was an error
// The `CheckedValue` returned is the length of the array
// The `Type` returned is the array's item_type
check_array :: proc(
    s: ^CheckerState,
    pos: Pos,
    value: CheckedValue,
    value_type: Type,

    // The error message for if the value is not an array
    // Must have one `%s` in it for the actual type of the value
    err_msg: string,
) -> (
    CheckedValue,
    Type,
) {
    array, ok := get_array_type(s, pos, "This value", value_type)
    if !ok {
        // diagnostic(s, pos, err_msg, type_to_string(s, value_type))
        return nil, Type{}
    }
    return length_of_array(array, value), array.item_type
}

get_global_function :: proc(
    s: ^CheckerState,
    usage_pos: Pos,
    file_to_search: ^CompilerFile,
    name: string,
    extra_text: string,
) -> (
    CheckedFuncRef,
    Pos,
    bool,
) {
    parsed_global, exists := s.parsed_files[get_file_index(s.files, file_to_search)][name]
    if !exists {
        diagnostic(s, usage_pos, "The global `%s` is not defined%s", name, extra_text)
        return CheckedFuncRef{}, unknown_pos, false
    }
    pos := usage_pos == unknown_pos ? Pos{parsed_global.pos, file_to_search} : usage_pos
    if parsed_global.has_generics {
        diagnostic(
            s,
            pos,
            "The global `%s` has generic\nExpected it to not have generics%s",
            name,
            extra_text,
        )
        return CheckedFuncRef{}, unknown_pos, false
    }
    global := s.global_values_without_generic[parsed_global.index]
    func_ref, is_func := global.v.value.(Func)
    if !is_func {
        diagnostic(
            s,
            pos,
            "The global value `%s` is not a function and so cannot be called%s",
            name,
            extra_text,
        )
        return CheckedFuncRef{}, unknown_pos, false
    }
    return func_ref.ref, Pos{parsed_global.pos, file_to_search}, true
}

EntryFuncType :: enum {
    BuildFunc,
    MainFunc,
}

CheckerOutput :: struct {
    reporter:                DiagnosticReporter,
    func_ref:                CheckedFuncRef,
    globals_without_generic: []GlobalValueWithoutGeneric,
    globals_with_generic:    []GlobalValueWithGeneric,
    checked_funcs:           []CheckedFunction,
    types:                   Types,
}

check :: proc(
    a: ^Arena,
    parsed: ParsedProject,
    func_name: string,
    io: Pipe(io.Writer),
) -> CheckerOutput {
    state := CheckerState {
        a                             = a,
        generic_initialisations       = GenericInitialisations {
            make_key_to_index(a, KeyToIndex(GenericInitialisation)),
            arena_make_multi(a, Multi(CheckedGlobalValue), 0, resizable = true),
        },
        r                             = DiagnosticReporter {
            parsed.files,
            io,
            [DiagnosticType]uint{},
        },
        parsed_files                  = parsed.parsed_files,
        global_values_without_generic = soa_zip(
            parsed.global_values_without_generic,
            make([]CheckedGlobalValue, len(parsed.global_values_without_generic)),
        ),
        global_values_with_generics   = parsed.global_values_with_generics,
        func_defs                     = parsed.function_defs,
        types                         = create_types(a),
    }
    defer {
        fix_types(state.types)
        fix_key_to_index(state.generic_initialisations.m)
        fix_resizable_multi(state.generic_initialisations.values)
    }

    for _, i in state.global_values_without_generic {
        state.global_values_without_generic[i].v.type = .unknown_type
    }

    for _, i in parsed.global_values_without_generic {
        check_global_value_without_generic(&state, GlobalValueWithoutGenericRef{uint(i)})
    }

    for state.first_unchecked_function < len(state.checked_functions) {
        // TODO: Do not pass `nil` in
        check_anonymous_func_body(&state, CheckedFuncRef{state.first_unchecked_function})
        state.first_unchecked_function += 1
    }

    for type in state.global_values_with_generics {
        // state.file = type.file
        for arg in type.generics {
            expect_camel_case(&state, "generic names", arg)
            if is_builtin(arg.text) {
                diagnostic(&state, arg.pos, builtins_err, arg.text)
            }
        }
        // TODO: Check that unused generics are valid
        // state.global_types_with_generics[i].generic_type = check_type(
        // &state,
        // type.ast_node.value,
        // type.ast_node.generic.ident,
        // )
    }

    // for _, i in state.global_values_without_generic {
    // initialise_global_type_without_generic(&state, uint(i))
    // }

    if state.r.number_of[.Error] > 0 {
        return CheckerOutput{reporter = state.r}
    }

    for file, i in parsed.parsed_files {
        // state.file = FileRef{uint(i)}
        // TODO: Iterating over globals as a map is a big source of the
        // non-deterministic error ordering in this compiler
        for global_name, global in file {
            if is_builtin(global_name) {
                diagnostic(&state, Pos{global.pos, &state.files.d[i]}, builtins_err, global_name)
                continue
            }
            // TODO: Check that the name is the correct case
            /*
            switch value in global.value {
            case GlobalValueWithoutGenericRef:
                expect_snake_case(&state, "variable names", IdentAndPos{global_name, global.pos})
                global_val := state.global_values_without_generics[value.index]
                func_ref, is_func := global_val.ast_node.unit.value.(FuncDefinitionRef)
                if !is_func {
                    continue
                }
                checked_func, func_ok := check_function(
                    &state,
                    parsed.function_defs[func_ref.index],
                    global_val.value.(CheckedGlobalRuntimeValue).type,
                )
                if func_ok {
                    checked_functions[func_ref.index] = checked_func
                }
            case GlobalValueWithGenericRef, GlobalValueWithoutGenericRef:
                expect_camel_case(&state, "type names", IdentAndPos{global_name, global.pos})
            }
            */
        }
    }

    if state.r.number_of[.Error] > 0 {
        return CheckerOutput{reporter = state.r}
    }

    func_ref, _, func_ok := get_global_function(
        &state,
        unknown_pos,
        &state.files.d[0],
        func_name,
        "\nTODO: Write hint",
    )
    if !func_ok {
        return CheckerOutput{reporter = state.r}
    }
    return CheckerOutput {
        state.r,
        func_ref,
        state.global_values_without_generic.ast_node[:len(state.global_values_without_generic)],
        state.global_values_with_generics,
        state.checked_functions[:],
        state.types,
    }

    /*
    hint ::
        "\n\nHint: If you define a `build` function, the compiler will run that " +
        "function at compile time to build the program, for example:\n\n" +
        "```\n" +
        "build = #comptime || {\n" +
        "    code = compiler.emit_c_code(this_can_have_any_name)\n" +
        "    write_file(\"code.c\", code)\n" +
        "}\n" +
        "this_can_have_any_name = || -> Int {\n    println(\"Hello world\")\n    return 0\n}\n" +
        "```\n\nIf no `build` function is defined, then you must specify a " +
        "`main` function, and the compiler will just emit C code to run that " +
        "`main` function, for example:\n\n" +
        "```\n" +
        "main = || -> Int {\n    println(\"Hello world\")\n    return 0\n}\n" +
        "```\n\n" +
        "TODO: Add link to docs"

    entry_func_ref: CheckedFuncRef = ---
    entry_func_type: EntryFuncType = ---
    if build_props, build_exists := parsed.files[0].globals["build"]; build_exists {
        if build_props.has_generics {
            diagnostic(
                &state,
                Pos{build_props.pos, FileRef{0}},
                "`build` is has generics\nExpected it to be a function without generics%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_value := state.global_values_without_generic[build_props.index]
        build_ref, build_is_func := build_value.v.value.(CheckedFuncRef)
        if !build_is_func {
            diagnostic(
                &state,
                Pos{build_props.pos, FileRef{0}},
                "`build` is a value other than a function\nExpected it to be a function%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_info := get_type(state.types, build_value.v.type).(FuncType)
        if build_info.type != .ComptimeFunc {
            diagnostic(
                &state,
                Pos{build_props.pos, FileRef{0}},
                "`build` is not marked with `#comptime`\nExpected it to be marked with `#comptime`%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_ref = build_ref
        entry_func_type = .BuildFunc
    } else {
        main_ref, main_pos, main_ok := get_global_function(
            &state,
            unknown_pos,
            FileRef{0},
            "main",
            hint,
        )
        if !main_ok {
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        main_info := get_type(state.types, state.checked_functions[main_ref.index].type).(FuncType)
        if main_info.type != .Normal {
            diagnostic(&state, main_pos, "`main` has a marker\nExpected `main` to not have a marker")
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        entry_func_ref = main_ref
        entry_func_type = .MainFunc
    }
    if state.diagnostics_info.number_of_errors > 0 {
        return CheckerOutput{diagnostics_info = state.diagnostics_info}
    }
    checked := Checked{state.checked_functions[:], state.types}
    return CheckerOutput{checked, state.diagnostics_info, entry_func_ref, entry_func_type}
    */
}


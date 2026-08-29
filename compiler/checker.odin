package compiler

import "../utils"
import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"

return_type_count_mismatch :: "Expected %d return types, but the function returns %d return types"

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
    length:    Maybe(u32), // `nil` means dynamic length
    item_type: Type,
}

HashMapKeyType :: enum u32 {
    String  = u32(Type.String),
    Int     = u32(Type.Int),
    UInt    = u32(Type.UInt),
    Float   = u32(Type.Float),
    Unknown = u32(Type.Unknown),
    Any     = u32(Type.Any),
}

OrderedHashMapType :: struct {
    key_type:   HashMapKeyType,
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
    m:      utils.KeyToIndex(GenericInitialisation),
    values: utils.Multi(utils.DebugValue(CheckedGlobalValue)),
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
    parsed_files:                  utils.Multi(map[string]ParsedGlobal), // len(parsed_files) == len(files)
    files:                         []utils.CompilerFile,
    global_values_without_generic: #soa[]CheckerGlobalValueWithoutGeneric,
    global_values_with_generics:   []GlobalValueWithGeneric,
    func_defs:                     []FunctionDefinition,

    // The following fields change while checking
    a:                             ^utils.Arena,
    r:                             utils.DiagnosticReporter,
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
    body:         utils.DebugValue([]CheckedStatement),
    inline_stuff: InlineFuncFields,
}

StringLiteralValue :: distinct string
CharValue :: distinct u8
IntValue :: distinct i64
BooleanNotValue :: distinct ^CheckedValue
CheckedJoinMethod :: enum {
    BooleanAnd           = int(UnitJoinMethod.BooleanAnd),
    BooleanOr            = int(UnitJoinMethod.BooleanOr),
    IsEqual              = int(UnitJoinMethod.IsEqual),
    IsNotEqual           = int(UnitJoinMethod.IsNotEqual),
    IsGreaterThan        = int(UnitJoinMethod.IsGreaterThan),
    IsLessThan           = int(UnitJoinMethod.IsLessThan),
    IsGreaterThanOrEqual = int(UnitJoinMethod.IsGreaterThanOrEqual),
    IsLessThanOrEqual    = int(UnitJoinMethod.IsLessThanOrEqual),
    In                   = int(UnitJoinMethod.In),
    StringConcat         = int(UnitJoinMethod.StringConcat), // &
    Addition             = int(UnitJoinMethod.Addition),
    Subtraction          = int(UnitJoinMethod.Subtraction),
    Modulo               = int(UnitJoinMethod.Modulo),
    Multiplication       = int(UnitJoinMethod.Multiplication),
    Division             = int(UnitJoinMethod.Division),
}
CheckedJoinedValues :: struct {
    join_method: CheckedJoinMethod,
    val0:        ^CheckedValue,
    val1:        ^CheckedValue,
}
CheckedFunctionCall :: struct {
    function: ^CheckedValue,
    args:     []CheckedValue,
}
SumTypeInitialisation :: struct {
    sum_type:      Type,
    variant_index: u32,
    payload:       ^CheckedValue, // May be `nil`
}
LengthOfString :: struct {
    str: ^CheckedValue,
}
LengthOfArray :: struct {
    array: ^CheckedValue,
}
LengthOfOrderedHashMap :: struct {
    hash_map: ^CheckedValue,
}
KeysOfOrderedHashMap :: struct {
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
ImportedFile :: struct {
    file_index: uint,
}
// UninitialisedGlobalWithGenerics :: struct {
// global: GlobalValueWithGenericRef,
// generic_args: []Type,
// }
UninitialisedOrderedHashMapType :: struct {}
CompileTimeStructInitialisation :: struct {
    struct_type: Type,
    fields:      []CompileTimeValue,
}
StructInitialisation :: struct {
    struct_type: Type,
    fields:      []CheckedValue,
}
CastFunction :: struct {
    type: Type,
}
CompileTimeOrderedHashMapInitialisation :: struct {
    type:  Type,
    value: map[HashMapKey]CompileTimeValue,
    order: []HashMapKey,
}
OrderedHashMapInitialisation :: struct {
    type:                Type,
    compile_time_values: map[HashMapKey]CompileTimeValue,
    runtime_values:      map[HashMapKey]CheckedValue,
    order:               []HashMapKey,
}
CompileTimeArray :: struct {
    type:     Type,
    elements: []CompileTimeValue,
}
CompileTimeValue :: union {
    CompileTimeArray,
    StringLiteralValue,
    utils.NumberValue,
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
    lambda_args: utils.Multi(VariableRef),
}
CheckedValue :: union {
    CompileTimeValue,
    ToString,
    VariableRef,
    BooleanNotValue,
    CheckedJoinedValues,
    CheckedFunctionCall,
    StructInitialisation,
    SumTypeInitialisation,
    CheckedIndexedAccess,
    CheckedOrderedHashMapAccess,
    CheckedFieldAccess,
    // CheckedJsFunctionCall,
    LengthOfArray,
    LengthOfString,
    LengthOfOrderedHashMap,
    KeysOfOrderedHashMap,
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

TypeAndRange :: struct {
    type:  Type,
    range: utils.Range,
}

expect_number :: proc(s: ^CheckerState, t: TypeAndRange) -> bool {
    #partial switch t.type {
    case .Int, .UInt, .Float:
        return true
    case:
        utils.diagnostic(
            s.r,
            t.range,
            "Expected a number type, but got the type `%s`",
            type_to_string(s, t.type),
        )
        return false
    }
}

most_general_number_type :: proc(
    s: ^CheckerState,
    first_type: Type,
    types: ..TypeAndRange,
) -> Type {
    out := first_type
    for type in types {
        ok := expect_number(s, type)
        if !ok {
            return .Invalid
        }
        if type.type < out {
            out = type.type
        }
    }
    return out
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
                utils.diagnostic(
                    s.r,
                    utils.Range {
                        ident.pos.index + i,
                        utils.to_debug_value(uint(1)),
                        ident.pos.file,
                    },
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
                utils.diagnostic(
                    s.r,
                    utils.Range {
                        ident.pos.index + i,
                        utils.to_debug_value(uint(1)),
                        ident.pos.file,
                    },
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
                utils.diagnostic(
                    s.r,
                    utils.Range {
                        ident.pos.index + i,
                        utils.to_debug_value(uint(1)),
                        ident.pos.file,
                    },
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
        utils.diagnostic(
            s.r,
            utils.Range{ident.pos.index, utils.to_debug_value(uint(1)), ident.pos.file},
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
            utils.diagnostic(
                s.r,
                utils.Range{ident.pos.index + i, utils.to_debug_value(uint(1)), ident.pos.file},
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
            utils.diagnostic(
                s.r,
                utils.Range{ident.pos.index + i, utils.to_debug_value(uint(1)), ident.pos.file},
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
    type_m: utils.KeyToIndex(string),
    type_positions: utils.Multi(utils.Pos),
    type_types: utils.Multi(Unit),
    generic_args: map[string]Type,
) -> Type {
    field_types := utils.arena_make_multi(s.a, utils.Multi(Type), len(type_m.keys))
    ok := true
    for field, i in type_m.keys {
        expect_snake_case(
            s,
            "the name of a struct field",
            TextAndPos{field.key, type_positions.d[i]},
            can_have_dollar_postfix = false,
        )
        field_types.d[i] = check_type(s, type_types.d[i], generic_args)
        if field_types.d[i] == .Invalid {
            ok = false
        }
    }
    if !ok {
        return .Invalid
    }

    created := create_type(&s.types, StructType{type_m, field_types})
    return created.type
}

// Returns `FuncType{}, false` on failure
check_function_type :: proc(
    s: ^CheckerState,
    inputs: []Unit,
    output: Maybe(Unit), // if the function has no output, then `output` is `nil`
    generic_args: map[string]Type,
) -> (
    FuncType,
    bool,
) {
    get_outputs :: proc(output: Maybe(Unit)) -> []Unit {
        if output == nil {
            return nil
        }
        o := output.(Unit)
        if len(o.rest) == 0 {
            if tuple, is_tuple := o.first.contents.(Tuple); is_tuple {
                return tuple.elements
            }
        }
        outputs := make([]Unit, 1)
        outputs[0] = o
        return outputs
    }

    ok := true

    args := make([]Type, len(inputs))
    for input, i in inputs {
        args[i] = check_type(s, input, generic_args)
        if args[i] == .Invalid {
            ok = false
        }
    }

    outputs := get_outputs(output)
    return_types := make([]Type, len(outputs))
    for output, i in outputs {
        return_types[i] = check_type(s, output, generic_args)
        if return_types[i] == .Invalid {
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
    item_type: Type,
    square_bracket_args: []Unit,
    square_bracket_args_range: utils.Range,
    generic_args: map[string]Type,
) -> (
    ArrayType,
    bool,
) {
    if len(square_bracket_args) == 0 {
        return ArrayType{nil, item_type}, true
    } else if len(square_bracket_args) == 1 {
        body := utils.to_debug_value([dynamic]CheckedStatement{})
        value := check_value_of_type(
            s,
            square_bracket_args[0],
            CheckValueArgs{&body, generic_args, nil},
            .UInt,
        )
        if !runtime_value_ok(s, get_range(square_bracket_args[0]), value) {
            return ArrayType{}, false
        }
        compile_time_value, is_comptime := value.(CompileTimeValue)
        if !is_comptime {
            utils.diagnostic(
                s.r,
                get_range(square_bracket_args[0]),
                "Expected a compile time value got a runtime value",
            )
            return ArrayType{}, false
        }
        number := compile_time_value.(utils.NumberValue)
        assert(len(body.v) == 0)
        assert(number.fraction_part == "")
        length, ok := utils.big_uint_to_u32(number.whole_part)
        if number.is_negated || !ok || length == 0 {
            utils.diagnostic(
                s.r,
                get_range(square_bracket_args[0]),
                "Expected an integer, n, where 0 < n <= max(u32)",
            )
            return ArrayType{}, false
        }
        return ArrayType{length, item_type}, true
    } else {
        utils.diagnostic(
            s.r,
            square_bracket_args_range,
            "Expected either 0 or 1 unit inside `[]`, got %d units",
            len(square_bracket_args),
        )
        return ArrayType{}, false
    }
}

// Returns `Invalid` if there are errors in the type
check_type :: proc(
    s: ^CheckerState,
    type: Unit,
    generic_args: map[string]Type,
    loc := #caller_location,
) -> Type {
    utils.call(loc, "check_type", "")
    body := utils.to_debug_value([dynamic]CheckedStatement{})
    value := check_value_of_type(s, type, CheckValueArgs{&body, generic_args, nil}, .Type)
    if value == nil {
        return .Invalid
    }
    assert(len(body.v) == 0)
    return value.(CompileTimeValue).(Type)
}

// TODO: It should not be possible to represent a value which cannot be used at runtime with `CheckedValue`, so this function should not be necersarry
// A "runtime value" is any value which can be used at runtime
// The boolean returned is whether `value` can be used as a runtime value
runtime_value_ok :: proc(
    s: ^CheckerState,
    range: utils.Range,
    value: CheckedValue,
    loc := #caller_location,
) -> bool {
    utils.call(loc, "runtime_value_ok", "")
    #partial switch v in value {
    case CompileTimeValue:
        #partial switch _ in v {
        case Type, GlobalValueWithGenericRef, UninitialisedOrderedHashMapType, Import:
            utils.diagnostic(s.r, range, "This value can only be used at compile time")
            return false
        }
        return true
    case nil:
        return false
    case:
        return true
    }
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
    body:          utils.DebugValue([]CheckedStatement),
}

CheckedLoopControlFlow :: struct {
    loop_index: uint,
    kind:       LoopControlFlowKind,
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
    label_range: utils.Range,
    block:       CheckedBlock,
    value_var:   Maybe(VariableRef), // May be nil
}

CheckedMatch :: struct {
    value:    VariableRef,
    branches: map[u32]CheckedMatchBranch, // The key is the tag name index
}

CheckedAssignment :: struct {
    dest:  VariableRef,
    value: CheckedValue,
}

CheckedStatement :: union {
    CheckedReturn,
    CheckedIf,
    CheckedLoop,
    CheckedLoopControlFlow,
    CheckedAssignment,
    CheckedFunctionCall,
    CheckedMatch,

    // TODO: Store where the statement is and tell the user where the statement is when it is reached
    UnreachableStatement,
}

non_compiletime_global_err :: "This value is not a compile time known constant\nAll global values must be compile time known constants"

generic_initialisation_to_index_procs :: utils.KeyToIndexProcs(GenericInitialisation) {
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
    function_range: utils.Range,
    global: GlobalValueWithGenericRef,
    generic_args: []Type,
    loc := #caller_location,
) -> CheckValueResult {
    // return CompileTimeValue(UninitialisedGlobalWithGenerics{global,generic_args})
    generic := &s.global_values_with_generics[global.index]
    if len(generic_args) != len(generic.generics) {
        argument_count_mismatch(s, function_range, len(generic_args), len(generic.generics))
        return CheckValueResult{nil, .Invalid}
    }

    ref, res := utils.lookup_or_insert(
        &s.generic_initialisations.m,
        GenericInitialisation{global, generic_args},
        generic_initialisation_to_index_procs,
    )
    if res == .LookedUp {
        value := s.generic_initialisations.values.d[ref.index]
        if value.v.type == .Unknown {
            utils.panicf("TODO: Handle cycles (value is %v)", value)
        }
        return CheckValueResult{value.v.value, value.v.type}
    } else {
        utils.resize_multi(
            &s.generic_initialisations.values,
            len(s.generic_initialisations.m.keys),
        )
        s.generic_initialisations.values.d[ref.index] = utils.to_debug_value(
            CheckedGlobalValue{.Unknown, nil},
        )
    }

    generic_args_map := make(map[string]Type)
    for arg, i in generic.generics {
        assert(!(arg.text in generic_args_map))
        generic_args_map[arg.text] = generic_args[i]
    }

    body := utils.to_debug_value([dynamic]CheckedStatement{})
    old_scope_state := s.scope_state
    s.scope_state = CheckerScopeState{}
    checked_value :=
        check_value(s, generic.value, CheckValueArgs{&body, generic_args_map, GenericTypeValue{global, generic_args}}).v
    s.scope_state = old_scope_state
    if checked_value.value == nil {
        s.generic_initialisations.values.d[ref.index] = utils.to_debug_value(
            CheckedGlobalValue{.Invalid, nil},
        )
        return CheckValueResult{nil, .Invalid}
    }
    comptime_value, ok := checked_value.value.(CompileTimeValue)
    s.generic_initialisations.values.d[ref.index] = utils.to_debug_value(
        CheckedGlobalValue{checked_value.type, comptime_value},
    )
    if !ok {
        utils.diagnostic(s.r, get_range(generic.value), non_compiletime_global_err)
        return CheckValueResult{nil, .Invalid}
    }
    assert(utils.debug_dynamic_array_len(body) == 0)

    if checked_value.type == .Type {
        type_value := comptime_value.(Type)
        checked_value2 :=
            check_value(s, generic.value, CheckValueArgs{nil, generic_args_map, nil}).v
        assert(checked_value2.type == .Type)
        assert(
            type_key_is_equal(
                s.types.m.keys[type_value].key,
                GenericTypeValue{global, generic_args},
            ),
        )
        s.types.values.d[type_value].type =
            checked_value2.value == nil ? .Invalid : checked_value2.value.(CompileTimeValue).(Type)
    }

    return checked_value
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
        return Invalid
    }

    created := create_type(
        &s.types,
        GenericTypeValue{generic_type_index, generic_args, Unknown},
    )
    if created.result == .Merged {
        if created.type_value.(GenericTypeValue).initialised_type == Invalid {
            return Invalid
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
    if initialised_type == Invalid {
        return Invalid
    }
    return created.type
}

initialise_global_type_without_generic :: proc(
    s: ^CheckerState,
    i: uint,
    loc := #caller_location,
) -> Type {
    when true {
        utils.call(loc, "initialise_global_type_without_generic", "")
    }
    // TODO: Check for cycles
    type := s.global_values_without_generic[i]
    if type.v.type == Type {
        return type.v.value.(Type)
    }
    if type.v.type != Unknown {
        utils.diagnostic(s, type.ast_node.unit.pos, "TODO: FIX") // TODO FIX
    }
    checked_type := check_type(s, type.ast_node.unit, no_generic_args)
    s.global_values_without_generic[i].v.value = CompileTimeValue(checked_type)
    return checked_type
}
*/

SimplifiedType :: struct {
    type: Type,
    key:  TypeKey,
}

simplify_type :: proc(s: ^CheckerState, type: Type, loc := #caller_location) -> SimplifiedType {
    utils.call(loc, "simplify_type", "")
    utils.print_arg("type", type)
    cur_type := type
    for {
        got := get_type(s.types, cur_type)
        #partial switch key in got.key {
        case GenericTypeValue, GlobalType:
            cur_type = got.value.type
            assert(cur_type != .Unknown)
        case nil:
            return SimplifiedType{cur_type, nil}
        case:
            if got.value.type != .Unknown {
                utils.panicf("got.value.type == %v", got.value.type)
            }
            return SimplifiedType{cur_type, got.key}
        }
    }
}

// For `get_sum_type`, `get_struct_type`, and `get_func_type`, set pos to
// `nil` to not report an error if it is not a sum/struct type

get_sum_type :: proc(
    s: ^CheckerState,
    range: Maybe(utils.Range),
    type: Type,
    loc := #caller_location,
) -> (
    SumType,
    Type,
    bool,
) {
    utils.call(loc, "get_sum_type", "")
    utils.print_arg("range", range)
    utils.print_arg("type", type)
    simplified := simplify_type(s, type)
    sum_type, is_sum_type := simplified.key.(SumType)
    if is_sum_type {
        utils.debug("returned SumType(StructType) is %#v", sum_type)
        return sum_type, simplified.type, true
    }
    if r, ok := range.(utils.Range); ok {
        utils.diagnostic(
            s.r,
            r,
            "Expected a sum type, but got the type `%s`",
            type_to_string(s, type),
        )
    }
    return SumType{}, .Unknown, false
}

get_struct_type :: proc(
    s: ^CheckerState,
    // range: Maybe(utils.Range),
    type: Type,
) -> (
    StructType,
    bool,
) {
    simplified := simplify_type(s, type)
    struct_type, is_struct_type := simplified.key.(StructType)
    if is_struct_type {
        return struct_type, true
    }
    /*
    if r, ok := pos.(utils.Range); ok {
        got := type_to_string(s, type)
        utils.diagnostic(s.r, r, "Expected a struct type, but got the type `%s`", got)
    }
    */
    return StructType{}, false
}

/*
get_func_type_from_struct_type :: proc(
    s: ^CheckerState,
    struct_type: StructType,
    return_type: Type,
) -> Type {
    func_return_types := make([]Type, 1)
    func_return_types[0] = return_type
    created := create_type(
        &s.types,
        FuncType {
            utils.multi_to_array(struct_type.types, len(struct_type.m.keys)),
            func_return_types,
        },
    )
    return created.type
}
*/

// Always returns a function type
// Returns `nil` on failure
get_func_type :: proc(
    s: ^CheckerState,
    value_range: utils.Range,
    value: CheckedValue,
    type: Type,
    loc := #caller_location,
) -> Maybe(FuncType) {
    utils.call(loc, "get_func_type", "")
    utils.print_arg("type", type_to_string(s, type))
    simplified := simplify_type(s, type)
    /*
    if simplified == .Type && value != nil {
        value_type_unsimplified := value.(CompileTimeValue).(Type)
        value_type := simplify_type(s, value_type_unsimplified)
        got := get_type(s.types, value_type)
        #partial switch type in got.key {
        case StructType:
            value^ = StructTypeInitFunc{value_type}
            return get_func_type_from_struct_type(s, type, value_type_unsimplified)
        }
        utils.diagnostic(
            s.r,
            pos,
            "The type `%s` cannot be converted to a function type",
            type_to_string(s, value_type_unsimplified),
        )
    }
    */
    if func, is_func := simplified.key.(FuncType); is_func {
        return func
    }
    if simplified.type == .Unknown && value != nil {
        // TODO: Also have this better error message for other functions:
        // - `get_struct_type`
        // - `get_sum_type`
        // - `expect_type`
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
            utils.diagnostic(
                s.r,
                value_range,
                "Expected a func type, but got an uninitialised global value with generics\nHint: Try initialising the global value with something like `%s`",
                strings.to_string(initialisation),
            )
            return nil
        }
    }
    utils.diagnostic(
        s.r,
        value_range,
        "Expected a func type, but got the type `%s`",
        type_to_string(s, type),
    )
    return nil
}

// Returns `nil` on success
// Returns a writer that needs closing on failure
expect_type_helper :: proc(
    s: ^CheckerState,
    range: utils.Range,
    got_unsimplified: Type,
    expected_unsimplified: Type,
    loc := #caller_location,
) -> (
    out: Maybe(io.Writer),
) {
    when ODIN_DEBUG {
        utils.call(
            loc,
            "expect_type_helper",
            "type: %v, superset: %v",
            get_type(s.types, got_unsimplified),
            get_type(s.types, expected_unsimplified),
        )
    }
    defer {
        if out != nil {
            w := out.(io.Writer)
            io.write_string(w, "Expected the type `")
            io.write_string(w, type_to_string(s, expected_unsimplified))
            io.write_string(w, "` but got the type `")
            io.write_string(w, type_to_string(s, got_unsimplified))
            io.write_string(w, "`\n")
        }
    }
    got := simplify_type(s, got_unsimplified)
    expected := simplify_type(s, expected_unsimplified)
    if got.type == expected.type {
        return
    }
    if expected.type == .Any {
        return
    }
    if expected.type == .Float {
        if got.type != .Int && got.type != .UInt {
            out = s.r.diagnostic_header(s.r.data, range, .Error)
        }
        return
    }
    if expected.type == .Int {
        if got.type != .UInt {
            out = s.r.diagnostic_header(s.r.data, range, .Error)
        }
        return
    }
    if expected.type > .MaxIndex {
        out = s.r.diagnostic_header(s.r.data, range, .Error)
        return
    }
    #partial switch superset_value in expected.key {
    case nil:
        panic("Unreachable")
    case:
        out = s.r.diagnostic_header(s.r.data, range, .Error)
        return
    case OrderedHashMapType:
        if got.type == .EmptyOrderedHashMap {
            return
        }
        type_value, is_ordered_hashmap_type := got.key.(OrderedHashMapType)
        if !is_ordered_hashmap_type {
            out = s.r.diagnostic_header(s.r.data, range, .Error)
            return
        }
        out = expect_type_helper(
            s,
            range,
            Type(type_value.key_type),
            Type(superset_value.key_type),
        )
        if out != nil {
            return
        }
        out = expect_type_helper(s, range, type_value.value_type, superset_value.value_type)
        if out != nil {
            return
        }
        return
    case ArrayType:
        type_value, is_array_type := got.key.(ArrayType)
        if !is_array_type {
            out = s.r.diagnostic_header(s.r.data, range, .Error)
            return
        }
        if type_value.length == 0 && (superset_value.length == 0 || superset_value.length == nil) {
            return
        }
        if superset_value.length == nil || superset_value.length == type_value.length {
            out = expect_type_helper(s, range, type_value.item_type, superset_value.item_type)
            return
        }
        out = s.r.diagnostic_header(s.r.data, range, .Error)
        return
    case StructType:
        type_value, is_struct_type := got.key.(StructType)
        if !is_struct_type {
            out = s.r.diagnostic_header(s.r.data, range, .Error)
            return
        }
        if len(superset_value.m.keys) != len(type_value.m.keys) {
            out = s.r.diagnostic_header(s.r.data, range, .Error)
            return
        }
        for superset_key, i in superset_value.m.keys {
            if superset_key.key != type_value.m.keys[i].key {
                out = s.r.diagnostic_header(s.r.data, range, .Error)
                return
            }
            out = expect_type_helper(s, range, type_value.types.d[i], superset_value.types.d[i])
            if out != nil {
                return
            }
        }
        return
    case SumType:
        type_value, is_sum_type := got.key.(SumType)
        if !is_sum_type {
            out = s.r.diagnostic_header(s.r.data, range, .Error)
            return
        }
        for tag_variant_index, tag_payload in type_value.payloads {
            if tag_variant_index not_in superset_value.payloads {
                out = s.r.diagnostic_header(s.r.data, range, .Error)
                return
            }
            type_payload, type_has_payload := tag_payload.(Type)
            superset_payload, superset_has_payload := superset_value.payloads[tag_variant_index].(Type)
            if type_has_payload != superset_has_payload {
                out = s.r.diagnostic_header(s.r.data, range, .Error)
                return
            }
            if !type_has_payload {
                continue
            }
            out = expect_type_helper(s, range, type_payload, superset_payload)
            if out != nil {
                return
            }
        }
        return
    case GenericTypeValue, GlobalType:
        panic("Unreachable")
    }
}

guess_number_type :: proc(n: utils.NumberValue) -> Type {
    // TODO: Check that `n` is in range
    if n.fraction_part != "" {
        return .Float
    }
    if n.is_negated {
        return .Int
    }
    return .UInt
}

/*
finish_checking_value :: proc(
    s: ^CheckerState,
    pos: utils.Pos,
    type: ExpectedType,
    got_value: CheckedValue,
    got_type: Type,
    extra_text: string,
    loc := #caller_location,
) -> CheckedValue {
    utils.call(loc, "finish_checking_value", "")
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
        assert(global_value.type == Unknown)
        assert(global_value.value == nil)
        global_value^ = CheckedGlobalValue{got_type, nil}
        comptime_value, ok := got_value.(CompileTimeValue)
        if !ok {
            utils.diagnostic(s, pos, non_compiletime_global_err)
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
*/

// For both `expect_value_of_type` and `expect_exact_type`
// - The boolean returned is whether the `got` type matches the `expected` type
// - TODO: Specify `extra_text` in all cases

/*
expect_value_of_type :: proc(
    s: ^CheckerState,
    pos: utils.Pos,
    expected: ExpectedType,
    got_value: ^CheckedValue,
    got_type: Type,
    extra_text: string,
    loc := #caller_location,
) -> bool {
    utils.call(loc, "expect_value_of_type", "")
    utils.print_arg("expected", expected)
    utils.print_arg("got_type", type_to_string(s, got_type))
    switch e in expected {
    case AnyType:
        e.store^ = got_type
        return true
    case Type:
        return expect_exact_type(s, pos, e, got_type, extra_text)
    case FunctionWithExpectedReturnTypes:
        func_type := get_func_type(s, pos, got_value, got_type)
        if func_type == .Invalid {
            return false
        }
        func_info := get_type(s.types, func_type).key.(FuncType)
        if len(func_info.return_types) != len(e.expected_return_types) {
            utils.diagnostic(
                s.r,
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
    case:
        panic("unreachable")
    }
}
*/

expect_type :: proc(
    s: ^CheckerState,
    range: utils.Range,
    expected: Type,
    got: Type,
    loc := #caller_location,
) -> bool {
    utils.call(loc, "expect_type", "")
    out := expect_type_helper(s, range, got, expected)
    if out == nil {
        return true
    }
    io.close(out.(io.Writer))
    return false
}

get_variable_type :: proc(
    s: ^CheckerState,
    variable: VariableRef,
    loc := #caller_location,
) -> Type {
    utils.call(loc, "get_variable_type", "")
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
    utils.call(loc, "type_to_string2", "")
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
    utils.call(loc, "build_type_string", "")
    // TODO: Format the string better
    #partial switch t {
    case .String:
        strings.write_string(b, "String")
    case .Int:
        strings.write_string(b, "Int")
    case .UInt:
        strings.write_string(b, "UInt")
    case .Float:
        strings.write_string(b, "Float")
    case .Char:
        strings.write_string(b, "Char")
    case .Bool:
        strings.write_string(b, "Bool")
    case .Invalid:
        strings.write_string(b, "Invalid")
    case .Unknown:
        strings.write_string(b, "Unknown")
    case .EmptyOrderedHashMap:
        strings.write_string(b, "EmptyOrderedHashMap")
    case .ImportedFile:
        strings.write_string(b, "ImportedFile")
    case .Type:
        strings.write_string(b, "Type")
    case .Any:
        strings.write_string(b, "Any")
    case:
        // TODO: For `GlobalType` and `StructType`, put the right namespace before the type
        switch tv in get_type(types, t).key {
        case GlobalType:
            strings.write_string(b, globals_without_generic[tv.global.index].name)
        case StructType:
            build_struct_string(types, globals_without_generic, globals_with_generic, b, tv)
        case SumType:
            strings.write_byte(b, '\\')
            first_variant := true
            for tag_variant_index, tag_payload in tv.payloads {
                if !first_variant {
                    strings.write_string(b, ", ")
                }
                tag_variant_name := types.sum_type_tags.keys[tag_variant_index].key
                if payload, has_payload := tag_payload.(Type); has_payload {
                    strings.write_string(b, tag_variant_name)
                    strings.write_string(b, ": ")
                    build_type_string(
                        types,
                        globals_without_generic,
                        globals_with_generic,
                        b,
                        payload,
                    )
                } else {
                    strings.write_byte(b, ':')
                    strings.write_string(b, tag_variant_name)
                }
                first_variant = false
            }
            strings.write_byte(b, '\\')
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
        case OrderedHashMapType:
            strings.write_string(b, "OrderedHashMap[")
            build_type_string(
                types,
                globals_without_generic,
                globals_with_generic,
                b,
                Type(tv.key_type),
            )
            strings.write_string(b, ", ")
            build_type_string(
                types,
                globals_without_generic,
                globals_with_generic,
                b,
                tv.value_type,
            )
            strings.write_string(b, "]")
        case ArrayType:
            build_type_string(
                types,
                globals_without_generic,
                globals_with_generic,
                b,
                tv.item_type,
            )
            strings.write_byte(b, '[')
            if length, has_length := tv.length.(u32); has_length {
                strings.write_uint(b, uint(length))
            }
            strings.write_byte(b, ']')
        case nil:
            panic("Unreachable")
        }
    }
}

pop_scope :: proc(s: ^CheckerState, loc := #caller_location) {
    utils.call(loc, "pop_scope", "")
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
    range: utils.Range,
    description: string,
    type_unsimplified: Type,
) -> (
    ArrayType,
    bool,
) {
    type := simplify_type(s, type_unsimplified)
    if out, is_array := type.key.(ArrayType); is_array {
        return out, true
    }
    utils.diagnostic(
        s.r,
        range,
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
        utils.diagnostic(
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
        key_value := check_runtime_value(s, key^, body, String, generic_args)
        if key_value == nil {
            return var_type_value.value_type, nil
        }
        key_variable: CheckedValue = add_unnamed_variable(s, String, false)
        append_elem(body, CheckedMutation{key_variable, key_value})
        return var_type_value.value_type, CheckedOrderedHashMapAccess{new_clone(CheckedValue(var_ref)), new_clone(key_variable)}

    }
    utils.diagnostic(s, key.pos, "Cannot use a key with the type `%s`", type_to_string(s, var_type))
    return Invalid, nil
}
*/

check_mutation :: proc(
    s: ^CheckerState,
    split: SuccessfulSplitFirst,
    // unit_being_mutated: UnitWithPos,
    // new_value_unit: Unit,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
    loc := #caller_location,
) -> bool {
    utils.call(loc, "check_mutation", "")
    ident, is_ident := split.before_split.contents.(IdentNode)
    if !is_ident {
        utils.diagnostic(
            s.r,
            split.before_split.range,
            "Expected an identifier for the unit being mutated",
        )
        return false
    }
    if ident.has_re_before && !ident.ident.has_dollar_at_end {
        utils.diagnostic(
            s.r,
            split.before_split.range,
            "The name of a reassignable variable must have a `$` postfix",
        )
        return false
    }
    if !ident.has_re_before && ident.ident.has_dollar_at_end {
        var_ref, ok := s.variables_map[ident.ident.ident]
        if !ok {
            utils.diagnostic(
                s.r,
                split.before_split.range,
                "The variable `%s` is not defined",
                ident.ident.ident,
            )
            return false
        }
        var := s.scopes[var_ref.nesting_level].variables[var_ref.index]
        if !var.is_reassignable {
            utils.diagnostic(
                s.r,
                split.before_split.range,
                "The variable `%s` is not reassignable",
                ident.ident.ident,
            )
            return false
        }

        alteration := check_derivation_alteration(
            s,
            split.split_method,
            split.split_method_range,
            split.after_split,
            var.type,
            body,
            generic_args,
        )
        if alteration.arg == nil {
            return false
        }

        utils.debug_dynamic_array_append(
            body,
            CheckedAssignment {
                var_ref,
                CheckedDerivation {
                    new_clone(CheckedValue(var_ref)),
                    DerivationSubset{},
                    alteration,
                },
            },
        )
        return true
    }

    if split.split_method != .Assign {
        utils.diagnostic(
            s.r,
            split.split_method_range,
            "For variable declaration: First join method must be `=`",
        )
        return false
    }

    new_value := check_value(s, split.after_split, CheckValueArgs{body, generic_args, nil}).v
    if new_value.value == nil {
        return false
    }

    variable, variable_ok := add_variable(s, new_value.type, ident.ident)
    if !variable_ok {
        return false
    }

    utils.debug_dynamic_array_append(body, CheckedAssignment{variable, new_value.value})
    return true
}

SuccessfulSplitFirst :: struct {
    before_split:       UnitSegment,
    split_method:       UnitJoinMethod,
    split_method_range: utils.Range,
    after_split:        Unit,
}

try_split_first_by :: proc(
    u: Unit,
    possible_splits: bit_set[UnitJoinMethod],
) -> Maybe(SuccessfulSplitFirst) {
    if len(u.rest) < 2 {
        return nil
    }
    join_method, is_join_method := u.rest[0].contents.(UnitJoinMethod)
    if !is_join_method || join_method not_in possible_splits {
        return nil
    }
    return SuccessfulSplitFirst{u.first, join_method, u.rest[0].range, Unit{u.rest[1], u.rest[2:]}}
}

SuccessfulSplit :: struct {
    before_split:       Unit,
    split_method:       UnitJoinMethod,
    split_method_range: utils.Range,
    after_split:        Unit,
}

// Returns `nil` on failure
try_split_by :: proc(u: Unit, possible_splits: bit_set[UnitJoinMethod]) -> Maybe(SuccessfulSplit) {
    // Start from the end for correct order of operations
    for i := len(u.rest) - 2; i >= 0; i -= 1 {
        join_method, is_join_method := u.rest[i].contents.(UnitJoinMethod)
        if is_join_method && join_method in possible_splits {
            return SuccessfulSplit {
                Unit{u.first, u.rest[:i]},
                join_method,
                u.rest[i].range,
                Unit{u.rest[i + 1], u.rest[i + 2:]},
            }
        }
    }
    return nil
}

GetTagResult :: struct {
    tag_name: TextAndPos,
    payload:  Maybe(Unit),
}

get_tag :: proc(r: utils.DiagnosticReporter, u: Unit) -> Maybe(GetTagResult) {
    #partial switch first in u.first.contents {
    case UnitJoinMethod:
        if first == .Colon && len(u.rest) == 1 {
            ident, is_ident := u.rest[0].contents.(IdentNode)
            if is_ident && !ident.has_re_before {
                return GetTagResult{TextAndPos{ident.ident.ident, ident.ident.pos}, nil}
            }
        }
    case IdentNode:
        if first.has_re_before == false && len(u.rest) >= 2 {
            join_method, is_join_method := u.rest[0].contents.(UnitJoinMethod)
            if is_join_method && join_method == .Colon {
                return GetTagResult {
                    TextAndPos{first.ident.ident, first.ident.pos},
                    Unit{u.rest[1], u.rest[2:]},
                }
            }
        }
    }
    utils.diagnostic(
        r,
        get_range(u),
        "Expected a tag like `:TagName` or `TagName: var_name` to create a sum type variant",
    )
    return nil
}

// The boolean returned is whether the block checked successfully
check_block :: proc(
    s: ^CheckerState,
    block: []Statement,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
    loc := #caller_location,
) -> (
    []Type,
    utils.DebugValue(bool),
) {
    utils.call(loc, "check_block", "")
    for stmt, stmt_index in block {
        switch value in stmt {

        /*
        case VariableManagement:
            value_type := Unknown
            checked_value := check_runtime_value(
                s,
                value.value,
                body,
                AnyType{&value_type},
                generic_args,
            )
            if len(value.destination) != 1 {
                utils.diagnostic(
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
            if len(value.rest) == 0 {
                utils.diagnostic(
                    s.r,
                    get_range(value),
                    "Must have atleast 2 unit segments in a statement",
                )
                return nil, utils.to_debug_value(false)
            }
            last_segment := value.rest[len(value.rest) - 1]
            if split, split_ok := try_split_first_by(
                   value,
                   alteration_methods,
               ).(SuccessfulSplitFirst); split_ok {
                /*
                if value.extra_units[0].join_method != .Assign {
                    utils.diagnostic(
                        s,
                        value.extra_units[0].join_method_pos,
                        "First join method must be `=`",
                    )
                    return nil, false
                }
                    */
                ok := check_mutation(
                    s,
                    split,
                    /*
                    UnitWithPos{value.first_unit, value.pos},
                    Unit {
                        value.extra_units[0].unit.pos,
                        value.extra_units[0].unit.unit,
                        value.extra_units[1:],
                    },
                    */
                    body,
                    generic_args,
                )
                if !ok {
                    return nil, utils.to_debug_value(false)
                }
            } else if args, args_ok := last_segment.contents.(Tuple); args_ok {
                unit_being_called := Unit{value.first, value.rest[:len(value.rest) - 1]}
                value_being_called := check_value(
                    s,
                    unit_being_called,
                    CheckValueArgs{body, generic_args, nil},
                )
                if value_being_called.v.value == nil {
                    return nil, utils.to_debug_value(false)
                }
                call, call_ok := check_function_call(
                    s,
                    value_being_called.v,
                    get_range(unit_being_called),
                    args.elements,
                    last_segment.range,
                    body,
                    generic_args,
                ).(CheckedFuncCall)
                if !call_ok {
                    return nil, utils.to_debug_value(false)
                }
                if len(call.return_types) != 0 {
                    utils.diagnostic(
                        s.r,
                        get_range(unit_being_called),
                        return_type_count_mismatch,
                        0,
                        len(call.return_types),
                    )
                    return nil, utils.to_debug_value(false)
                }
                utils.debug_dynamic_array_append(body, call.value)
            } else {
                utils.diagnostic(s.r, get_range(value), "Cannot use this unit as a statement")
                return nil, utils.to_debug_value(false)
            }

        case ConditionControlledLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            s.parent_loop_index = loop_index
            s.loop_index += 1
            condition := check_value_of_type(
                s,
                value.condition,
                CheckValueArgs{body, generic_args, nil},
                .Bool,
            )


            loop_body_array := utils.to_debug_value([dynamic]CheckedStatement{})
            exit_loop := make([]CheckedStatement, 1)
            exit_loop[0] = CheckedLoopControlFlow{loop_index, .Break}
            condition_check := CheckedIf{condition, CheckedBlock{}, CheckedBlock{nil, exit_loop}}
            if value.type == .WhileLoop {
                utils.debug_dynamic_array_append(&loop_body_array, condition_check)
            }

            loop_variables, loop_body_ok := check_block(
                s,
                value.body,
                &loop_body_array,
                generic_args,
            )
            if !runtime_value_ok(s, get_range(value.condition), condition) || !loop_body_ok.v {
                return nil, utils.to_debug_value(false)
            }

            if value.type == .DoWhileLoop {
                utils.debug_dynamic_array_append(&loop_body_array, condition_check)
            }

            utils.debug_dynamic_array_append(
                body,
                CheckedLoop{loop_index, loop_variables, nil, nil, utils.slice(loop_body_array)},
            )

        case ForInLoop:
            append_elem(&s.scopes, Scope{})
            defer pop_scope(s)
            old_parent_loop_index := s.parent_loop_index
            defer s.parent_loop_index = old_parent_loop_index
            loop_index := s.loop_index
            if value.label.text != "" {
                if value.label.text in s.labels_map {
                    utils.diagnostic(
                        s.r,
                        get_range(value.label),
                        "The label `%s` is already defined",
                        value.label.text,
                    )
                    return nil, utils.to_debug_value(false)
                }
                s.labels_map[value.label.text] = LabelRef{len(s.scopes) - 1, loop_index}
            }
            s.parent_loop_index = loop_index
            s.loop_index += 1
            loop_body_array := utils.to_debug_value([dynamic]CheckedStatement{})
            outer: switch iter in value.iterator {
            case Unit:
                v := check_value(s, iter, CheckValueArgs{body, generic_args, nil}).v
                if !runtime_value_ok(s, get_range(iter), v.value) {
                    return nil, utils.to_debug_value(false)
                }
                #partial switch t in simplify_type(s, v.type).key {
                case ArrayType:
                    array_item_type := t.item_type
                    if value.variables[2].text != "" {
                        utils.diagnostic(
                            s.r,
                            get_range(value.variables[2]),
                            "You can only capture at most 2 variables from iterating over an array",
                        )
                        return nil, utils.to_debug_value(false)
                    }
                    elem_ref, elem_ok := add_variable(
                        s,
                        array_item_type,
                        IdentAndPos{value.variables[0].text, false, value.variables[0].pos},
                    )
                    index_ref, index_ok := add_variable(
                        s,
                        .UInt,
                        IdentAndPos{value.variables[1].text, false, value.variables[1].pos},
                    )
                    if !elem_ok || !index_ok {
                        return nil, utils.to_debug_value(false)
                    }
                    loop_variables, loop_body_ok := check_block(
                        s,
                        value.body,
                        &loop_body_array,
                        generic_args,
                    )
                    if !loop_body_ok.v {
                        return nil, utils.to_debug_value(false)
                    }
                    utils.debug_dynamic_array_append(
                        body,
                        iterate_array(
                            loop_index,
                            index_ref,
                            elem_ref,
                            &utils.DoubleDynamic(CheckedStatement){loop_body_array.v, 0},
                            loop_variables,
                            v.value,
                            t,
                        ),
                    )
                    break outer
                case OrderedHashMapType:
                    key, key_ok := add_variable(
                        s,
                        Type(t.key_type),
                        IdentAndPos{value.variables[0].text, false, value.variables[0].pos},
                    )
                    value_var, value_var_ok := add_variable(
                        s,
                        t.value_type,
                        IdentAndPos{value.variables[1].text, false, value.variables[1].pos},
                    )
                    index, index_ok := add_variable(
                        s,
                        .UInt,
                        IdentAndPos{value.variables[2].text, false, value.variables[2].pos},
                    )
                    if !key_ok || !value_var_ok || !index_ok {
                        return nil, utils.to_debug_value(false)
                    }
                    loop_variables, loop_body_ok := check_block(
                        s,
                        value.body,
                        &loop_body_array,
                        generic_args,
                    )
                    if !loop_body_ok.v {
                        return nil, utils.to_debug_value(false)
                    }
                    utils.debug_dynamic_array_append(
                        body,
                        iterate_ordered_hash_map(
                            loop_index,
                            v.value,
                            index,
                            key,
                            value_var,
                            &utils.DoubleDynamic(CheckedStatement){loop_body_array.v, 0},
                            loop_variables,
                        ),
                    )
                    break outer
                }
                utils.diagnostic(
                    s.r,
                    get_range(iter),
                    "Expected an array or an `OrderedHashMap`, got the type `%s`",
                    type_to_string(s, v.type),
                )

            case NumericIterator:
                if value.variables[1].text != "" {
                    utils.diagnostic(
                        s.r,
                        get_range(value.variables[1]),
                        "You can only capture at most one variable in a numeric iterator",
                    )
                    return nil, utils.to_debug_value(false)
                }
                assert(value.variables[2].text == "")
                index_variable, var_ok := add_variable(
                s,
                .Int, // TODO: Support types other than Int
                IdentAndPos{value.variables[0].text, false, value.variables[0].pos},
                )
                expected_type: Type = .Int
                start := check_value_of_type(
                    s,
                    iter.start,
                    CheckValueArgs{&loop_body_array, generic_args, nil},
                    expected_type,
                )
                end := check_value_of_type(
                    s,
                    iter.end,
                    CheckValueArgs{&loop_body_array, generic_args, nil},
                    expected_type,
                )
                step: CheckedValue = ---
                if iter.step == nil {
                    step = CompileTimeValue(
                        utils.NumberValue{false, utils.big_uint_from_u64(1), ""},
                    )
                } else {
                    step = check_value_of_type(
                        s,
                        iter.step^,
                        CheckValueArgs{&loop_body_array, generic_args, nil},
                        expected_type,
                    )
                    if !runtime_value_ok(s, get_range(iter.step^), step) {
                        return nil, utils.to_debug_value(false)
                    }
                }
                if !var_ok ||
                   !runtime_value_ok(s, get_range(iter.start), start) ||
                   !runtime_value_ok(s, get_range(iter.end), end) ||
                   step == nil {
                    return nil, utils.to_debug_value(false)
                }
                loop_variables, loop_body_ok := check_block(
                    s,
                    value.body,
                    &loop_body_array,
                    generic_args,
                )
                if !loop_body_ok.v {
                    return nil, utils.to_debug_value(false)
                }
                utils.debug_dynamic_array_append(
                    body,
                    iterate_start_end_step(
                        loop_index,
                        index_variable,
                        iter.type,
                        start,
                        end,
                        step,
                        &utils.DoubleDynamic(CheckedStatement){loop_body_array.v, 0},
                        loop_variables,
                    ),
                )
            }

        case IfElseStatement:
            expected_type: Type = .Bool
            condition := check_value_of_type(
                s,
                value.condition,
                CheckValueArgs{body, generic_args, nil},
                expected_type,
            )

            append_elem(&s.scopes, Scope{})
            if_block_array := utils.to_debug_value([dynamic]CheckedStatement{})
            if_variables, if_block_ok := check_block(
                s,
                value.if_block,
                &if_block_array,
                generic_args,
            )
            if_block := CheckedBlock{if_variables, if_block_array.v[:]}
            pop_scope(s)

            append_elem(&s.scopes, Scope{})
            else_block_array := utils.to_debug_value([dynamic]CheckedStatement{})
            else_variables, else_block_ok := check_block(
                s,
                value.else_block,
                &else_block_array,
                generic_args,
            )
            else_block := CheckedBlock{else_variables, else_block_array.v[:]}
            pop_scope(s)

            if !runtime_value_ok(s, get_range(value.condition), condition) ||
               !if_block_ok.v ||
               !else_block_ok.v {
                return nil, utils.to_debug_value(false)
            }
            utils.debug_dynamic_array_append(body, CheckedIf{condition, if_block, else_block})

        case LoopControlFlow:
            if stmt_index + 1 != len(block) {
                utils.diagnostic(
                    s.r,
                    value.range,
                    "Loop control flow statement must be last statement in block",
                )
                return nil, utils.to_debug_value(false)
            }
            if s.parent_loop_index == max(uint) {
                utils.diagnostic(
                    s.r,
                    value.range,
                    "Loop control flow statement must go inside a loop",
                )
                return nil, utils.to_debug_value(false)
            }
            if value.label.text == "" {
                utils.debug_dynamic_array_append(
                    body,
                    CheckedLoopControlFlow{s.parent_loop_index, value.kind},
                )
            } else {
                loop_ref, ok := s.labels_map[value.label.text]
                if !ok {
                    utils.diagnostic(
                        s.r,
                        get_range(value.label),
                        "There is no parent loop labelled with `%s`",
                        value.label.text,
                    )
                    return nil, utils.to_debug_value(false)
                }
                utils.debug_dynamic_array_append(
                    body,
                    CheckedLoopControlFlow{loop_ref.loop_index, value.kind},
                )
            }

        case UnreachableStatement:
            if stmt_index + 1 != len(block) {
                utils.diagnostic(
                    s.r,
                    value.range,
                    "Unreachable statement must be last statement in block",
                )
                return nil, utils.to_debug_value(false)
            }
            utils.debug_dynamic_array_append(body, UnreachableStatement{})

        case ReturnStatement:
            if stmt_index + 1 != len(block) {
                utils.diagnostic(
                    s.r,
                    value.range,
                    "Return statement must be last statement in block",
                )
                return nil, utils.to_debug_value(false)
            }
            if len(value.args) != len(s.return_types) {
                utils.diagnostic(
                    s.r,
                    value.range,
                    "Function returns %d values, but %d values given",
                    len(s.return_types),
                    len(value.args),
                )
                return nil, utils.to_debug_value(false)
            }
            switch len(value.args) {
            case 0:
                utils.debug_dynamic_array_append(body, CheckedReturn{nil})
            case 1:
                checked := check_value_of_type(
                    s,
                    value.args[0],
                    CheckValueArgs{body, generic_args, nil},
                    s.return_types[0],
                )
                if !runtime_value_ok(s, get_range(value.args[0]), checked) {
                    return nil, utils.to_debug_value(false)
                }
                utils.debug_dynamic_array_append(body, CheckedReturn{checked})
            case:
                utils.diagnostic(
                    s.r,
                    value.range,
                    "Can only have <=1 value in return statement (TODO: add support for returning >1 values)",
                )
                return nil, utils.to_debug_value(false)
            }

        case YieldStatement:
            utils.diagnostic(s.r, value.range, "TODO: Handle yield statement")
            return nil, utils.to_debug_value(false)

        case MatchStatement:
            res := check_value(s, value.value, CheckValueArgs{body, generic_args, nil}).v
            if !runtime_value_ok(s, get_range(value.value), res.value) {
                return nil, utils.to_debug_value(false)
            }

            val_sum_type, _, val_sum_type_ok := get_sum_type(s, get_range(value.value), res.type)
            if !val_sum_type_ok {
                return nil, utils.to_debug_value(false)
            }

            variable_ref := add_unnamed_variable(s, res.type, false)
            utils.debug_dynamic_array_append(body, CheckedAssignment{variable_ref, res.value})

            branches := make(map[u32]CheckedMatchBranch)
            for branch in value.branches {
                append_elem(&s.scopes, Scope{})
                defer pop_scope(s)

                tag, tag_ok := get_tag(s.r, branch.label).(GetTagResult)
                if !tag_ok {
                    return nil, utils.to_debug_value(false)
                }

                variant := utils.lookup(
                    s.types.sum_type_tags,
                    tag.tag_name.text,
                    utils.string_to_index_procs,
                )
                if variant == utils.does_not_exist || variant.index not_in val_sum_type.payloads {
                    utils.diagnostic(
                        s.r,
                        get_range(tag.tag_name),
                        "The sum type `%s` does not have the variant `%s`",
                        type_to_string(s, res.type),
                        tag.tag_name.text,
                    )
                    return nil, utils.to_debug_value(false)
                }

                if variant.index in branches {
                    utils.diagnostic(
                        s.r,
                        get_range(tag.tag_name),
                        "The variant `%s` already has a branch defined at %v",
                        tag.tag_name.text,
                        branches[variant.index].label_range,
                    )
                    return nil, utils.to_debug_value(false)
                }

                var: Maybe(VariableRef) = nil
                if payload, has_payload := tag.payload.(Unit); has_payload {
                    sum_type_payload, sum_type_has_payload := val_sum_type.payloads[variant.index].(Type)
                    if !sum_type_has_payload {
                        utils.diagnostic(
                            s.r,
                            get_range(payload),
                            "Cannot have variable for sum type variant with no payload",
                        )
                        return nil, utils.to_debug_value(false)
                    }
                    var_name, var_ok := get_text_and_pos_from_unit(s.r, payload).(TextAndPos)
                    if !var_ok {
                        return nil, utils.to_debug_value(false)
                    }
                    var, var_ok = add_variable(
                        s,
                        sum_type_payload,
                        IdentAndPos{var_name.text, false, var_name.pos},
                    )
                    if !var_ok {
                        return nil, utils.to_debug_value(false)
                    }
                }

                body := utils.to_debug_value([dynamic]CheckedStatement{})
                variables, block_ok := check_block(s, branch.body, &body, generic_args)
                if !block_ok.v {
                    return nil, utils.to_debug_value(false)
                }

                branches[variant.index] = CheckedMatchBranch {
                    get_range(branch.label),
                    CheckedBlock{variables, body.v[:]},
                    var,
                }
            }

            if len(branches) < len(val_sum_type.payloads) {
                for tag_variant_index in val_sum_type.payloads {
                    if tag_variant_index not_in branches {
                        utils.diagnostic(
                            s.r,
                            get_range(value.value),
                            "Unhandled variant `%s`",
                            s.types.sum_type_tags.keys[tag_variant_index].key,
                        )
                    }
                }
                return nil, utils.to_debug_value(false)
            }
            utils.debug_dynamic_array_append(body, CheckedMatch{variable_ref, branches})

        }

        utils.debug("length of body is %d", len(body.v))
    }
    variables := s.scopes[len(s.scopes) - 1].variables
    return variables.type[:len(variables)], utils.to_debug_value(true)
}

value_err1 :: "Compiler cannot generate a `.` function without knowing the return type of the function"

check_namespaced_var_ref :: proc(
    s: ^CheckerState,
    namespace: ^utils.CompilerFile,
    ident: IdentAndPos,
) -> CheckValueResult {
    namespace_index := get_file_index(s.files, namespace)
    file_globals := s.parsed_files.d[namespace_index]
    parsed_global, global_exists := file_globals[ident.ident]
    if !global_exists {
        utils.diagnostic(
            s.r,
            get_range(ident),
            "The variable `%s` is not defined in the file `%s`",
            ident.ident,
            s.files[namespace_index].file_path,
        )
        return CheckValueResult{nil, .Invalid}
    }
    if parsed_global.has_generics {
        return CheckValueResult {
            CompileTimeValue(GlobalValueWithGenericRef{parsed_global.index}),
            .Unknown,
        }
    } else {
        global_value := check_global_value_without_generic(
            s,
            GlobalValueWithoutGenericRef{uint(parsed_global.index)},
        )
        if global_value.type == .Invalid {
            assert(global_value.value == nil)
            return CheckValueResult{nil, .Invalid}
        }
        // if global_value.type == imported_file_type && index + 1 < len(ref.segments) {
        // return check_namespaced_var_ref(s, global_value.value.(Import).file, ref, index + 1)
        // }
        return CheckValueResult{global_value.value, global_value.type}
        // switch value in global.value {
        // case:
        //     panic("Unreachable")
        // case nil:
        //     utils.diagnostic(
        //         s,
        //         ref[index].pos,
        //         "Either this global has not been defined yet, there was an error checking this global, or this type of global is not yet supported (TODO)",
        //     )
        //     return nil, Invalid, 0
        // case CheckerGlobalValueWithoutGeneric:
        //     return value.inline_value, value.type, index + 1
        // case Import:
        //     if index + 1 >= len(ref) {
        //         utils.diagnostic(s, ref[index].pos, import_use_err)
        //         return nil, Invalid, 0
        //     }
        //     return check_namespaced_var_ref(s, value.file, ref, index + 1)
        // }
        // initialised := initialise_global_type_without_generic(s, global_value.index)
        // if initialised == Invalid {
        //     return nil, Invalid, 0
        // }
        // return CompileTimeValue(initialised), Type, index + 1
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
            utils.diagnostic(
                s,
                ref[index].pos,
                "Either this global has not been defined yet, there was an error checking this global, or this type of global is not yet supported (TODO)",
            )
            return nil, Invalid, 0
        case CheckedGlobalRuntimeValue:
            return value.inline_value, value.type, index + 1
        case Import:
            if index + 1 >= len(ref) {
                utils.diagnostic(s, ref[index].pos, import_use_err)
                return nil, Invalid, 0
            }
            return check_namespaced_var_ref(s, value.file, ref, index + 1)
        }
    case GlobalTypeWithGenericRef:
        return CompileTimeValue(global_value), Unknown, index + 1
    case GlobalTypeWithoutGenericRef:
        initialised := initialise_global_type_without_generic(s, global_value.index)
        if initialised == Invalid {
            return nil, Invalid, 0
        }
        return CompileTimeValue(initialised), Type, index + 1
        */
    }
}

// Returns `nil, Invalid, 0` if there was an error in the ref start
check_var_ref_start :: proc(
    s: ^CheckerState,
    ident: IdentAndPos,
    generic_args: map[string]Type,
) -> CheckValueResult {
    if ident.ident in generic_args {
        return CheckValueResult{CompileTimeValue(generic_args[ident.ident]), .Type}
    }
    if builtin := get_builtin(ident.ident); builtin.value != nil {
        return CheckValueResult{builtin.value, builtin.type}
    }
    /*
    if ref.segments[0].ident == "compiler" {
        compiler_funcs :: "`compiler.emit_js_code`"
        if len(ref.segments) == 1 {
            utils.diagnostic(s, pos, "Expected " + compiler_funcs + " got just `compiler`")
            return nil, Invalid, 0
        }
        switch ref.segments[1].ident {
        case "emit_js_code":
            return .emit_js_code, string_any_ordered_hashmap_and_string_to_String, 2
        case:
            utils.diagnostic(s, pos, "Expected " + compiler_funcs + " got `compiler.%s`", ref.segments[1].ident)
            return nil, Invalid, 0
        }
    }
    */
    if var_ref, ok := s.variables_map[ident.ident]; ok {
        return CheckValueResult{var_ref, get_variable_type(s, var_ref)}
    }
    return check_namespaced_var_ref(s, ident.pos.file, ident)
}

/*
    // OLD
    if len(segments) == 2 && segments[0].ident == "" {
        expected_return_type: Type = ---
        switch expected in a.type {
        case AnyType:
            utils.diagnostic(s.r, pos, value_err1)
            return nil
        case Type:
            utils.diagnostic(s.r, pos, "TODO: Generate `.` functions better")
            return nil
        case FunctionWithExpectedReturnTypes:
            if len(expected.expected_return_types) != 1 {
                utils.diagnostic(
                    s.r,
                    pos,
                    "Compiler cannot generate a `.` function which generates %d return types",
                    len(expected.expected_return_types),
                )
                return nil
            }
            switch expected_return in expected.expected_return_types[0] {
            case AnyType, FunctionWithExpectedReturnTypes:
                utils.diagnostic(s.r, pos, value_err1)
                return nil
            case Type:
                expected_return_type = expected_return
            }
        }

        sum_type_value, sum_type, sum_type_ok := get_sum_type(s, pos, expected_return_type)
        if !sum_type_ok {
            return nil
        }

        variant := utils.lookup(sum_type_value.m, segments[1].ident, utils.string_to_index_procs)
        if variant == utils.does_not_exist {
            utils.diagnostic(
                s.r,
                pos,
                "The sum type `%s` does not have a variant called `%s`",
                type_to_string(s, expected_return_type),
                segments[1].ident,
            )
            return nil
        }
        return_type := sum_type_value.payloads.d[variant.index]
        got := get_type(s.types, return_type)
        // TODO: Use `StructTypeInitFunc` instead of `SumTypeInitFunc` if `type` is the struct type rather than the sum type
        return finish_checking_value(
            s,
            pos,
            a.type,
            SumTypeInitFunc{sum_type, variant.index},
            get_func_type_from_struct_type(s, got.key.(StructType), return_type),
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
            utils.debug("expected_type is %#v", expected_type)
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
*/

check_var_ref :: proc(
    s: ^CheckerState,
    value_range: utils.Range,
    value: CheckValueResult,
    extra_segment: IdentAndPos,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckValueResult {
    utils.call(loc, "check_var_ref", "")
    utils.print_arg("extra_segment", extra_segment.has_dollar_at_end)
    utils.print_arg("extra_segment", extra_segment.ident)
    utils.print_arg("extra_segment", extra_segment.pos)
    utils.print_arg("a", a)

    if extra_segment.ident == "len" {
        simplified := simplify_type(s, value.type)
        if simplified.type == .String {
            return CheckValueResult{LengthOfString{new_clone(value.value)}, .UInt}
        }
        #partial switch type in simplified.key {
        case ArrayType:
            return CheckValueResult{length_of_array(type, value.value), .UInt}
        case OrderedHashMapType:
            return CheckValueResult{LengthOfOrderedHashMap{new_clone(value.value)}, .UInt}
        }
        utils.diagnostic(
            s.r,
            value_range,
            "This value is of type `%s`\nCan only use `.len` for a value which is a string, an array, or an OrderedHashSet",
            type_to_string(s, value.type),
        )
        return CheckValueResult{nil, .Invalid}
    } else if extra_segment.ident == "to_str" {
        converted := to_str(s, value_range, value.value, value.type)
        if converted == nil {
            return CheckValueResult{nil, .Invalid}
        }
        return CheckValueResult{converted, .String}
    } else if value.type == .ImportedFile {
        return check_namespaced_var_ref(
            s,
            value.value.(CompileTimeValue).(Import).file,
            extra_segment,
        )
    }
    struct_type, ok := get_struct_type(s, value.type)
    if ok {
        field := utils.lookup(struct_type.m, extra_segment.ident, utils.string_to_index_procs)
        if field != utils.does_not_exist {
            return CheckValueResult {
                create_field_access(value.value, field.index),
                struct_type.types.d[field.index],
            }
        }
    }
    utils.diagnostic(
        s.r,
        value_range,
        "This value (of type `%s`) does not have a `.%s` field",
        type_to_string(s, value.type),
        extra_segment.ident,
    )
    return CheckValueResult{nil, .Invalid}
}

check_array_initialisation :: proc(
    s: ^CheckerState,
    elements: []Unit,
    a: CheckValueArgs,
) -> CheckValueResult {
    ok := true
    has_non_compiletime_value := false
    types := make(map[Type]struct{})
    values := make([]CheckedValue, len(elements))
    for elem, i in elements {
        checked := check_value(s, elem, CheckValueArgs{a.body, a.generic_args, nil})
        if checked.v.value == nil {
            ok = false
        }
        _, is_comptime := checked.v.value.(CompileTimeValue)
        if !is_comptime {
            has_non_compiletime_value = true
        }
        values[i] = checked.v.value
        types[checked.v.type] = struct{}{}
    }
    if !ok {
        return CheckValueResult{nil, .Invalid}
    }
    assert(Type.Invalid not_in types)
    elem_type := Type.Any
    if len(types) != 0 {
        elem_type = find_most_specific_supertype(s, &types)
    }
    array_type := create_type(&s.types, ArrayType{u32(len(elements)), elem_type}).type
    if has_non_compiletime_value {
        segments := make([]ArraySegment, len(elements))
        for v, i in values {
            segments[i] = SingleElemSegment{v}
        }
        return CheckValueResult{ArrayLiteral{array_type, segments}, array_type}
    } else {
        comptime_elems := make([]CompileTimeValue, len(elements))
        for v, i in values {
            comptime_elems[i] = v.(CompileTimeValue)
        }
        return CheckValueResult {
            CompileTimeValue(CompileTimeArray{array_type, comptime_elems}),
            array_type,
        }
    }
}

/*
// OLD (creating arrays like []ItemType(elems...))
check_array_initialisation :: proc(
    s: ^CheckerState,
    pos: utils.Pos,
    array_type_node: CallWithFrontedSquareBrackets,
    array_type_pos: utils.Pos,
    args: []Unit,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckValueResult {
    utils.call(loc, "check_array_initialisation", "")
    array_type_value, ok := check_array_type(s, array_type_pos, array_type_node, a.generic_args)
    if !ok {
        return CheckValueResult{nil, .Invalid}
    }
    array_type := create_type(&s.types, array_type_value).type
    if array_type_value.length != 0 && len(args) != int(array_type_value.length) {
        utils.diagnostic(
            s.r,
            pos,
            "Type initialisation provides %d values\nType expects %d values",
            len(args),
            array_type_value.length,
        )
        return CheckValueResult{nil, .Invalid}
    }
    compile_time_elems := make([dynamic]CompileTimeValue)
    for i := 0; i < len(args); i += 1 {
        value := check_value_of_type(
            s,
            args[i],
            CheckValueArgs{a.body, a.generic_args, nil},
            array_type_value.item_type,
        )
        if !runtime_value_ok(s, args[i].pos, value) {
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
                value = check_value_of_type(
                    s,
                    args[i],
                    CheckValueArgs{a.body, a.generic_args, nil},
                    array_type_value.item_type,
                )
                if !runtime_value_ok(s, args[i].pos, value) {
                    ok = false
                } else {
                    array_segments[i] = SingleElemSegment{value}
                }
            }
            if !ok {
                return CheckValueResult{nil, .Invalid}
            }
            return CheckValueResult{ArrayLiteral{array_type, array_segments}, array_type}
        }
    }
    if !ok {
        return CheckValueResult{nil, .Invalid}
    }
    return CheckValueResult {
        CompileTimeValue(CompileTimeArray{array_type, compile_time_elems[:]}),
        array_type,
    }
}
*/

CheckedFuncCall :: struct {
    value:        CheckedFunctionCall,
    return_types: []Type,
}

// Returns `nil` on failure
check_function_call :: proc(
    s: ^CheckerState,
    value_being_called: CheckValueResult,
    value_being_called_range: utils.Range,
    args: []Unit,
    args_range: utils.Range,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
    loc := #caller_location,
) -> Maybe(CheckedFuncCall) {
    utils.call(loc, "check_function_call", "")
    func, is_func := get_func_type(
        s,
        value_being_called_range,
        value_being_called.value,
        value_being_called.type,
    ).(FuncType)
    if !is_func {
        return nil
    }
    if !runtime_value_ok(s, value_being_called_range, value_being_called.value) {
        return nil
    }

    if len(args) != len(func.args) {
        argument_count_mismatch(s, value_being_called_range, len(args), len(func.args))
        return nil
    }

    checked_args := make([]CheckedValue, len(args))
    for arg, i in args {
        arg_value := check_value_of_type(
            s,
            arg,
            CheckValueArgs{body, generic_args, nil},
            func.args[i],
        )
        if !runtime_value_ok(s, get_range(arg), arg_value) {
            return nil
        }
        checked_args[i] = arg_value
    }

    return CheckedFuncCall {
        CheckedFunctionCall{new_clone(value_being_called.value), checked_args},
        func.return_types,
    }
}

/*
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
*/

check_value_with_marker :: proc(
    s: ^CheckerState,
    marker: TextAndPos,
    v: Unit,
    i: ^uint,
    a: CheckValueArgs,
) -> CheckValueResult {
    switch marker.text {
    case "load":
        value := check_initial_value(s, v, i, CheckValueArgs{a.body, a.generic_args, nil}).v
        if value.value == nil {
            return CheckValueResult{nil, .Invalid}
        }
        if !expect_type(s, get_segment(v, i^).range, .String, value.type) {
            return CheckValueResult{nil, .Invalid}
        }
        comptime_value, is_comptime := value.value.(CompileTimeValue)
        if !is_comptime {
            utils.diagnostic(s.r, get_segment(v, i^).range, "Expected a compile time known value")
            return CheckValueResult{nil, .Invalid}
        }

        joined, join_err := filepath.join(
            []string{v.first.range.file.dir_path, string(comptime_value.(StringLiteralValue))},
            context.allocator,
        )
        if join_err != nil {
            utils.diagnostic(s.r, get_range(marker), "Failed to join strings: %v", join_err)
            return CheckValueResult{nil, .Invalid}
        }
        data, data_err := os.read_entire_file(joined, context.allocator)
        if data_err != nil {
            utils.diagnostic(
                s.r,
                get_range(marker),
                "Failed to read `%s`: %#v\n",
                joined,
                data_err,
            )
            return CheckValueResult{nil, .Invalid}
        }
        return CheckValueResult{CompileTimeValue(StringLiteralValue(data)), .String}
    case "debug_ast":
        // debug_unit(nil, v)
        utils.debug("TODO: Handle debug_ast")
    case:
        utils.diagnostic(
            s.r,
            get_range(marker),
            "TODO: Handle the `%s` marker",
            marker.text,
            type = .Warning,
        )
    }

    return check_initial_value(s, v, i, a).v
}

// For `check_value` and `check_joined_unit_value`:
// - Returns `nil` if there are errors in the value
// - The `body` arg may be appended to with statements that should be executed
//   before the value is accessed

check_joined_unit_value :: proc(
    s: ^CheckerState,
    join_method: UnitJoinMethod,
    join_method_range: utils.Range,
    before: Unit,
    after: Unit,
    a: CheckValueArgs,
    loc := #caller_location,
) -> CheckValueResult {
    when ODIN_DEBUG {
        utils.call(loc, "check_joined_unit_value", "")
    }
    // TODO: In lots of this code, `check_runtime_value` is used when the
    // operations should be performable on values that can only be used at
    // compile time, like a value of the type `Type`
    array_err :: "Expected an array type\nGot the type `%s`"
    switch join_method {

    case .Assign, .Tilde, .Colon, .PipeEquals, .Dot:
        utils.panicf("Unreachable (join method is %v)", join_method)

    case:
        utils.panicf("Unreachable (join method is %v)", join_method)

    case .In:
        val0 := check_value(s, before, CheckValueArgs{a.body, a.generic_args, nil}).v
        val1 := check_value(s, after, CheckValueArgs{a.body, a.generic_args, nil}).v
        if !runtime_value_ok(s, get_range(before), val0.value) ||
           !runtime_value_ok(s, get_range(after), val1.value) {
            return CheckValueResult{nil, .Invalid}
        }
        hash_map_type, is_hash_map_type := simplify_type(s, val1.type).key.(OrderedHashMapType)
        if !is_hash_map_type {
            utils.diagnostic(
                s.r,
                get_range(after),
                "Expected an ordered hash map type\nGot the type %s",
                type_to_string(s, val1.type),
            )
            return CheckValueResult{nil, .Invalid}
        }
        if !expect_type(s, get_range(before), Type(hash_map_type.key_type), val0.type) {
            return CheckValueResult{nil, .Invalid}
        }
        out: CheckedValue = CheckedJoinedValues{.In, new_clone(val0.value), new_clone(val1.value)}
        return CheckValueResult{out, .Bool}

    case .Arrow:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, a).v
        }
        tuple, is_tuple := before.first.contents.(Tuple)
        if len(before.rest) != 0 || !is_tuple {
            utils.diagnostic(
                s.r,
                get_range(after),
                "While checking function type: The unit before the `->` should be a tuple (for example `(String, U64)`)",
            )
            return CheckValueResult{CompileTimeValue(Type.Invalid), .Type}
        }
        t, ok := check_function_type(s, tuple.elements, after, a.generic_args)
        if !ok {
            return CheckValueResult{nil, .Type}
        }
        out: CheckedValue = CompileTimeValue(create_type(&s.types, t).type)
        return CheckValueResult{out, .Type}

    case .BooleanAnd, .BooleanOr:
        val0 := check_value_of_type(s, before, CheckValueArgs{a.body, a.generic_args, nil}, .Bool)
        val1 := check_value_of_type(s, after, CheckValueArgs{a.body, a.generic_args, nil}, .Bool)
        if val0 == nil || val1 == nil {
            return CheckValueResult{nil, .Invalid}
        }
        return CheckValueResult{create_joined_values(join_method, val0, val1), .Bool}

    case .IsEqual, .IsNotEqual:
        val0 := check_value(s, before, CheckValueArgs{a.body, a.generic_args, nil}).v
        if !runtime_value_ok(s, get_range(before), val0.value) {
            return CheckValueResult{nil, .Invalid}
        }
        val1 := check_value_of_type(
            s,
            after,
            CheckValueArgs{a.body, a.generic_args, nil},
            val0.type,
        )
        if !runtime_value_ok(s, get_range(after), val1) {
            return CheckValueResult{nil, .Invalid}
        }
        t_simplified := simplify_type(s, val0.type)
        if t_simplified.type == .String {
            str_comp: CheckedValue = StringsAreEqual{new_clone(val0.value), new_clone(val1)}
            if join_method == .IsNotEqual {
                return CheckValueResult{create_not(str_comp), .Bool}
            }
            return CheckValueResult{str_comp, .Bool}
        }
        return CheckValueResult{create_joined_values(join_method, val0.value, val1), .Bool}

    case .Append:
        val0 := check_value(s, before, CheckValueArgs{a.body, a.generic_args, nil}).v
        if !runtime_value_ok(s, get_range(before), val0.value) {
            return CheckValueResult{nil, .Invalid}
        }
        length, item_type := check_array(s, get_range(before), val0.value, val0.type, array_err)
        if length == nil {
            return CheckValueResult{nil, .Invalid}
        }
        val1 := check_value_of_type(
            s,
            after,
            CheckValueArgs{a.body, a.generic_args, nil},
            item_type,
        )
        if !runtime_value_ok(s, get_range(after), val1) {
            return CheckValueResult{nil, .Invalid}
        }
        return_type1 := ArrayType{nil, item_type}
        return_type0 := create_type(&s.types, return_type1).type // TODO: Maybe `::` should be able to output fixed size arrays
        segments := make([]ArraySegment, 2)
        segments[0] = InlineArraySegment{val0.value}
        segments[1] = SingleElemSegment{val1}
        return CheckValueResult{ArrayLiteral{return_type0, segments}, return_type0}

    case .StringConcat:
        val0 := check_value_of_type(
            s,
            before,
            CheckValueArgs{a.body, a.generic_args, nil},
            .String,
        )
        val1 := check_value_of_type(s, after, CheckValueArgs{a.body, a.generic_args, nil}, .String)
        if !runtime_value_ok(s, get_range(before), val0) ||
           !runtime_value_ok(s, get_range(after), val1) {
            return CheckValueResult{nil, .Invalid}
        }
        return CheckValueResult{create_joined_values(.StringConcat, val0, val1), .String}

    case .Concat:
        val0 := check_value(s, before, CheckValueArgs{a.body, a.generic_args, nil}).v
        val1 := check_value(s, after, CheckValueArgs{a.body, a.generic_args, nil}).v
        if !runtime_value_ok(s, get_range(before), val0.value) ||
           !runtime_value_ok(s, get_range(after), val1.value) {
            return CheckValueResult{nil, .Invalid}
        }
        length0, item_type0 := check_array(s, get_range(before), val0.value, val0.type, array_err)
        length1, item_type1 := check_array(s, get_range(after), val1.value, val1.type, array_err)
        if length0 == nil || length1 == nil {
            return CheckValueResult{nil, .Invalid}
        }
        if item_type0 != item_type1 {
            utils.diagnostic(
                s.r,
                join_method_range,
                "Array item type mismatch:\nItem type on left is %s\nItem type on right is %s",
                type_to_string(s, item_type0),
                type_to_string(s, item_type1),
            )
            return CheckValueResult{nil, .Invalid}
        }
        return_type1 := ArrayType{nil, item_type0}
        return_type := create_type(&s.types, return_type1).type // TODO: Maybe `++` should be able to output fixed size arrays
        segments := make([]ArraySegment, 2)
        segments[0] = InlineArraySegment{val0.value}
        segments[1] = InlineArraySegment{val1.value}
        return CheckValueResult{ArrayLiteral{return_type, segments}, return_type}

    case .IsGreaterThan, .IsGreaterThanOrEqual, .IsLessThan, .IsLessThanOrEqual:
        val0 := check_value_of_type(s, before, CheckValueArgs{a.body, a.generic_args, nil}, .Float)
        val1 := check_value_of_type(s, after, CheckValueArgs{a.body, a.generic_args, nil}, .Float)
        if !runtime_value_ok(s, get_range(before), val0) ||
           !runtime_value_ok(s, get_range(after), val1) {
            return CheckValueResult{nil, .Invalid}
        }
        return CheckValueResult{create_joined_values(join_method, val0, val1), .Bool}

    case .Multiplication, .Subtraction, .Division, .Addition, .Modulo:
        get_output_type :: proc(m: UnitJoinMethod) -> Type {
            #partial switch m {
            case .Multiplication, .Addition, .Modulo:
                return .UInt
            case .Subtraction:
                return .Int
            case .Division:
                return .Float
            case:
                panic("Unreachable")
            }
        }
        val0 := check_value(s, before, CheckValueArgs{a.body, a.generic_args, nil}).v
        val1 := check_value(s, after, CheckValueArgs{a.body, a.generic_args, nil}).v
        if !runtime_value_ok(s, get_range(before), val0.value) ||
           !runtime_value_ok(s, get_range(after), val1.value) {
            return CheckValueResult{nil, .Invalid}
        }
        out_type := most_general_number_type(
            s,
            get_output_type(join_method),
            TypeAndRange{val0.type, get_range(before)},
            TypeAndRange{val1.type, get_range(after)},
        )
        if out_type == .Invalid {
            return CheckValueResult{nil, .Invalid}
        }
        return CheckValueResult {
            create_joined_values(join_method, val0.value, val1.value),
            out_type,
        }
    }
}

import_use_err :: "Cannot use an import as a runtime value"
re_then_ident_use_err :: "Cannot use `re` followed by an identifier as a value"

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
    pos: utils.Pos,
    hint: ValueHint,
    generic_args: map[string]Type,
) -> (
    CheckedValue,
    bool,
) {
    switch value in hint {
    case ExpectedType:
        if expect_value_of_type(s, pos, value, nil, Type, "") {
            return nil, false
        }
        return nil, true
    case ValueWithGenericHint:
        global_value := &s.generic_initialisations.values[value.initialisations_ref.index].value.v
        assert(global_value.type == Unknown)
        assert(global_value.value == nil)
        global_value^ = CheckedGlobalValue{Type, nil}
        created := create_type(&s.types, GenericTypeValue{value.ref, value.args, Unknown})
        if created.result == .Merged {
            if created.type_value.(GenericTypeValue).initialised_type == Invalid {
                return Invalid, true
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
        if initialised_type == Invalid {
            return Invalid, true
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
    body:                        ^utils.DebugValue([dynamic]CheckedStatement),

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
    a: CheckValueArgs,
) -> utils.DebugValue(CheckValueResult) {
    out := CompileTimeValue(create_type(&s.types, a.early_exit_if_value_is_type).type)
    return utils.to_debug_value(CheckValueResult{out, .Type})
}

index_type :: Type.Int // TODO: Maybe uInt should be used instead

// `CheckedIndex.start_index == nil` on failure
check_index :: proc(
    s: ^CheckerState,
    u: Unit,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
) -> CheckedIndex {
    split, is_range := try_split_by(u, {.Colon}).(SuccessfulSplit)
    if !is_range {
        start_index := check_value_of_type(
            s,
            u,
            CheckValueArgs{body, generic_args, nil},
            index_type,
        )
        if !runtime_value_ok(s, get_range(u), start_index) {
            return CheckedIndex{}
        }
        return CheckedIndex{new_clone(start_index), nil}
    }
    start_index := check_value_of_type(
        s,
        split.before_split,
        CheckValueArgs{body, generic_args, nil},
        index_type,
    )
    end_index := check_value_of_type(
        s,
        split.after_split,
        CheckValueArgs{body, generic_args, nil},
        index_type,
    )
    if !runtime_value_ok(s, get_range(split.before_split), start_index) ||
       !runtime_value_ok(s, get_range(split.after_split), end_index) {
        return CheckedIndex{}
    }
    return CheckedIndex{new_clone(start_index), new_clone(end_index)}
}

check_tag_value :: proc(
    s: ^CheckerState,
    tag_name: TextAndPos,
    payload_unit: Maybe(Unit),
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
) -> utils.DebugValue(CheckValueResult) {
    expect_camel_case(s, "the tag name", tag_name)

    variant_type: Maybe(Type) = ---
    payload: ^CheckedValue = ---
    if payload_unit == nil {
        variant_type = nil
        payload = nil
    } else {
        checked := check_value(s, payload_unit.(Unit), CheckValueArgs{body, generic_args, nil})
        if checked.v.value == nil {
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        variant_type = checked.v.type
        payload = new_clone(checked.v.value)
    }

    i, _ := utils.lookup_or_insert(
        &s.types.sum_type_tags,
        tag_name.text,
        utils.string_to_index_procs,
    )

    sum_type_payloads := make(map[u32]Maybe(Type))
    sum_type_payloads[i.index] = variant_type
    sum_type := create_type(&s.types, SumType{sum_type_payloads}).type

    return utils.to_debug_value(
        CheckValueResult{SumTypeInitialisation{sum_type, i.index, payload}, sum_type},
    )
}

HashMapKey :: union {
    string,
    f64,
}

CheckedKeyValuePair :: struct {
    key:       HashMapKey,
    key_range: utils.Range,
    key_type:  HashMapKeyType,
    value:     CheckValueResult,
}

// Returns `nil` on failure
check_key_value_pair :: proc(
    s: ^CheckerState,
    arg: Unit,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
) -> Maybe(CheckedKeyValuePair) {
    split, split_ok := try_split_by(arg, {.Assign}).(SuccessfulSplit)
    if !split_ok {
        utils.diagnostic(s.r, get_range(arg), "Expected `key = value`")
        return nil
    }

    // Check key
    key_body := utils.to_debug_value([dynamic]CheckedStatement{})
    key_value := check_value(s, split.before_split, CheckValueArgs{&key_body, generic_args, nil})
    if key_value.v.value == nil {
        return nil
    }
    key_comptime, is_comptime := key_value.v.value.(CompileTimeValue)
    if !is_comptime {
        utils.diagnostic(
            s.r,
            get_range(split.before_split),
            "Key must be comptile-time known value",
        )
        return nil
    }
    assert(len(key_body.v) == 0)
    key: HashMapKey = nil
    key_type := HashMapKeyType.Unknown
    #partial switch simplify_type(s, key_value.v.type).type {
    case .Int, .UInt, .Float:
        number_value := key_comptime.(utils.NumberValue)
        k, ok := utils.number_value_to_f64(number_value).(f64)
        if !ok {
            return nil
        }
        key = k
        key_type = HashMapKeyType(guess_number_type(number_value))
    case .String:
        key = string(key_comptime.(StringLiteralValue))
        key_type = .String
    case:
        utils.diagnostic(
            s.r,
            get_range(split.before_split),
            "Expected the type `String`, `Int`, `UInt`, or `Float` for hash map key\nGot the type `%s`",
            type_to_string(s, key_value.v.type),
        )
        return nil
    }

    // Check value
    value := check_value(s, split.after_split, CheckValueArgs{body, generic_args, nil})
    if !runtime_value_ok(s, get_range(split.after_split), value.v.value) {
        return nil
    }
    return CheckedKeyValuePair{key, get_range(split.before_split), key_type, value.v}
}

check_ordered_hashmap_initialisation :: proc(
    s: ^CheckerState,
    args: []Unit,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
) -> utils.DebugValue(CheckValueResult) {
    if len(args) == 0 {
        return utils.to_debug_value(
            CheckValueResult {
                CompileTimeValue(
                    CompileTimeOrderedHashMapInitialisation{.EmptyOrderedHashMap, nil, nil},
                ),
                .EmptyOrderedHashMap,
            },
        )
    }
    // TODO: This function could expect 0 args, and you would
    // still be able to use the dervation syntax to create an ordered
    // hashmap value, so maybe all this code is unnecersarry
    /*
    type := simplify_type(s, value_being_called.v.value.(CompileTimeValue).(Type))
    type_value, ok := type.key.(OrderedHashMapType)
    if !ok {
        utils.diagnostic(
            s.r,
            value.unit_being_called.pos,
            "Got the type `%s`\nExpected an ordered hash map type for hash map creation",
            type_to_string(s, type.type),
        )
        return utils.to_debug_value(CheckValueResult{nil, .Invalid})
    }
    */
    compile_time_items: map[HashMapKey]CompileTimeValue
    runtime_items: map[HashMapKey]CheckedValue
    order := make([dynamic]HashMapKey)
    value_types: map[Type]struct{} // map[Type]utils.Pos
    key_types: map[Type]struct{} // map[Type]utils.Pos
    for arg in args {
        pair, ok := check_key_value_pair(s, arg, body, generic_args).(CheckedKeyValuePair)
        if !ok {
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        value_types[pair.value.type] = struct{}{} // arg.first.pos
        key_types[Type(pair.key_type)] = struct{}{} // arg.first.pos
        if pair.key in compile_time_items || pair.key in runtime_items {
            utils.diagnostic(
                s.r,
                pair.key_range,
                "The key `%v` is already specified in this map",
                pair.key,
            )
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        if comptime, is_comptime := pair.value.value.(CompileTimeValue); is_comptime {
            compile_time_items[pair.key] = comptime
        } else {
            runtime_items[pair.key] = pair.value.value
        }
        append_elem(&order, pair.key)
    }
    out_type := create_type(
        &s.types,
        OrderedHashMapType {
            HashMapKeyType(find_most_specific_supertype(s, &key_types)),
            find_most_specific_supertype(s, &value_types),
        },
    )
    if len(runtime_items) == 0 {
        return utils.to_debug_value(
            CheckValueResult {
                CompileTimeOrderedHashMapInitialisation {
                    out_type.type,
                    compile_time_items,
                    order[:],
                },
                out_type.type,
            },
        )
    }
    return utils.to_debug_value(
        CheckValueResult {
            OrderedHashMapInitialisation {
                out_type.type,
                compile_time_items,
                runtime_items,
                order[:],
            },
            out_type.type,
        },
    )
}

check_initial_value :: proc(
    s: ^CheckerState,
    v: Unit,
    i: ^uint,
    a: CheckValueArgs,
    loc := #caller_location,
) -> utils.DebugValue(CheckValueResult) {
    when ODIN_DEBUG {
        utils.call(loc, "check_initial_value", "")
    }
    segment := get_segment(v, i^)
    switch value in segment.contents {
    case:
        utils.diagnostic(s.r, segment.range, "Internal error: got nil value in check_value")
        return utils.to_debug_value(CheckValueResult{nil, .Invalid})

    case StructUnit:
        if len(value.elements) == 0 {
            utils.diagnostic(
                s.r,
                segment.range,
                "Cannot have empty `{{}}` because the checker cannot tell if the value is a struct type or a struct literal",
            )
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        fields_map := utils.make_key_to_index(s.a, utils.KeyToIndex(string))
        field_positions := utils.arena_make_multi(s.a, utils.Multi(utils.Pos), len(value.elements))
        field_types := utils.arena_make_multi(s.a, utils.Multi(Unit), len(value.elements))
        defer utils.fix_key_to_index(fields_map)
        kind: enum {
            Unknown,
            StructType,
            StructLiteral,
        } = .Unknown
        for element in value.elements {
            split, ok := try_split_first_by(element, {.Assign, .Colon}).(SuccessfulSplitFirst)
            if !ok {
                utils.diagnostic(
                    s.r,
                    get_range(element),
                    "Elements in `{{}}` must be like `name: Type` or `name = type`",
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }

            switch kind {
            case .Unknown:
                kind = split.split_method == .Colon ? .StructType : .StructLiteral
            case .StructType:
                if split.split_method != .Colon {
                    utils.diagnostic(
                        s.r,
                        split.split_method_range,
                        "Expected `:` for struct type field",
                    )
                    return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                }
            case .StructLiteral:
                if split.split_method != .Assign {
                    utils.diagnostic(
                        s.r,
                        split.split_method_range,
                        "Expected `=` for struct literal field",
                    )
                    return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                }
            }

            ident, ident_ok := split.before_split.contents.(IdentNode)
            if !ident_ok || ident.has_re_before || ident.ident.has_dollar_at_end {
                utils.diagnostic(
                    s.r,
                    split.before_split.range,
                    "Before `:` or `=` in struct field must be just an identifier with no re before and no dollar sign at the end",
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }

            name := ident.ident
            i, result := utils.lookup_or_insert(
                &fields_map,
                name.ident,
                utils.string_to_index_procs,
            )
            if result == .LookedUp {
                utils.diagnostic(
                    s.r,
                    get_range(name),
                    "There is already a field called `%s` defined in this struct at `%v`",
                    name.ident,
                    field_positions.d[i.index],
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }

            field_positions.d[i.index] = name.pos
            field_types.d[i.index] = split.after_split
        }
        switch kind {
        case .StructType:
            if a.early_exit_if_value_is_type != nil {
                return finish_checking_early_return_type(s, a)
            }
            return utils.to_debug_value(
                CheckValueResult {
                    CompileTimeValue(
                        check_struct_type(
                            s,
                            fields_map,
                            field_positions,
                            field_types,
                            a.generic_args,
                        ),
                    ),
                    .Type,
                },
            )
        case .StructLiteral:
            arg_values := make([]CheckedValue, len(value.elements))
            arg_types := make([]Type, len(value.elements))
            ok := true
            for _, i in fields_map.keys {
                checked := check_value(
                    s,
                    field_types.d[i],
                    CheckValueArgs{a.body, a.generic_args, nil},
                )
                arg_types[i] = checked.v.type
                arg_values[i] = checked.v.value
                if arg_values[i] == nil {
                    ok = false
                }
            }
            if !ok {
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
            struct_type :=
                create_type(&s.types, StructType{fields_map, utils.array_to_multi(arg_types)}).type
            return utils.to_debug_value(
                CheckValueResult{create_struct(struct_type, arg_values), struct_type},
            )
        case .Unknown:
            panic("Unreachable")
        case:
            panic("Unreachable")
        }

    /*
    case UnitsInSquareBrackets:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, a)
        }
        array, ok := check_array_type(s, pos, value, a.generic_args)
        if !ok {
            return utils.to_debug_value(CheckValueResult{nil, .Type})
        }
        return utils.to_debug_value(
            CheckValueResult{CompileTimeValue(create_type(&s.types, array).type), .Type},
        )
        */

    case SumUnit:
        if a.early_exit_if_value_is_type != nil {
            return finish_checking_early_return_type(s, a)
        }
        variant_positions := make(map[u32]utils.Pos)
        sum_type := SumType{make(map[u32]Maybe(Type))}
        ok := true
        for elem in value.elements {
            tag, tag_ok := get_tag(s.r, elem).(GetTagResult)
            if !tag_ok {
                ok = false
                continue
            }
            expect_camel_case(s, "the name of a sum type variant", tag.tag_name)
            index, _ := utils.lookup_or_insert(
                &s.types.sum_type_tags,
                tag.tag_name.text,
                utils.string_to_index_procs,
            )
            if index.index in sum_type.payloads {
                utils.diagnostic(
                    s.r,
                    get_range(tag.tag_name),
                    "The variant `%s` is already defined at %v in this sum type",
                    tag.tag_name.text,
                    variant_positions[index.index],
                )
                ok = false
                continue
            }
            if tag.payload == nil {
                sum_type.payloads[index.index] = nil
            } else {
                payload := check_type(s, tag.payload.(Unit), a.generic_args)
                if payload == .Invalid {
                    ok = false
                    continue
                }
                sum_type.payloads[index.index] = payload
            }
        }
        if !ok {
            return utils.to_debug_value(CheckValueResult{nil, .Type})
        }
        return utils.to_debug_value(
            CheckValueResult{CompileTimeValue(create_type(&s.types, sum_type).type), .Type},
        )

    case Import:
        utils.diagnostic(s.r, get_range(v), import_use_err)
        return utils.to_debug_value(CheckValueResult{nil, .Invalid})

    case UnitsInSquareBrackets:
        return utils.to_debug_value(check_array_initialisation(s, value.elements, a))

    case Marker:
        if is_last_segment(v, i^) {
            utils.diagnostic(s.r, segment.range, "Expected another segment after marker")
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        i^ += 1
        return utils.to_debug_value(check_value_with_marker(s, value.marker, v, i, a))

    case Tuple:
        if len(value.elements) != 1 {
            utils.diagnostic(
                s.r,
                segment.range,
                "Only tuples with one element are supported\nThis tuple has %d elements",
                len(value.elements),
            )
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        return check_value(s, value.elements[0], a)

    case Bool:
        return utils.to_debug_value(CheckValueResult{CompileTimeValue(BoolValue(value)), .Bool})
    case FuncDefinitionRef:
        out_func, out_type := check_anonymous_func_head(s, value, a.generic_args)
        return utils.to_debug_value(CheckValueResult{out_func, out_type})
    /*
    case HierarchyJoinedUnits:
        return utils.to_debug_value(check_joined_unit_value(s, pos, value, a))
    */

    case IdentNode:
        if value.has_re_before {
            utils.diagnostic(s.r, segment.range, re_then_ident_use_err)
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        return utils.to_debug_value(check_var_ref_start(s, value.ident, a.generic_args))

    case UnitJoinMethod:
        if is_last_segment(v, i^) {
            utils.diagnostic(s.r, segment.range, "Expected another segment after join method")
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        i^ += 1
        first := get_segment(v, i^)
        #partial switch value {
        case .Colon:
            ident, is_ident := first.contents.(IdentNode)
            if !is_ident || ident.has_re_before {
                utils.diagnostic(
                    s.r,
                    first.range,
                    "After `:`, expected an identifier without `re` before to create a tag",
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
            return check_tag_value(
                s,
                TextAndPos{ident.ident.ident, ident.ident.pos},
                nil,
                a.body,
                a.generic_args,
            )
        case .Subtraction:
            value := check_initial_value(s, v, i, CheckValueArgs{a.body, a.generic_args, nil})
            if !runtime_value_ok(s, first.range, value.v.value) {
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
            out_type := most_general_number_type(s, .Int, TypeAndRange{value.v.type, first.range})
            return utils.to_debug_value(CheckValueResult{create_negation(value.v.value), out_type})
        case:
            utils.diagnostic(
                s.r,
                segment.range,
                "Join method that is the first segment of a unit must be either `:` or `-`, got %v",
                value,
            )
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }

    case WholeNonNegativeNumber:
        whole_part := utils.big_uint_from_string(value.digits)
        fraction_part := ""
        if is_segment(v, i^ + 2) {
            dot_segment := get_segment(v, i^ + 1)
            fraction_segment := get_segment(v, i^ + 2)
            dot_value, dot_value_ok := dot_segment.contents.(UnitJoinMethod)
            fraction_value, fraction_value_ok := fraction_segment.contents.(WholeNonNegativeNumber)
            if dot_value_ok && fraction_value_ok && dot_value == .Dot {
                i^ += 2
                fraction_part = fraction_value.digits
            }
        }
        n := utils.NumberValue{false, whole_part, fraction_part}
        return utils.to_debug_value(CheckValueResult{CompileTimeValue(n), guess_number_type(n)})

    case String:
        out := CompileTimeValue(StringLiteralValue(value))
        return utils.to_debug_value(CheckValueResult{out, .String})

    case Char:
        out := CompileTimeValue(utils.NumberValue{false, utils.big_uint_from_u64(u64(value)), ""})
        return utils.to_debug_value(CheckValueResult{out, .Char})
    }
}

// Returns `ArrayElementAccess{}` on failure
check_array_index_derivation_subset :: proc(
    s: ^CheckerState,
    args: []Unit,
    args_range: utils.Range,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
) -> ArrayElementAccess {
    if len(args) != 1 {
        utils.diagnostic(
            s.r,
            args_range,
            "Expected 1 value in square brackets\nGot %d values",
            len(args),
        )
        return ArrayElementAccess{}
    }
    index := check_value_of_type(s, args[0], CheckValueArgs{body, generic_args, nil}, index_type)
    utils.diagnostic(s.r, args_range, bounds_checks_warning, type = .Warning)
    return ArrayElementAccess{index}
}

// Returns `nil, .Invalid` on failure
// The type returned is the type of the derivation alteration's value
check_derivation_subset :: proc(
    s: ^CheckerState,
    derivation_base_type: Type,
    unit: Unit,
    generic_args: map[string]Type,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    elements: ^[dynamic]DerivationSubsetElement,
) -> Type {
    /*
    if call, is_call := unit.unit.(CallWithSquareBrackets); is_call {
        subset, type := check_derivation_subset(
            s,
            derivation_base_type,
            call.unit_being_called^,
            generic_args,
            body,
        )
        if type == .Invalid {
            return utils.DoubleDynamic(DerivationSubsetElement){}, .Invalid
        }
        array_type, is_array := simplify_type(s, type).key.(ArrayType)
        if !is_array {
            utils.diagnostic(
                s.r,
                unit.pos,
                "Square bracket call expects an array\nGot the type `%s`",
                type_to_string(s, type),
            )
            return utils.DoubleDynamic(DerivationSubsetElement){}, .Invalid
        }
        subset_elem := check_array_index_derivation_subset(
            s,
            unit.pos,
            call.args,
            body,
            generic_args,
        )
        if subset_elem.index == nil {
            return utils.DoubleDynamic(DerivationSubsetElement){}, .Invalid
        }
        utils.dynamic_append_elem(&subset, subset_elem)
        return subset, array_type.item_type
    }
    */
    #partial switch t in simplify_type(s, derivation_base_type).key {
    case ArrayType:
        args, args_ok := unit.first.contents.(UnitsInSquareBrackets)
        if !args_ok {
            utils.diagnostic(
                s.r,
                unit.first.range,
                "For array type `%s`\nCan only use unit in square brackets as derivation subset\nGot %v",
                type_to_string(s, derivation_base_type),
                unit.first.contents,
            )
            return .Invalid
        }
        subset_elem := check_array_index_derivation_subset(
            s,
            args.elements,
            unit.first.range,
            body,
            generic_args,
        )
        if subset_elem.index == nil {
            return .Invalid
        }
        append(elements, subset_elem)
        if len(unit.rest) == 0 {
            return t.item_type
        }
        return check_derivation_subset(
            s,
            t.item_type,
            Unit{unit.rest[0], unit.rest[1:]},
            generic_args,
            body,
            elements,
        )
    case OrderedHashMapType:
        unit_in_square_brackets, ok := unit.first.contents.(UnitsInSquareBrackets)
        if !ok {
            utils.diagnostic(
                s.r,
                unit.first.range,
                "For ordered hash map type `%s`\nCan only use unit in square brackets as derivation subset",
                type_to_string(s, derivation_base_type),
            )
            return .Invalid
        }
        if len(unit_in_square_brackets.elements) != 1 {
            utils.diagnostic(
                s.r,
                unit.first.range,
                "Expected 1 value in square brackets\nGot %d values",
                len(unit_in_square_brackets.elements),
            )
            return .Invalid
        }
        key := check_value_of_type(
            s,
            unit_in_square_brackets.elements[0],
            CheckValueArgs{body, generic_args, nil},
            Type(t.key_type),
        )
        if key == nil {
            return .Invalid
        }
        append(elements, StringOrderedHashMapAccess{key})
        if len(unit.rest) == 0 {
            return t.value_type
        }
        return check_derivation_subset(
            s,
            t.value_type,
            Unit{unit.rest[0], unit.rest[1:]},
            generic_args,
            body,
            elements,
        )
    case StructType:
        join_method, join_method_ok := unit.first.contents.(UnitJoinMethod)
        if !join_method_ok || join_method != .Dot {
            utils.diagnostic(
                s.r,
                unit.first.range,
                "For struct type `%s`\nExpected `.` to be the first segment of the derivation subset",
                type_to_string(s, derivation_base_type),
            )
            return .Invalid
        }
        err_start :: "For struct type `%s`\nExpected an identifier without `re` before it "
        err_end :: " of the derivation subset"
        if len(unit.rest) == 0 {
            utils.diagnostic(
                s.r,
                unit.first.range,
                err_start + "after this segment" + err_end,
                type_to_string(s, derivation_base_type),
            )
            return .Invalid
        }
        field_name, field_ok := unit.rest[0].contents.(IdentNode)
        if !field_ok || field_name.has_re_before {
            utils.diagnostic(
                s.r,
                unit.rest[0].range,
                err_start + "as the second segment" + err_end,
                type_to_string(s, derivation_base_type),
            )
            return .Invalid
        }
        field_index := utils.lookup(t.m, field_name.ident.ident, utils.string_to_index_procs)
        if field_index == utils.does_not_exist {
            utils.diagnostic(
                s.r,
                get_range(field_name.ident),
                "The field `%s` does not exist in the struct type `%s`",
                field_name.ident.ident,
                type_to_string(s, derivation_base_type),
            )
            return .Invalid
        }
        append(elements, FieldAccess{field_index.index})
        out_type := t.types.d[field_index.index]
        if len(unit.rest) == 1 {
            return out_type
        } else {
            return check_derivation_subset(
                s,
                out_type,
                Unit{unit.rest[1], unit.rest[2:]},
                generic_args,
                body,
                elements,
            )
        }
    case:
        utils.diagnostic(
            s.r,
            get_range(unit),
            "Cannot have derivation subset when the type of the derivation base is `%s`",
            type_to_string(s, derivation_base_type),
        )
        return .Invalid
    }
}

alteration_methods :: bit_set[UnitJoinMethod]{.Assign, .PipeEquals}

// If DerivationAlteration.arg == nil then the checking failed
check_derivation_alteration :: proc(
    s: ^CheckerState,
    join_method: UnitJoinMethod,
    join_method_range: utils.Range,
    unit: Unit,
    value_type: Type,
    body: ^utils.DebugValue([dynamic]CheckedStatement),
    generic_args: map[string]Type,
) -> DerivationAlteration {
    #partial switch join_method {
    case .Assign:
        new_value := check_value_of_type(
            s,
            unit,
            CheckValueArgs{body, generic_args, nil},
            value_type,
        )
        if new_value == nil {
            return DerivationAlteration{}
        }
        return DerivationAlteration{.Replace, new_clone(new_value)}
    case .PipeEquals:
        // TODO: Support `|=` without curried functions
        arr := make([]Type, 1)
        arr[0] = value_type
        func := check_value_of_type(
            s,
            unit,
            CheckValueArgs{body, generic_args, nil},
            create_type(&s.types, FuncType{arr, arr}).type,
        )
        if func == nil {
            return DerivationAlteration{}
        }
        return DerivationAlteration{.PipeThroughFunction, new_clone(func)}
    case:
        panic("Unreachable")
    }
}

check_value_of_type :: proc(
    s: ^CheckerState,
    v: Unit,
    a: CheckValueArgs,
    expected_type: Type,
    loc := #caller_location,
) -> CheckedValue {
    when ODIN_DEBUG {
        utils.call(loc, "check_value_of_type", "")
    }
    r := check_value(s, v, a)
    if r.v.value == nil {
        return nil
    }
    if expect_type(s, get_range(v), expected_type, r.v.type) {
        return r.v.value
    }
    return nil
}

CheckValueResult :: struct {
    value: CheckedValue,
    type:  Type,
}

check_value :: proc(
    s: ^CheckerState,
    v: Unit,
    a: CheckValueArgs,
    loc := #caller_location,
) -> utils.DebugValue(CheckValueResult) {
    when ODIN_DEBUG {
        utils.call(
            loc,
            "check_value",
            "a.early_exit_if_value_is_type: %v",
            a.early_exit_if_value_is_type,
        )
        utils.print_arg("v", v)
    }

    if len(v.rest) == 0 {
        i: uint = 0
        return check_initial_value(s, v, &i, a)
    }

    if split, split_ok := try_split_by(v, {.Tilde}).(SuccessfulSplit); split_ok {
        res := check_value(s, split.before_split, CheckValueArgs{a.body, a.generic_args, nil}).v
        if res.value == nil {
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }

        after_split, after_split_ok := try_split_by(
            split.after_split,
            {.Assign, .PipeEquals},
        ).(SuccessfulSplit)
        if !after_split_ok {
            utils.diagnostic(
                s.r,
                get_range(split.after_split),
                "Expected an `=` to set the subset's new value or an `|=` to update the subset's value within this text area",
                "",
            )
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }

        derivation_subset: [dynamic]DerivationSubsetElement
        derivation_alteration_type := check_derivation_subset(
            s,
            res.type,
            after_split.before_split,
            a.generic_args,
            a.body,
            &derivation_subset,
        )
        if derivation_alteration_type == .Invalid {
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }

        alteration := check_derivation_alteration(
            s,
            after_split.split_method,
            after_split.split_method_range,
            after_split.after_split,
            derivation_alteration_type,
            a.body,
            a.generic_args,
        )
        if alteration.arg == nil {
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        return utils.to_debug_value(
            CheckValueResult {
                CheckedDerivation {
                    new_clone(res.value),
                    DerivationSubset{derivation_subset[:]},
                    alteration,
                },
                res.type,
            },
        )
    }

    if split, split_ok := try_split_first_by(v, {.Colon}).(SuccessfulSplitFirst); split_ok {
        tag_name, tag_name_ok := get_text_and_pos_from_unit_segment(
            s.r,
            split.before_split,
        ).(TextAndPos)
        if !tag_name_ok {
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
        return check_tag_value(s, tag_name, split.after_split, a.body, a.generic_args)
    }

    if split, split_ok := try_split_by(v, {.BooleanOr, .BooleanAnd}).(SuccessfulSplit); split_ok {
        return utils.to_debug_value(
            check_joined_unit_value(
                s,
                split.split_method,
                split.split_method_range,
                split.before_split,
                split.after_split,
                a,
            ),
        )
    }

    if split, split_ok := try_split_by(
           v,
           {
               .IsEqual,
               .IsNotEqual,
               .IsGreaterThan,
               .IsLessThan,
               .IsGreaterThanOrEqual,
               .IsLessThanOrEqual,
           },
       ).(SuccessfulSplit); split_ok {
        return utils.to_debug_value(
            check_joined_unit_value(
                s,
                split.split_method,
                split.split_method_range,
                split.before_split,
                split.after_split,
                a,
            ),
        )
    }

    if split, split_ok := try_split_by(v, {.In}).(SuccessfulSplit); split_ok {
        return utils.to_debug_value(
            check_joined_unit_value(
                s,
                split.split_method,
                split.split_method_range,
                split.before_split,
                split.after_split,
                a,
            ),
        )
    }

    if split, split_ok := try_split_by(
           v,
           {.Append, .Concat, .StringConcat, .Arrow},
       ).(SuccessfulSplit); split_ok {
        return utils.to_debug_value(
            check_joined_unit_value(
                s,
                split.split_method,
                split.split_method_range,
                split.before_split,
                split.after_split,
                a,
            ),
        )
    }

    if split, split_ok := try_split_by(v, {.Addition, .Subtraction, .Modulo}).(SuccessfulSplit);
       split_ok {
        return utils.to_debug_value(
            check_joined_unit_value(
                s,
                split.split_method,
                split.split_method_range,
                split.before_split,
                split.after_split,
                a,
            ),
        )
    }

    if split, split_ok := try_split_by(v, {.Multiplication, .Division}).(SuccessfulSplit);
       split_ok {
        return utils.to_debug_value(
            check_joined_unit_value(
                s,
                split.split_method,
                split.split_method_range,
                split.before_split,
                split.after_split,
                a,
            ),
        )
    }

    i: uint = 0
    res := check_initial_value(s, v, &i, CheckValueArgs{a.body, a.generic_args, nil}).v
    i += 1
    if res.value == nil {
        return utils.to_debug_value(CheckValueResult{nil, .Invalid})
    }
    for ; is_segment(v, i); i += 1 {
        res_range := get_range(Unit{v.first, v.rest[:i - 1]})
        segment := get_segment(v, i)
        #partial switch contents in segment.contents {
        case:
            utils.diagnostic(
                s.r,
                segment.range,
                "Cannot use this kind of unit segment to extend value",
            )
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        case UnitJoinMethod:
            if is_last_segment(v, i) {
                utils.diagnostic(
                    s.r,
                    segment.range,
                    "Unexpected trailing join method\nHint: Try adding an extra unit segment after this join method",
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
            i += 1
            if contents == .Dot {
                ident, is_ident := get_segment(v, i).contents.(IdentNode)
                if !is_ident || ident.has_re_before {
                    utils.diagnostic(
                        s.r,
                        segment.range,
                        "After `.`, expected identifier with `re` before it",
                    )
                    return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                }
                res = check_var_ref(
                    s,
                    res_range,
                    res,
                    ident.ident,
                    CheckValueArgs{a.body, a.generic_args, nil},
                )
            } else {
                utils.diagnostic(
                    s.r,
                    segment.range,
                    "Expected join method `.` to extend value\nGot join method %v",
                    contents,
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
        case Tuple:
            /*
        if array_type, is_array := value.unit_being_called.unit.(CallWithFrontedSquareBrackets);
           is_array {
            return utils.to_debug_value(
                check_array_initialisation(
                    s,
                    pos,
                    array_type,
                    value.unit_being_called.pos,
                    value.args,
                    CheckValueArgs{a.body, a.generic_args, nil},
                ),
            )
        }
        */
            if comptime, is_comptime := res.value.(CompileTimeValue); is_comptime {
                _, is_ordered_hash_map := comptime.(UninitialisedOrderedHashMapType)
                if is_ordered_hash_map {
                    assert(res.type == .Unknown)
                    return check_ordered_hashmap_initialisation(
                        s,
                        contents.elements,
                        a.body,
                        a.generic_args,
                    )
                }
            }
            call, call_ok := check_function_call(
                s,
                res,
                res_range,
                contents.elements,
                segment.range,
                a.body,
                a.generic_args,
            ).(CheckedFuncCall)
            if !call_ok {
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
            if len(call.return_types) != 1 {
                utils.diagnostic(
                    s.r,
                    res_range,
                    return_type_count_mismatch,
                    1,
                    len(call.return_types),
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
            res = CheckValueResult{call.value, call.return_types[0]}
            continue

        case UnitsInSquareBrackets:
            res.type = simplify_type(s, res.type).type
            if res.type == .Unknown {
                checked_args := make([]Type, len(contents.elements))
                ok := true
                for arg, i in contents.elements {
                    checked_args[i] = check_type(s, arg, a.generic_args)
                    if checked_args[i] == .Invalid {
                        ok = false
                    }
                }
                if !ok {
                    return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                }
                #partial switch comptime_value in res.value.(CompileTimeValue) {
                case GlobalValueWithGenericRef:
                    res = check_comptime_func_call(s, res_range, comptime_value, checked_args)
                    continue

                case UninitialisedOrderedHashMapType:
                    if a.early_exit_if_value_is_type != nil {
                        return finish_checking_early_return_type(s, a)
                    }
                    if len(checked_args) != 2 {
                        argument_count_mismatch(s, res_range, len(checked_args), 2)
                        return utils.to_debug_value(CheckValueResult{nil, .Type})
                    }
                    key := simplify_type(s, checked_args[0])
                    type_key: TypeKey
                    #partial switch key.type {
                    case .String, .Int, .UInt, .Float, .Any:
                        type_key = OrderedHashMapType{HashMapKeyType(key.type), checked_args[1]}
                    case:
                        utils.diagnostic(
                            s.r,
                            segment.range,
                            "The key of an `OrderedHashMap` must be either `String`, `Int`, `UInt`, `Float` or `Any`\nGot the key `%s`\nTODO: Support more `OrderedHashMap` keys",
                            type_to_string(s, checked_args[0]),
                        )
                        return utils.to_debug_value(CheckValueResult{nil, .Type})
                    }
                    res.value = CompileTimeValue(create_type(&s.types, type_key).type)
                    res.type = .Type
                    continue
                case BuiltinFunction:
                    assert(comptime_value == .cast_func)
                    if len(checked_args) != 1 {
                        argument_count_mismatch(s, res_range, len(checked_args), 1)
                        return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                    }
                    args := make([]Type, 1)
                    args[0] = .Any
                    return_types := make([]Type, 1)
                    return_types[0] = checked_args[0]
                    res = CheckValueResult {
                        CompileTimeValue(CastFunction{checked_args[0]}),
                        create_type(&s.types, FuncType{args, return_types}).type,
                    }
                    continue
                }
                panic("Unreachable")
            } else if res.type == .Type {
                if a.early_exit_if_value_is_type != nil {
                    return finish_checking_early_return_type(s, a)
                }
                array, ok := check_array_type(
                    s,
                    res.value.(CompileTimeValue).(Type),
                    contents.elements,
                    segment.range,
                    a.generic_args,
                )
                if !ok {
                    return utils.to_debug_value(CheckValueResult{nil, .Type})
                }
                res = CheckValueResult{CompileTimeValue(create_type(&s.types, array).type), .Type}
                continue
            }
            if len(contents.elements) != 1 {
                utils.diagnostic(
                    s.r,
                    segment.range,
                    "Indexed accesses into an array or ordered hash map must pass one value into the square brackets\nGot %d values",
                    len(contents.elements),
                )
                return utils.to_debug_value(CheckValueResult{nil, .Invalid})
            }
            if res.type == .String {
                index := check_index(s, contents.elements[0], a.body, a.generic_args)
                if index.start_index == nil {
                    return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                }
                res = CheckValueResult {
                    CheckedIndexedAccess{.String, new_clone(res.value), index},
                    index.end_index == nil ? .Char : .String,
                }
                continue
            }
            #partial switch t in get_type(s.types, res.type).key {
            case ArrayType:
                utils.diagnostic(s.r, segment.range, bounds_checks_warning, type = .Warning)
                index := check_index(s, contents.elements[0], a.body, a.generic_args)
                if index.start_index == nil {
                    return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                }
                //if t.length == 0 {
                //    utils.diagnostic(
                //        s,
                //        value.array.pos,
                //        "TODO: Implement element access for dynamically sized arrays",
                //    )
                //    return nil, false
                //}
                res = CheckValueResult {
                    CheckedIndexedAccess{.Array, new_clone(res.value), index},
                    // TODO: Gives wrong type if being_called is a fixed-size array
                    index.end_index == nil ? t.item_type : res.type,
                }
                continue
            case OrderedHashMapType:
                key_value := check_value_of_type(
                    s,
                    contents.elements[0],
                    CheckValueArgs{a.body, a.generic_args, nil},
                    Type(t.key_type),
                )
                if !runtime_value_ok(s, get_range(contents.elements[0]), key_value) {
                    return utils.to_debug_value(CheckValueResult{nil, .Invalid})
                }
                res = CheckValueResult {
                    CheckedOrderedHashMapAccess{new_clone(res.value), new_clone(key_value)},
                    t.value_type,
                }
                continue
            }
            utils.diagnostic(
                s.r,
                res_range,
                "The value is of type `%s`\nExpected a string type, an array type or an `OrderedHashMap` type for indexed/keyed access",
                type_to_string(s, res.type),
            )
            return utils.to_debug_value(CheckValueResult{nil, .Invalid})
        }
    }
    return utils.to_debug_value(res)
}

get_inline_func_fields :: proc(s: ^CheckerState) -> (InlineFuncFields, utils.Multi(VariableRef)) {
    if len(s.variables_map) == 0 {
        return InlineFuncFields{}, utils.Multi(VariableRef){nil}
    }
    variables_from_outer_scope: map[string]VariableRef
    scope0: Scope
    lambda_args := utils.arena_make_multi(s.a, utils.Multi(VariableRef), 0, resizable = true)
    defer utils.fix_resizable_multi(lambda_args)

    for var_name, var_ref in s.variables_map {
        variable := s.scopes[var_ref.nesting_level].variables[var_ref.index]

        if variable.is_reassignable {
            // Reassignable variables defined in an outer function are not accessible from an inline function
            continue
        }

        variables_from_outer_scope[var_name] = VariableRef{0, len(scope0.variables)}
        utils.append_multi_dynamic(&lambda_args, len(scope0.variables), var_ref)
        append(&scope0.variables, variable)
    }

    return InlineFuncFields{variables_from_outer_scope, scope0}, lambda_args
}

// Returns `nil, Invalid` on failure
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
        return nil, .Invalid
    }
    type := create_type(&s.types, checked_func_type).type
    checked_ref := CheckedFuncRef{len(s.checked_functions)}
    append(
        &s.checked_functions,
        CheckedFunction {
            type,
            ref,
            generic_args,
            nil,
            utils.to_debug_value([]CheckedStatement{}, "checked_ref.index: %d", checked_ref.index),
            inline_func_fields,
        },
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
    body := utils.to_debug_value([dynamic]CheckedStatement{})
    variables, block_ok := check_block(s, func.body, &body, generic_args)
    if !block_ok.v {
        if !s.r.has_errors(s.r.data) {
            utils.panicf("Failed to check block but no errors reported\nblock_ok: %v", block_ok)
        }
        return false
    }
    s.checked_functions[ref.index].variables = variables
    s.checked_functions[ref.index].body = utils.debug_dynamic_array_to_slice(body)
    return true
}

// Returns `CheckedGlobalValue{Invalid, nil}` on failure
check_global_value_without_generic :: proc(
    s: ^CheckerState,
    ref: GlobalValueWithoutGenericRef,
    loc := #caller_location,
) -> CheckedGlobalValue {
    utils.call(loc, "check_global_value_without_generic", "")
    global := &s.global_values_without_generic[ref.index]
    if global.v.type != .Unknown {
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
    if len(value.unit.rest) == 0 {
        if import_value, is_import := value.unit.first.contents.(Import); is_import {
            global.v = CheckedGlobalValue{.ImportedFile, import_value}
            return global.v
        }
    }
    body := utils.to_debug_value([dynamic]CheckedStatement{})
    early_exit_if_value_is_type: TypeKey = GlobalType{ref}
    old_scope_state := s.scope_state
    s.scope_state = CheckerScopeState{}
    checked_value := check_value(
        s,
        value.unit,
        CheckValueArgs{&body, no_generic_args, early_exit_if_value_is_type},
    )
    s.scope_state = old_scope_state
    when false {
        fmt.printfln(
            "Checked global with name `%s`\nvalue: `%v`\ntype: `%v`",
            global.ast_node.name,
            checked_value,
            type_to_string(s, checked_value.v.type),
        )
    }
    if checked_value.v.value == nil {
        global.v = CheckedGlobalValue{.Invalid, nil}
        return global.v
    }
    comptime_value, ok := checked_value.v.value.(CompileTimeValue)
    if !ok {
        utils.diagnostic(s.r, get_range(value.unit), non_compiletime_global_err)
        global.v = CheckedGlobalValue{.Invalid, nil}
        return global.v
    }
    assert(len(body.v) == 0)
    if checked_value.v.type == .Invalid {
        assert(comptime_value == nil)
    }
    global.v = CheckedGlobalValue{checked_value.v.type, comptime_value}
    if checked_value.v.type == .Type {
        type_value := comptime_value.(Type)
        assert(type_key_is_equal(s.types.m.keys[type_value].key, early_exit_if_value_is_type))
        checked_value = check_value(s, value.unit, CheckValueArgs{nil, no_generic_args, nil})
        assert(checked_value.v.type == .Type)
        if checked_value.v.value == nil {
            s.types.values.d[type_value].type = .Invalid
        } else {
            s.types.values.d[type_value].type = checked_value.v.value.(CompileTimeValue).(Type)
        }
    }
    return global.v
}

length_of_array :: proc(type: ArrayType, value: CheckedValue) -> CheckedValue {
    if length, has_length := type.length.(u32); has_length {
        return CompileTimeValue(utils.NumberValue{false, utils.big_uint_from_u64(u64(length)), ""})
    }
    return LengthOfArray{new_clone(value)}
}

// Returns `nil, Type{}` if there was an error
// The `CheckedValue` returned is the length of the array
// The `Type` returned is the array's item_type
check_array :: proc(
    s: ^CheckerState,
    range: utils.Range,
    value: CheckedValue,
    value_type: Type,

    // The error message for if the value is not an array
    // Must have one `%s` in it for the actual type of the value
    err_msg: string,
) -> (
    CheckedValue,
    Type,
) {
    array, ok := get_array_type(s, range, "This value", value_type)
    if !ok {
        // utils.diagnostic(s, pos, err_msg, type_to_string(s, value_type))
        return nil, Type{}
    }
    return length_of_array(array, value), array.item_type
}

// Returns `CheckedFuncRef{max(uint)}` on failure
get_global_function :: proc(
    s: ^CheckerState,
    usage_range: utils.RangeOrFile,
    file_to_search: ^utils.CompilerFile,
    name: string,
    extra_text: string,
) -> CheckedFuncRef {
    parsed_global, exists := s.parsed_files.d[get_file_index(s.files, file_to_search)][name]
    if !exists {
        utils.diagnostic(s.r, usage_range, "The global `%s` is not defined%s", name, extra_text)
        return CheckedFuncRef{max(uint)}
    }
    pos: utils.Range = ---
    switch r in usage_range {
    case utils.Range:
        pos = r
    case ^utils.CompilerFile:
        pos = utils.Range{parsed_global.pos, utils.to_debug_value(uint(len(name))), file_to_search}
    case:
        panic("Unreachable")
    }
    if parsed_global.has_generics {
        utils.diagnostic(
            s.r,
            pos,
            "The global `%s` has generic\nExpected it to not have generics%s",
            name,
            extra_text,
        )
        return CheckedFuncRef{max(uint)}
    }
    global := s.global_values_without_generic[parsed_global.index]
    func_ref, is_func := global.v.value.(Func)
    if !is_func {
        utils.diagnostic(
            s.r,
            pos,
            "The global value `%s` is not a function and so cannot be called%s",
            name,
            extra_text,
        )
        return CheckedFuncRef{max(uint)}
    }
    return func_ref.ref
}

EntryFuncType :: enum {
    BuildFunc,
    MainFunc,
}

CheckerOutput :: struct {
    func_ref:                CheckedFuncRef,
    globals_without_generic: []GlobalValueWithoutGeneric,
    globals_with_generic:    []GlobalValueWithGeneric,
    checked_funcs:           []CheckedFunction,
    types:                   Types,
}

add_sum_type :: proc(
    s: ^CheckerState,
    variants: ^map[u32]Maybe(map[Type]struct{}),
    sum_type: SumType,
) -> Maybe(Type) {
    for tag_index, payload in sum_type.payloads {
        if tag_index in variants {
            m := &variants[tag_index]
            if m^ == nil {
                if payload != nil {
                    return .Any
                }
            } else {
                if payload == nil {
                    return .Any
                }
                (&m.(map[Type]struct{}))[payload.(Type)] = struct{}{}
            }
        } else if payload == nil {
            variants[tag_index] = nil
        } else {
            m := make(map[Type]struct{})
            m[payload.(Type)] = struct{}{}
            variants[tag_index] = m
        }
    }
    return nil
}

// Never fails by returning `.Any`
find_most_specific_supertype :: proc(s: ^CheckerState, args: ^map[Type]struct{}) -> Type {
    key, _ := utils.pop_map(args)
    if len(args) == 0 {
        return key
    }
    simplified := simplify_type(s, key)
    if simplified.type > .MaxIndex {
        out := simplified.type
        if out != .Int && out != .UInt && out != .Float {
            return .Any
        }
        for k in args {
            #partial switch simplify_type(s, k).type {
            case .UInt:
            case .Int:
                if out == .UInt {
                    out = .Int
                }
            case .Float:
                out = .Float
            case:
                return .Any
            }
        }
        return out
    }
    switch type in simplified.key {
    case SumType:
        variants := make(map[u32]Maybe(map[Type]struct{}))
        out, should_return := add_sum_type(s, &variants, type).(Type)
        if should_return {
            return out
        }
        for k in args {
            sum_type, is_sum_type := simplify_type(s, k).key.(SumType)
            if !is_sum_type {
                return .Any
            }
            out, should_return = add_sum_type(s, &variants, sum_type).(Type)
            if should_return {
                return out
            }
        }
        sum_type := SumType{}
        for tag_index, &payload in variants {
            if payload == nil {
                sum_type.payloads[tag_index] = nil
            } else {
                sum_type.payloads[tag_index] = find_most_specific_supertype(
                    s,
                    &payload.(map[Type]struct{}),
                )
            }
        }
        return create_type(&s.types, sum_type).type
    case StructType:
        fields := type.m
        field_types := make([]map[Type]struct{}, len(fields.keys))
        for type, i in utils.multi_to_array(type.types, len(type.m.keys)) {
            field_types[i][type] = struct{}{}
        }

        for key, pos in args {
            struct_type, is_struct_type := simplify_type(s, key).key.(StructType)
            if !is_struct_type {
                return .Any
            }
            if len(struct_type.m.keys) != len(fields.keys) {
                return .Any
            }
            for field_key, i in fields.keys {
                if field_key.key != struct_type.m.keys[i].key {
                    return .Any
                }
                field_types[i][struct_type.types.d[i]] = pos
            }
        }

        finalized_field_types := utils.arena_make_multi(s.a, utils.Multi(Type), len(fields.keys))
        for &field_type, i in field_types {
            finalized_field_types.d[i] = find_most_specific_supertype(s, &field_type)
        }

        return create_type(&s.types, StructType{fields, finalized_field_types}).type
    case FuncType:
        // TODO: Implement a function like `find_most_general_subtype` for the function arguments
        // TODO: Implement this branch
        return .Any
    case ArrayType:
        length: Maybe(u32) = type.length
        item_types := make(map[Type]struct{})
        if type.length == nil || type.length.(u32) != 0 {
            item_types[type.item_type] = struct{}{}
        }

        for key, pos in args {
            array_type, is_array_type := simplify_type(s, key).key.(ArrayType)
            if !is_array_type {
                return .Any
            }

            if length != nil {
                if array_type.length == nil || array_type.length.(u32) != length.(u32) {
                    length = nil
                }
            }

            if array_type.length == nil || array_type.length.(u32) != 0 {
                item_types[array_type.item_type] = pos
            }
        }

        out := create_type(
            &s.types,
            ArrayType{length, find_most_specific_supertype(s, &item_types)},
        )
        return out.type
    case OrderedHashMapType:
        key_types: map[Type]struct{}
        value_types: map[Type]struct{}

        key_types[Type(type.key_type)] = struct{}{}
        value_types[type.value_type] = struct{}{}

        for key, pos in args {
            simplified := simplify_type(s, key)
            if simplified.type == .EmptyOrderedHashMap {
                continue
            }
            ordered_hashmap_type, is_ordered_hash_map := simplified.key.(OrderedHashMapType)
            if !is_ordered_hash_map {
                return .Any
            }
            key_types[Type(ordered_hashmap_type.key_type)] = pos
            value_types[ordered_hashmap_type.value_type] = pos
        }

        out := create_type(
            &s.types,
            OrderedHashMapType {
                HashMapKeyType(find_most_specific_supertype(s, &key_types)),
                find_most_specific_supertype(s, &value_types),
            },
        )
        return out.type
    case GlobalType, GenericTypeValue:
        panic("Unreachable (should be handled by `simplify_type`)")
    case:
        panic("Unreachable")
    }
}

check :: proc(
    a: ^utils.Arena,
    parsed: ParserOutput,
    files: []utils.CompilerFile,
    func_name: string,
    func_file: ^utils.CompilerFile,
    io: utils.Pipe(io.Writer),
    diagnostic_reporter: utils.DiagnosticReporter,
    loc := #caller_location,
) -> CheckerOutput {
    utils.call(loc, "check", "", enable_debug = utils.debug_checker)
    state := CheckerState {
        a                             = a,
        generic_initialisations       = GenericInitialisations {
            utils.make_key_to_index(a, utils.KeyToIndex(GenericInitialisation)),
            utils.arena_make_multi(
                a,
                utils.Multi(utils.DebugValue(CheckedGlobalValue)),
                0,
                resizable = true,
            ),
        },
        r                             = diagnostic_reporter,
        parsed_files                  = parsed.parsed_files,
        files                         = files,
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
        utils.fix_key_to_index(state.generic_initialisations.m)
        utils.fix_resizable_multi(state.generic_initialisations.values)
    }

    for _, i in state.global_values_without_generic {
        state.global_values_without_generic[i].v.type = .Unknown
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
            if get_builtin(arg.text).value != nil {
                utils.diagnostic(state.r, get_range(arg), builtins_err, arg.text)
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

    if state.r.has_errors(state.r.data) {
        return CheckerOutput{}
    }

    for &read_file, i in files {
        file := parsed.parsed_files.d[i]
        // state.file = FileRef{uint(i)}
        // TODO: Iterating over globals as a map is a big source of the
        // non-deterministic error ordering in this compiler
        for global_name, global in file {
            if get_builtin(global_name).value != nil {
                utils.diagnostic(
                    diagnostic_reporter,
                    utils.Range {
                        global.pos,
                        utils.to_debug_value(uint(len(global_name))),
                        &read_file,
                    },
                    builtins_err,
                    global_name,
                )
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

    if state.r.has_errors(state.r.data) {
        return CheckerOutput{}
    }

    func_ref := CheckedFuncRef{max(uint)}
    if func_name != "" {
        func_ref = get_global_function(
            &state,
            func_file,
            func_file,
            func_name,
            "\nTODO: Write hint",
        )
        if func_ref.index == max(uint) {
            assert(diagnostic_reporter.has_errors(diagnostic_reporter.data))
            return CheckerOutput{}
        }
    }

    assert(!diagnostic_reporter.has_errors(diagnostic_reporter.data))
    return CheckerOutput {
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
            utils.diagnostic(
                &state,
                utils.Pos{build_props.pos, FileRef{0}},
                "`build` is has generics\nExpected it to be a function without generics%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_value := state.global_values_without_generic[build_props.index]
        build_ref, build_is_func := build_value.v.value.(CheckedFuncRef)
        if !build_is_func {
            utils.diagnostic(
                &state,
                utils.Pos{build_props.pos, FileRef{0}},
                "`build` is a value other than a function\nExpected it to be a function%s",
                hint,
            )
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        build_info := get_type(state.types, build_value.v.type).(FuncType)
        if build_info.type != .ComptimeFunc {
            utils.diagnostic(
                &state,
                utils.Pos{build_props.pos, FileRef{0}},
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
            utils.unknown_pos,
            FileRef{0},
            "main",
            hint,
        )
        if !main_ok {
            return CheckerOutput{diagnostics_info = state.diagnostics_info}
        }
        main_info := get_type(state.types, state.checked_functions[main_ref.index].type).(FuncType)
        if main_info.type != .Normal {
            utils.diagnostic(&state, main_pos, "`main` has a marker\nExpected `main` to not have a marker")
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

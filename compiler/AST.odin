package compiler

import "../utils"

StructUnit :: struct {
    elements: []Unit,
}

StructType :: struct {
    m:     utils.KeyToIndex(string),
    // positions: utils.Multi(utils.Pos),
    types: utils.Multi(Type),
}

SumUnit :: struct {
    elements: []Unit,
}

SumType :: struct {
    // positions: utils.Multi(utils.Pos),
    payloads: map[u32]Maybe(Type),
}

IdentNode :: struct {
    segments:      #soa[]Ident,
    has_re_before: bool,
}

WholeNonNegativeNumber :: struct {
    digits: string,
}

DecimalNonNegativeNumber :: struct {
    integer_part:    string,
    fractional_part: string,
}

NonNegativeNumber :: union {
    WholeNonNegativeNumber,
    DecimalNonNegativeNumber,
}

Number :: struct {
    is_negated:     bool,
    absolute_value: NonNegativeNumber,
}

String :: distinct []string

Char :: distinct byte

Bool :: distinct bool

MarkedUnit :: struct {
    value:   ^Unit,
    markers: []TextAndPos,
}

Tuple :: struct {
    elements: []Unit,
}

UnitsInSquareBrackets :: struct {
    elements: []Unit,
}

FuncDefinitionRef :: struct {
    // an index into:
    // - `ParserState.function_defs`
    // - `ParserOutput.function_defs`
    index: uint,
}

CheckedFuncRef :: struct {
    // An index into:
    // - `Checked.checked_funcs`
    // - `CheckerState.checked_functions`
    index: uint,
}

// - A unit is a value or a type
// - There is no distinction between a value and a type in the AST because
//   there are cases where the parser cannot tell whether something is a value
//   or a type
// - For example, something like `HtmlElem[State].Text("hello world")`, where
//   `HtmlElem[State]` could be either:
//   - A value with a type like `{ Text: (String) -> Int }`, or;
//   - A sum type like `< Text{contents: String} >`

/*
InitialUnit :: union {
    Struct(Unit),
    SumType(Unit, struct {}),
    Tuple,
    FuncDefinitionRef,
    Ident,
    Number,
    String,
    Char,
    Bool,
    Import,
}
*/

TagUnit :: struct {
    tag: IdentToken,
    // value: ^UnitWithPos, // May be `nil`
}

UnitWithoutPos :: union #no_nil {
    StructUnit,
    SumUnit,
    Tuple,
    UnitsInSquareBrackets,
    FuncDefinitionRef,
    CallWithBrackets,
    CallWithSquareBrackets,
    HierarchyJoinedUnits,
    IdentNode,
    Number,
    String,
    Char,
    Bool,
    MarkedUnit,
    Import,
    TagUnit,
}

UnitWithPos :: struct {
    unit: UnitWithoutPos,
    pos:  utils.Pos,
}

Unit :: struct {
    pos:         utils.Pos,
    first_unit:  UnitWithoutPos,
    extra_units: []ExtraUnit,
}

ExtraUnit :: struct {
    join_method_pos: utils.Pos,
    join_method:     LeftToRightUnitJoinMethod,
    unit:            UnitWithPos,
}

// TODO: Maybe all unit join methods should be left to right?

LeftToRightUnitJoinMethod :: enum {
    Assign, // =
    Tilde, // ~
    PipeEquals, // |=
    Colon, // Used for array indexing (for example `my_array[start_index:end_index]`)
}

HierarchyUnitJoinMethod :: enum {
    // Prioraty 0
    BooleanAnd,
    BooleanOr,

    // Prioraty 1
    IsEqual,
    IsNotEqual,
    IsGreaterThan,
    IsLessThan,
    IsGreaterThanOrEqual,
    IsLessThanOrEqual,

    // Prioraty 2
    In,

    // Prioraty 3
    Append, // ::
    Concat, // ++
    StringConcat, // &
    Arrow, // Used for function types (for example `(String) -> U64`)

    // Prioraty 4
    Addition,
    Subtraction,
    Modulo,

    // Prioraty 5
    Multiplication,
    Division,
}

// Operations with higher prioraty (prioraty 5 is the highest prioraty) are executed first
// See https://en.wikipedia.org/wiki/Order_of_operations#Programming_languages
get_prioraty :: proc(join_method: HierarchyUnitJoinMethod) -> uint {
    switch join_method {
    case .BooleanAnd, .BooleanOr:
        return 0
    case .IsEqual,
         .IsNotEqual,
         .IsGreaterThan,
         .IsLessThan,
         .IsGreaterThanOrEqual,
         .IsLessThanOrEqual:
        return 1
    case .In:
        return 2
    case .Append, .Concat, .StringConcat, .Arrow:
        return 3
    case .Subtraction, .Addition, .Modulo:
        return 4
    case .Division, .Multiplication:
        return 5
    }
    panic("Unreachable")
}

HierarchyJoinedUnits :: struct {
    join_method: HierarchyUnitJoinMethod,
    unit0:       ^Unit,
    unit1:       ^Unit,
}

Call :: struct {
    unit_being_called: ^UnitWithPos,
    args:              []Unit,
}

CallWithBrackets :: distinct Call // A(B, C, D)
CallWithSquareBrackets :: distinct Call // A[B, C, D]

Iterator :: union {
    Unit,
    NumericIterator,
}

NumericIteratorType :: enum {
    IncludeEndValue,
    ExcludeEndValue,
}

NumericIterator :: struct {
    start: Unit,
    end:   Unit,
    step:  ^Unit, // nil if the step is 1
    type:  NumericIteratorType,
}

/*
IdentAndIndex :: struct {
    ident: string,
    index: uint,
}
*/

TextAndPos :: struct {
    text: string,
    pos:  utils.Pos,
}

Ident :: struct {
    ident:             string,
    pos:               utils.Pos,
    has_dollar_at_end: bool,
}

ConditionControlledLoop :: struct {
    type:      enum {
        WhileLoop,
        DoWhileLoop,
    },
    condition: Unit,
    body:      []Statement,
}

ForInLoop :: struct {
    label:     TextAndPos,
    // At most there can be 3 variables:
    // - The iteration the for loop is on
    // - The key of the thing being iterated over
    // - The value of the thing being iterated over
    variables: [3]TextAndPos,
    iterator:  Iterator,
    body:      []Statement,
}

IfElseStatement :: struct {
    condition:  Unit,
    if_block:   []Statement,
    else_block: []Statement,
}

MatchBranch :: struct {
    label: Unit,
    body:  []Statement,
}

MatchStatement :: struct {
    value:    Unit,
    branches: []MatchBranch,
}

ReturnStatement :: distinct []Unit
YieldStatement :: distinct []Unit
LoopControlFlow :: struct {
    label: TextAndPos,
    kind:  LoopControlFlowKind,
}
UnreachableStatement :: struct {}

Statement :: struct {
    position: utils.Pos,
    value:    union {
        Unit,
        ConditionControlledLoop,
        ForInLoop,
        IfElseStatement,
        ReturnStatement,
        YieldStatement,
        MatchStatement,
        LoopControlFlow,
        UnreachableStatement,
    },
}

FunctionArg :: struct {
    name:       Ident,
    value_type: Unit,
}

FunctionDefinition :: struct {
    inputs: #soa[]FunctionArg,
    output: ^Unit, // if the function has no output, then `output` is `nil`
    body:   []Statement,
}

//ComponentDefinition :: struct {
//    inputs: []NameAndType,
//    body:   []Statement,
//}

//File :: struct {
//    imports: []Import,
//    // TODO: Store the map order to maintain order when formatting is implemented
//    globals: map[string]Global,
//}
/*
print_type :: proc(s: ^TreePrinterState, type: Type) {
    list_item(s, "Type at character index %d:", type.pos)
    print_type_value(s, type.type)
}

print_type_value :: proc(s: ^TreePrinterState, type: TypeValue) {
    list_item(s, "todo")
}

print_name_and_type_list :: proc(s: ^TreePrinterState, label: string, list: []NameAndType) {
    list_item(s, label)
    for name_and_type, index in list {
        list_item(s, "`%s`:", name_and_type.name)
        print_type(s, name_and_type.type)
    }
}

print_argument_list :: proc(s: ^TreePrinterState, label: string, list: []FunctionArg) {
    list_item(s, label)
    for arg, index in list {
        list_item(s, "`%s`:", arg.name)
        switch arg.arg_type {
        case .Normal:
            list_item(s, "normal type")
        case .Mutable:
            list_item(s, "mutable type")
        case .RemovedFromStack:
            list_item(s, "removed from stack type")
        }
        print_type(s, arg.value_type)
    }
}

print_output_list :: proc(s: ^TreePrinterState, label: string, list: []FunctionOutput) {
    list_item(s, label)
    for output, index in list {
        list_item(s, "`%s`:", output.name)
        switch output.output_type {
        case .Normal:
            list_item(s, "normal type")
        case .AllocatedOntoStack:
            list_item(s, "allocated onto stack type")
        }
        print_type(s, output.value_type)
    }
}

debug_call :: proc(funcs: []FunctionDefinition, c: Call) {
    utils.debug_nesting += 1
    utils.debug("TODO")
    // debug_unit(funcs, c.unit_being_called)
    for arg, i in c.args {
        utils.debug("arg %d", i)
        utils.debug_nesting += 1
        debug_unit(funcs, arg)
        utils.debug_nesting -= 1
    }
    utils.debug_nesting -= 1
}

debug_unit :: proc(funcs: []FunctionDefinition, unit: Unit) {
    utils.debug("value at %v", unit.pos)
    utils.debug_nesting += 1
    switch v in unit.first_unit {
    case UnitsInSquareBrackets:
        panic("TODO")
    case StructUnit:
        panic("TODO")
    case SumUnit:
        panic("TODO")
    case Number:
        utils.debug("is_negated: %v", v.is_negated)
        utils.debug("absolute_value: %v", v.absolute_value)
    case Char:
        panic("TODO")
    case MarkedUnit:
        panic("TODO")
    case Import:
        panic("TODO")
    case Bool:
        if v {
            utils.debug("The boolean literal `true`")
        } else {
            utils.debug("The boolean literal `false`")
        }
    case FuncDefinitionRef:
        utils.debug("value is a function definition (TODO)")
    // print_argument_list(s, "inputs:", funcs[v].inputs)
    // print_output_list(s, "outputs:", funcs[v].outputs)
    // print_block(s, funcs, funcs[v].body, "body:")
    case Tuple:
        utils.debug("tuple:")
        for elem in v.elements {
            debug_unit(funcs, elem)
        }
    case CallWithBrackets:
        utils.debug("call with brackets")
        debug_call(funcs, Call(v))
    case CallWithSquareBrackets:
        utils.debug("call with square brackets")
        debug_call(funcs, Call(v))
    case CallWithFrontedSquareBrackets:
        utils.debug("call with fronted square brackets")
        debug_call(funcs, Call(v))
    case HierarchyJoinedUnits:
        utils.debug("joined units")
        utils.debug_nesting += 1
        utils.debug("join method: %v", v.join_method)
        debug_unit(funcs, v.unit0^)
        debug_unit(funcs, v.unit1^)
        utils.debug_nesting -= 1
    case IdentNode:
        utils.debug("ident")
        utils.debug_nesting += 1
        for segment in v.segments {
            utils.debug("%q", segment.ident)
        }
        utils.debug_nesting -= 1
    case String:
        utils.debug("string: %v", v)
    }
    for _ in unit.extra_units {
        utils.debug("TODO: Handle extra unit")
    }
    utils.debug_nesting -= 1
}
*/

/*
print_block :: proc(
    s: ^TreePrinterState,
    funcs: []FunctionDefinition,
    block: []Statement,
    label: string,
) {
    list_item(s, label)
    for statement, index in block {
        list_item(s, "statement %d at character index %d", index, statement.position)
        #partial switch v in statement.value {
        case ForInLoop:
            list_item(s, "for in loop:")
            {
                list_item(s, "variables:")
                print_variable :: proc(s: ^TreePrinterState, var: IdentAndPos) {
                    list_item(s, "`%s` at character index %d", var.ident, var.pos)
                }
                print_variable(s, v.variables[0])
                print_variable(s, v.variables[1])
                print_variable(s, v.variables[2])
            }
            switch iter in v.iterator {
            case NumericIterator:
                list_item(s, "numeric iterator:")
                {list_item(s, "type: %v", iter.type)}
                {list_item(s, "start: %v", iter.start)}
                {list_item(s, "end: %v", iter.end)}
                {list_item(s, "step: %v", iter.step)}
            case Value:
                print_value(s, funcs, iter, "value iterator:")
            }
            print_block(s, funcs, v.body, "body")
        case DoWhileLoop:
            list_item(s, "Do while loop:")
            print_block(s, funcs, v.body, "loop body:")
            print_value(s, funcs, v.condition, "loop condition:")
        case WhileLoop:
            list_item(s, "While loop:")
            print_value(s, funcs, v.condition, "loop condition:")
            print_block(s, funcs, v.body, "loop body:")
        case ReturnStatement:
            list_item(s, "return statement")
            for v, i in v {
                print_value(s, funcs, v, "value %d:", i)
            }
        case YieldStatement:
            list_item(s, "yield statement")
            for v, i in v {
                print_value(s, funcs, v, "value %d:", i)
            }
        case IfElseStatement:
            list_item(s, "if else statement")
            print_value(s, funcs, v.condition, "condition:")
            print_block(s, funcs, v.if_block, "if block:")
            print_block(s, funcs, v.else_block, "else block:")
        case FunctionCall:
            list_item(s, "function call")
            print_value(s, funcs, v.function^, "function value")
            for arg, index in v.args {
                print_value(s, funcs, arg, "value %d", index)
            }
        case:
            list_item(s, "todo")

        }
    }
}

print_ast :: proc(
    imports: []Import,
    globals: map[string]ParsedGlobal,
    funcs: []FunctionDefinition,
    global_types: []TypeValue,
) {
    s: TreePrinterState

    {
        list_item(&s, "%d imports:", len(imports))
        for i, index in imports {
            list_item(&s, "import %d", index)
            for component, index in i.components {
                list_item(&s, "component %d: %s", index, component)
            }
        }
    }

    {
        list_item(&s, "%d globals:", len(globals))
        for name, global in globals {
            switch value in global.value {
            case uint:
                list_item(&s, "global type called `%s` at character index %d:", name, global.pos)
                print_type_value(&s, global_types[value])
            case Value:
                print_value(
                    &s,
                    funcs,
                    value,
                    "global value called `%s` at character index %d:",
                    name,
                    global.pos,
                )
            }
        }
    }
}

*/

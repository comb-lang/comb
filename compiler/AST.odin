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
    ident:         IdentAndPos,
    has_re_before: bool,
}

WholeNonNegativeNumber :: struct {
    digits: string,
}

/*
DecimalNonNegativeNumber :: struct {
    integer_part:    string,
    fractional_part: string,
}

NonNegativeNumber :: union {
    WholeNonNegativeNumber,
    DecimalNonNegativeNumber,
}
*/

String :: distinct string

Char :: distinct byte

Bool :: distinct bool

Marker :: struct {
    marker: TextAndPos,
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

UnitSegmentContents :: union #no_nil {
    StructUnit,
    SumUnit,
    Tuple,
    UnitsInSquareBrackets,
    FuncDefinitionRef,
    IdentNode,
    WholeNonNegativeNumber,
    String,
    Char,
    Bool,
    Marker,
    Import,
    UnitJoinMethod,
}

UnitSegment :: struct {
    range:    utils.Range,
    contents: UnitSegmentContents,
}

Unit :: struct {
    first: UnitSegment,
    rest:  []UnitSegment,
}

get_segment :: proc(unit: Unit, segment_index: uint, loc := #caller_location) -> UnitSegment {
    when ODIN_DEBUG {
        utils.call(loc, "get_segment", "")
    }
    return segment_index == 0 ? unit.first : unit.rest[segment_index - 1]
}

is_last_segment :: proc(unit: Unit, segment_index: uint) -> bool {
    assert(segment_index <= len(unit.rest))
    return segment_index == len(unit.rest)
}

is_segment :: proc(unit: Unit, segment_index: uint) -> bool {
    return segment_index <= len(unit.rest)
}

// Operations with higher prioraty (prioraty 5 is the highest prioraty) are executed first
// See https://en.wikipedia.org/wiki/Order_of_operations#Programming_languages
UnitJoinMethod :: enum {
    // Prioraty 0
    Assign, // =
    Tilde, // ~
    PipeEquals, // |=
    Colon, // Used for array indexing (for example `my_array[start_index:end_index]`)

    // Prioraty 1
    BooleanAnd,
    BooleanOr,

    // Prioraty 2
    IsEqual,
    IsNotEqual,
    IsGreaterThan,
    IsLessThan,
    IsGreaterThanOrEqual,
    IsLessThanOrEqual,

    // Prioraty 3
    In,

    // Prioraty 4
    Append, // ::
    Concat, // ++
    StringConcat, // &
    Arrow, // Used for function types (for example `(String) -> U64`)

    // Prioraty 5
    Addition,
    Subtraction,
    Modulo,

    // Prioraty 6
    Multiplication,
    Division,

    // Prioraty 7
    Dot,
}

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
    has_dollar_at_end: bool,
}

IdentAndPos :: struct {
    ident:             string,
    has_dollar_at_end: bool,
    pos:               utils.Pos,
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

ReturnStatement :: struct {
    range: utils.Range,
    args:  []Unit,
}
YieldStatement :: struct {
    range: utils.Range,
    args:  []Unit,
}
LoopControlFlow :: struct {
    range: utils.Range,
    label: TextAndPos,
    kind:  LoopControlFlowKind,
}
UnreachableStatement :: struct {
    range: utils.Range,
}

Statement :: union {
    Unit,
    ConditionControlledLoop,
    ForInLoop,
    IfElseStatement,
    ReturnStatement,
    YieldStatement,
    MatchStatement,
    LoopControlFlow,
    UnreachableStatement,
}

FunctionArg :: struct {
    name:       IdentAndPos,
    value_type: Unit,
}

FunctionDefinition :: struct {
    inputs: #soa[]FunctionArg,
    output: Maybe(Unit), // if the function has no output, then `output` is `nil`
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

debug_unit_segment :: proc(funcs: []FunctionDefinition, segment: UnitSegment) {
    utils.debug("segment at %v", segment.range)
    utils.debug_nesting += 1
    switch v in segment.contents {
    case StructUnit:
        panic("TODO")
    case SumUnit:
        panic("TODO")
    case WholeNonNegativeNumber:
        utils.debug("digits: %s", v.digits)
    case Char:
        panic("TODO")
    case Marker:
        utils.debug("marker: %s", v.marker)
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
    case UnitJoinMethod:
        utils.debug("unit join method: %v", v)
    case Tuple:
        utils.debug("tuple:")
        for elem in v.elements {
            debug_unit(funcs, elem)
        }
    case UnitsInSquareBrackets:
        utils.debug("units in square brackets:")
        for elem in v.elements {
            debug_unit(funcs, elem)
        }
    case IdentNode:
        utils.debug("Ident")
        utils.debug("b")
        utils.debug("b")

        utils.debug("ident: `%s`", v.ident.ident)
        utils.debug("b")
    case String:
        utils.debug("string: %s", v)
    }
    utils.debug_nesting -= 1
}

debug_unit :: proc(funcs: []FunctionDefinition, unit: Unit) {
    for i: uint = 0; is_segment(unit, i); i += 1 {
        segment := get_segment(unit, i)
        debug_unit_segment(funcs, segment)
    }
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

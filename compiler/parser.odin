#+feature dynamic-literals
package compiler

import "../utils"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:path/filepath"

plain_ident_base :: "n identifier with one segment and no `$` sign at the end"
plain_ident_capitalised :: "A" + plain_ident_base
plain_ident_normal :: "a" + plain_ident_base

@(private = "file")
expect_text_and_pos :: "Expected " + plain_ident_normal

get_text_and_pos_from_ident :: proc(
    r: utils.DiagnosticReporter,
    t: #soa[]Ident,
) -> Maybe(TextAndPos) {
    if len(t) != 1 || t[0].has_dollar_at_end {
        utils.diagnostic(r, t[0].pos, expect_text_and_pos)
        return nil
    }
    return TextAndPos{t[0].ident, t[0].pos}
}

get_text_and_pos_from_unit_with_pos :: proc(
    r: utils.DiagnosticReporter,
    u: UnitWithPos,
) -> Maybe(TextAndPos) {
    ident, is_ident := u.unit.(IdentNode)
    if !is_ident || ident.has_re_before {
        utils.diagnostic(r, u.pos, expect_text_and_pos)
        return nil
    }
    return get_text_and_pos_from_ident(r, ident.segments)
}

get_text_and_pos_from_unit :: proc(r: utils.DiagnosticReporter, u: Unit) -> Maybe(TextAndPos) {
    if len(u.extra_units) == 0 {
        return get_text_and_pos_from_unit_with_pos(r, UnitWithPos{u.first_unit, u.pos})
    }
    utils.diagnostic(r, u.pos, expect_text_and_pos)
    return nil
}

get_file_index :: proc(
    files: []utils.CompilerFile,
    ref: ^utils.CompilerFile,
    loc := #caller_location,
) -> int {
    // utils.print_call(loc, "get_file_index")
    return mem.ptr_sub(ref, &files[0])
}

ParsingContext :: struct {
    pos:  utils.Pos,
    kind: enum {
        ValuesInCurlyBraces,
        Block,
        ValuesInBars,
        ValuesInBrackets,
        ValuesInSquareBrackets,
    },
}

// The index of the first unparsed file is always `ParserState.file_ref.index + 1`
ParserState :: struct {
    a:                              ^utils.Arena,
    // Updated every time the parser starts parsing a different file
    using tokenizer_state:          TokenizerState,

    // Grows and shrinks as the nesting increases and decreases
    parser_context:                 []ParsingContext,

    // Grow as the project is parsed
    r:                              utils.DiagnosticReporter,
    files_cache:                    ^utils.FilesCache,
    // len(parsed_files) == get_file_index(files_cache.files, tokenizer_state.last_token_pos.file) + 1
    parsed_files:                   utils.Multi(map[string]ParsedGlobal),
    global_values_without_generics: [dynamic]GlobalValueWithoutGeneric,
    global_values_with_generics:    [dynamic]GlobalValueWithGeneric,
    function_defs:                  [dynamic]FunctionDefinition,
}

/*
// Does not include the `{`
parse_struct :: proc(s: ^ParserState) -> (OldStructUnit, bool) {
    utils.append_dynamic(&s.parser_context, ParsingContext{s.last_token_pos, .StructType})
    defer utils.pop_dynamic(&s.parser_context)
    out := OldStructUnit {
        utils.make_key_to_index(s.a, utils.KeyToIndex(string)),
        utils.arena_make_multi(s.a, utils.Multi(utils.Pos), 0, resizable = true),
        utils.arena_make_multi(s.a, utils.Multi(Unit), 0, resizable = true),
    }
    defer {
        utils.fix_key_to_index(out.m)
        utils.fix_resizable_multi(out.types)
        utils.fix_resizable_multi(out.positions)
    }
    for {
        field: TextAndPos = ---
        get_next_token(s, true)
        wrong_token :: proc(s: ^ParserState) -> (OldStructUnit, bool) {
            utils.clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                plain_ident_capitalised,
                "`}`",
            )
            wrong_token_err(s)
            return OldStructUnit{}, false
        }
        #partial switch token in s.last_token {
        case CloseBraceToken:
            return out, true
        case IdentToken:
            if len(token) != 1 || token[0].has_dollar_at_end {
                return wrong_token(s)
            }
            field = TextAndPos{token[0].ident, token[0].pos}
        case:
            return wrong_token(s)
        }

        get_next_token(s, false)
        #partial switch token in s.last_token {
        case:
            utils.clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                fmt.aprintf("`:` to specify the type of the `%s` field", field.text),
            )
            wrong_token_err(s)
            return OldStructUnit{}, false
        case ColonToken:
        }

        get_next_token(s, true)
        utils.append_dynamic(&s.parser_context, ParsingContext{s.last_token_pos, .StructFieldType})
        defer utils.pop_dynamic(&s.parser_context)
        parsed, parsed_ok := parse_unit(s)
        if !parsed_ok {
            return OldStructUnit{}, false
        }
        i, result := utils.lookup_or_insert(&out.m, field.text, utils.string_to_index_procs)
        if result == .LookedUp {
            utils.diagnostic(
                s.r,
                field.pos,
                "There is already a field called `%s` defined in this struct at %v",
                field.text,
                out.positions.d[i.index],
            )
            return OldStructUnit{}, false
        }
        utils.resize_multi(&out.positions, len(out.m.keys))
        utils.resize_multi(&out.types, len(out.m.keys))
        out.positions.d[i.index] = field.pos
        out.types.d[i.index] = parsed

        #partial switch _ in s.last_token {
        case:
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`,` to add a new field to the struct",
                "`}`",
            )
            wrong_token_err(s)
            return OldStructUnit{}, false
        case CommaToken:
        case CloseBraceToken:
            return out, true
        }
    }
}
*/

parse_non_negative_number :: proc(s: ^ParserState, whole_part: string) -> NonNegativeNumber {
    get_next_token(s, true)
    symbols, is_symbols := s.last_token.(SymbolsToken)
    if !is_symbols || symbols != "." {
        utils.append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`.` to create a decimal number",
        )
        return WholeNonNegativeNumber{whole_part}
    }
    get_next_token(s, true)
    digits, is_digits := s.last_token.(DigitsToken)
    if !is_digits {
        utils.append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "some digits for the fractional part of the number",
        )
        wrong_token_err(s)
        return nil
    }
    get_next_token(s, true)
    return DecimalNonNegativeNumber{whole_part, string(digits)}
}

Failure :: struct {}
NothingToParse :: struct {}

@(private = "file")
MaybeParseInitialUnitResult :: union #no_nil {
    UnitWithoutPos,
    NothingToParse, // there wasn't an initial unit to parse
    Failure,
}

@(private = "file")
maybe_parse_initial_unit :: proc(
    s: ^ParserState,
    loc := #caller_location,
) -> MaybeParseInitialUnitResult {
    utils.call(loc, "maybe_parse_initial_unit", "")
    e :: proc(s: ^ParserState) -> MaybeParseInitialUnitResult {
        utils.append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`true`",
            "`false`",
            "`fn` to create a lambda function value",
            "`(` to create a tuple of values or types",
            "a digits token",
            "a string literal",
            "a character literal",
            "a marker token (# followed by one or more alphanumerics)",
            "a name",
            "`|` to create a sum type",
            "`[` to create an array type",
            "`{` to create a struct type",
            "`re`",
            // "`dynamic` for a dynamic type",
        )
        return NothingToParse{}
    }
    #partial switch token in s.last_token {
    case:
        return e(s)

    case ColonToken:
        get_next_token(s, false)
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident {
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "an identifier for the tag name",
            )
            wrong_token_err(s)
            return Failure{}
        }
        get_next_token(s, true)
        return TagUnit{ident}
    /*
        pos := s.last_token_pos
        switch unit in maybe_parse_initial_unit(s) {
        case:
            panic("Unreachable")
        case Failure:
            return Failure{}
        case NothingToParse:
            return TagUnit{ident, nil}
        case UnitWithoutPos:
            return TagUnit{ident, new_clone(UnitWithPos{unit, pos})}
        }
        */

    case ImportToken:
        get_next_token(s, false)
        path, is_string_literal := s.last_token.(StringToken)
        if !is_string_literal {
            utils.clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "A string literal",
            )
            wrong_token_err(s)
            return Failure{}
        }
        joined, join_err := filepath.join(
            []string{s.last_token_pos.file.dir_path, string(path)},
            context.allocator,
        )
        if join_err != nil {
            utils.diagnostic(s.r, s.last_token_pos, "Failed to join filepath: %v", join_err)
            return Failure{}
        }
        file_ref, read_err := utils.read_file(s.files_cache, joined)
        if read_err != nil {
            utils.diagnostic(s.r, s.last_token_pos, "Failed to read `%s`: %#v", joined, read_err)
            return Failure{}
        }
        get_next_token(s, true)
        return UnitWithoutPos(Import{file_ref})

    case OpenBracketToken:
        utils.append_dynamic(
            &s.parser_context,
            ParsingContext{s.last_token_pos, .ValuesInBrackets},
        )
        defer utils.pop_dynamic(&s.parser_context)
        elements, ok := parse_units_until(s, is_close_bracket, "`)` to end the tuple").([]Unit)
        if !ok {
            return Failure{}
        }
        get_next_token(s, true)
        return UnitWithoutPos(Tuple{elements})

    // case DynamicToken:
    //     get_next_token(state, false)
    //     type, other_possible_tokens, ok := parse_type(state)
    //     if !ok {
    //         return Unit{}, nil, false
    //     }
    //     return Unit{type_pos, DynamicUnit(new_clone(type))}, other_possible_tokens, true

    case OpenBraceToken:
        utils.append_dynamic(
            &s.parser_context,
            ParsingContext{s.last_token_pos, .ValuesInCurlyBraces},
        )
        defer utils.pop_dynamic(&s.parser_context)
        elements, ok := parse_units_until(s, is_close_brace, "`}` to end the struct").([]Unit)
        if !ok {
            return Failure{}
        }
        get_next_token(s, true)
        return UnitWithoutPos(StructUnit{elements})

    case BarToken:
        utils.append_dynamic(&s.parser_context, ParsingContext{s.last_token_pos, .ValuesInBars})
        defer utils.pop_dynamic(&s.parser_context)
        elems, elems_ok := parse_units_until(s, is_bar_token, "`|`").([]Unit)
        if !elems_ok {
            return Failure{}
        }
        get_next_token(s, true)
        return UnitWithoutPos(SumUnit{elems})
    /*
        sum_type := SumUnit {
            utils.make_key_to_index(s.a, utils.KeyToIndex(string)),
            utils.arena_make_multi(s.a, utils.Multi(utils.Pos), 0, resizable = true),
            utils.arena_make_multi(s.a, utils.Multi(Unit), 0, resizable = true),
        }
        defer {
            utils.fix_key_to_index(sum_type.m)
            utils.fix_resizable_multi(sum_type.payloads)
            utils.fix_resizable_multi(sum_type.positions)
        }
        loop: for {
            get_next_token(s, true)
            utils.clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                plain_ident_capitalised,
                "`>`",
            )
            #partial switch token2 in s.last_token {
            case:
                wrong_token_err(s)
                return Failure{}
            case CloseAngleBracketToken:
                break loop
            case IdentToken:
                if len(token2) != 1 || token2[0].has_dollar_at_end {
                    wrong_token_err(s)
                    return Failure{}
                }
                variant_name := token2[0]
                variant_payload := OldStructUnit{}
                get_next_token(s, true)
                _, has_payload := s.last_token.(OpenBraceToken)
                if has_payload {
                    variant_payload, has_payload = parse_struct(s)
                    if !has_payload {
                        return Failure{}
                    }
                    get_next_token(s, false)
                }
                i, result := utils.lookup_or_insert(
                    &sum_type.m,
                    variant_name.ident,
                    utils.string_to_index_procs,
                )
                if result == .LookedUp {
                    utils.diagnostic(
                        s.r,
                        variant_name.pos,
                        "There is already a variant called `%s` in this sum type at %v",
                        variant_name.ident,
                        sum_type.positions.d[i.index],
                    )
                    return Failure{}
                }
                utils.resize_multi(&sum_type.positions, len(sum_type.m.keys))
                utils.resize_multi(&sum_type.payloads, len(sum_type.m.keys))
                sum_type.positions.d[i.index] = variant_name.pos
                sum_type.payloads.d[i.index] = variant_payload
                #partial switch _ in s.last_token {
                case:
                    utils.clear_dynamic(&s.last_token_descriptions_of_other_possible_tokens)
                    utils.append_dynamic_elems(
                        &s.last_token_descriptions_of_other_possible_tokens,
                        "`,`",
                        "`>`",
                    )
                    if !has_payload {
                        utils.append_dynamic(
                            &s.last_token_descriptions_of_other_possible_tokens,
                            fmt.aprintf(
                                "`{` to add a payload to the `%s` variant",
                                variant_name.ident,
                            ),
                        )
                    }
                    wrong_token_err(s)
                    return Failure{}
                case CommaToken:
                case CloseAngleBracketToken:
                    break loop
                }
            }
        }
        get_next_token(s, true)
        return sum_type
        */

    case OpenSquareBracketToken:
        utils.append_dynamic(
            &s.parser_context,
            ParsingContext{s.last_token_pos, .ValuesInSquareBrackets},
        )
        defer utils.pop_dynamic(&s.parser_context)
        elems, elems_ok := parse_units_until(s, is_close_square_bracket, "`]`").([]Unit)
        if !elems_ok {
            return Failure{}
        }
        get_next_token(s, true)
        return UnitWithoutPos(UnitsInSquareBrackets{elems})
    /*
        // OLD (creating arrays like []ItemType(elems...))
        unit_pos := s.last_token_pos
        switch unit in maybe_parse_initial_unit(s) {
        case:
            panic("Unreachable")
        case Failure:
            return Failure{}
        case NothingToParse:
            return UnitsInSquareBrackets{elems}
        case UnitWithoutPos:
            // TODO: Update the syntax so that this exception to the parsed order of operations is not necersarry
            if _, is_open_square_bracket := s.last_token.(OpenSquareBracketToken);
               is_open_square_bracket {
                args2, args2_ok := parse_units_until(s, is_close_square_bracket, "`]`").([]Unit)
                if !args2_ok {
                    return Failure{}
                }
                get_next_token(s, true)
                return CallWithFrontedSquareBrackets {
                    new_clone(
                        UnitWithPos {
                            CallWithSquareBrackets{new_clone(UnitWithPos{unit, unit_pos}), args2},
                            unit_pos,
                        },
                    ),
                    elems,
                }
            }
            return CallWithFrontedSquareBrackets{new_clone(UnitWithPos{unit, unit_pos}), elems}
        }
        */
    case IdentToken:
        get_next_token(s, true)
        return IdentNode{token, false}

    case ReToken:
        get_next_token(s, false)
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident {
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "an identifier",
            )
            wrong_token_err(s)
            return Failure{}
        }
        get_next_token(s, true)
        return IdentNode{ident, true}

    case MarkerToken:
        markers := [dynamic]TextAndPos{{string(token), s.last_token_pos}}
        for {
            get_next_token(s, false)
            marker, is_marker := s.last_token.(MarkerToken)
            if !is_marker {
                break
            }
            append_elem(&markers, TextAndPos{string(marker), s.last_token_pos})
        }
        val_pos := s.last_token_pos
        val, ok := parse_initial_unit(s).(UnitWithoutPos)
        if !ok {
            return Failure{}
        }
        return UnitWithoutPos(MarkedUnit{new_clone(Unit{val_pos, val, nil}), markers[:]})

    case TrueToken:
        get_next_token(s, true)
        return UnitWithoutPos(Bool(true))

    case FalseToken:
        get_next_token(s, true)
        return UnitWithoutPos(Bool(false))

    case DigitsToken:
        number := parse_non_negative_number(s, string(token))
        if number == nil {
            return Failure{}
        }
        return UnitWithoutPos(Number{false, number})

    case SymbolsToken:
        if token != "-" {
            return e(s)
        }
        get_next_token(s, true)
        digits, is_digits := s.last_token.(DigitsToken)
        if !is_digits {
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "A digits token",
            )
            wrong_token_err(s)
            return Failure{}
        }
        number := parse_non_negative_number(s, string(digits))
        if number == nil {
            return Failure{}
        }
        return UnitWithoutPos(Number{true, number})

    case StringToken:
        strings := [dynamic]string{string(token)}
        for {
            get_next_token(s, true)
            #partial switch token2 in s.last_token {
            case:
                utils.append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "a string token",
                )
                return UnitWithoutPos(String(strings[:]))
            case StringToken:
                append_elem(&strings, string(token2))
            }
        }

    case CharToken:
        get_next_token(s, true)
        return UnitWithoutPos(Char(token))

    case FnToken:
        func, ok := parse_function_def(s)
        if !ok {
            return Failure{}
        }
        get_next_token(s, true)
        out := FuncDefinitionRef{uint(len(s.function_defs))}
        append_elem(&s.function_defs, func)
        return out

    }
}

parse_initial_unit :: proc(s: ^ParserState, loc := #caller_location) -> Maybe(UnitWithoutPos) {
    utils.call(loc, "parse_initial_unit", "")
    switch unit in maybe_parse_initial_unit(s) {
    case Failure:
        return nil
    case NothingToParse:
        wrong_token_err(s)
        return nil
    case UnitWithoutPos:
        return unit
    case:
        panic("Unreachable")
    }
}

parse_units_until :: proc(
    s: ^ParserState,
    is_end: proc(t: TokenContents) -> bool,
    end_description: string,
) -> Maybe([]Unit) {
    units := [dynamic]Unit{}
    for {
        get_next_token(s, true)
        if is_end(s.last_token) {
            return units[:]
        }
        utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, end_description)
        unit, ok := parse_unit(s)
        if !ok {
            return nil
        }
        append_elem(&units, unit)

        if is_end(s.last_token) {
            return units[:]
        }
        #partial switch token in s.last_token {
        case:
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                end_description,
                "`,`",
            )
            wrong_token_err(s)
            return nil
        case CommaToken:
            continue
        }
    }
}

create_joined_unit :: proc(
    join_method: HierarchyUnitJoinMethod,
    unit0: Unit,
    unit1: ^Unit,
) -> UnitWithoutPos {
    joined_values, is_joined_values := unit1.first_unit.(HierarchyJoinedUnits)
    if is_joined_values && get_prioraty(joined_values.join_method) <= get_prioraty(join_method) {
        val0 := create_joined_unit(join_method, unit0, joined_values.unit0)
        return HierarchyJoinedUnits {
            joined_values.join_method,
            new_clone(Unit{unit0.pos, val0, nil}),
            joined_values.unit1,
        }
    }
    return HierarchyJoinedUnits{join_method, new_clone(unit0), unit1}
}

// Returns `nil` on failure
parse_unit_with_pos :: proc(s: ^ParserState, loc := #caller_location) -> Maybe(UnitWithoutPos) {
    utils.call(loc, "parse_unit_without_pos", "")
    pos := s.last_token_pos
    unit, unit_ok := parse_initial_unit(s).(UnitWithoutPos)
    if !unit_ok {
        return nil
    }

    // Parse possible calls
    loop: for {
        #partial switch token in s.last_token {
        case:
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                // TODO: pretty print the unit being called
                "`(` to create a bracket call",
                "`[` to create a square bracket call",
            )
            break loop
        case OpenBracketToken:
            args, args_ok := parse_units_until(s, is_close_bracket, "`)`").([]Unit)
            if !args_ok {
                return nil
            }
            unit = CallWithBrackets{new_clone(UnitWithPos{unit, pos}), args}
            get_next_token(s, true)
        case OpenSquareBracketToken:
            args, args_ok := parse_units_until(s, is_close_square_bracket, "`]`").([]Unit)
            if !args_ok {
                return nil
            }
            unit = CallWithSquareBrackets{new_clone(UnitWithPos{unit, pos}), args}
            get_next_token(s, true)
        }
    }

    // Parse possible arithmetic
    utils.append_dynamic(
        &s.last_token_descriptions_of_other_possible_tokens,
        "A hierarchical value joiner (`and`, `or`, `==`, `!=`, `>`, `>=`, `<`, `<=`, `*`, `/`, `+`, `-`, `%`, `::`, `:`, `->`, `in`, `++`, `&`)",
    )
    value_type: HierarchyUnitJoinMethod
    #partial switch token in s.last_token {
    case:
        return unit
    case InToken:
        value_type = .In
    case AndToken:
        value_type = .BooleanAnd
    case ColonColonToken:
        value_type = .Append
    case OrToken:
        value_type = .BooleanOr
    case OpenAngleBracketToken:
        value_type = .IsLessThan
    case LessThanOrEqualToken:
        value_type = .IsLessThanOrEqual
    case CloseAngleBracketToken:
        value_type = .IsGreaterThan
    case GreaterThanOrEqualToken:
        value_type = .IsGreaterThanOrEqual
    case ArrowToken:
        value_type = .Arrow
    case SymbolsToken:
        switch token {
        case:
            return unit
        case "==":
            value_type = .IsEqual
        case "!=":
            value_type = .IsNotEqual
        case "*":
            value_type = .Multiplication
        case "/":
            value_type = .Division
        case "+":
            value_type = .Addition
        case "++":
            value_type = .Concat
        case "&":
            value_type = .StringConcat
        case "-":
            value_type = .Subtraction
        case "%":
            value_type = .Modulo
        }
    }
    get_next_token(s, true)
    next_value_pos := s.last_token_pos
    next_value, ok := parse_unit_with_pos(s).(UnitWithoutPos)
    if !ok {
        return nil
    }
    return create_joined_unit(
        value_type,
        Unit{pos, unit, nil},
        new_clone(Unit{next_value_pos, next_value, nil}),
    )
}

// Returns `Unit{}, false` on failure
parse_unit :: proc(s: ^ParserState) -> (Unit, bool) {
    pos := s.last_token_pos
    first_unit, first_unit_ok := parse_unit_with_pos(s).(UnitWithoutPos)
    if !first_unit_ok {
        return Unit{}, false
    }
    extra_units := utils.arena_make(s.a, []ExtraUnit, 0, resizable = true)
    defer utils.fix_resizable_dynamic(extra_units)
    for {
        join_method_pos := s.last_token_pos
        utils.append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "A left to right value joiner (`~`, `=`, `|=`)",
        )
        join_method: LeftToRightUnitJoinMethod
        #partial switch v in s.last_token {
        case AssignToken:
            join_method = .Assign
        case SymbolsToken:
            if v != "~" {
                return Unit{pos, first_unit, extra_units}, true
            }
            join_method = .Tilde
        case PipeEqualsToken:
            join_method = .PipeEquals
        case ColonToken:
            join_method = .Colon
        case:
            return Unit{pos, first_unit, extra_units}, true
        }
        get_next_token(s, true)
        extra_unit_pos := s.last_token_pos
        extra_unit, extra_unit_ok := parse_unit_with_pos(s).(UnitWithoutPos)
        if !extra_unit_ok {
            return Unit{}, false
        }
        utils.append_dynamic(
            &extra_units,
            ExtraUnit{join_method_pos, join_method, UnitWithPos{extra_unit, extra_unit_pos}},
        )
    }
}

// Returns `nil` if there was an error
parse_iterator :: proc(s: ^ParserState) -> Iterator {
    get_next_token(s, false)
    value1, value1_ok := parse_unit(s)
    if !value1_ok {
        return nil
    }

    symbols, is_symbols_token := s.last_token.(SymbolsToken)
    type: NumericIteratorType
    if is_symbols_token && symbols == "..=" {
        type = .IncludeEndValue
    } else if is_symbols_token && symbols == "..<" {
        type = .ExcludeEndValue
    } else {
        utils.append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`..=`",
            "`..<`",
        )
        return value1
    }

    get_next_token(s, false)
    value2, value2_ok := parse_unit(s)
    if !value2_ok {
        return nil
    }

    _, is_step_token := s.last_token.(StepToken)
    if is_step_token {
        get_next_token(s, false)
        step, step_ok := parse_unit(s)
        if !step_ok {
            return nil
        }
        return NumericIterator{value1, value2, new_clone(step), type}
    }
    utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`step`")
    return NumericIterator{value1, value2, nil, type}
}

at_description := "`@` to set the label of the loop"
parse_possible_loop_label :: proc(s: ^ParserState) -> (TextAndPos, bool) {
    get_next_token(s, false)
    if _, is_at_token := s.last_token.(AtToken); is_at_token {
        get_next_token(s, false)
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident || len(ident) != 1 || ident[0].has_dollar_at_end {
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                plain_ident_capitalised + " for the label of the loop",
            )
            wrong_token_err(s)
            return TextAndPos{}, false
        }
        get_next_token(s, false)
        return TextAndPos{ident[0].ident, ident[0].pos}, true
    }
    return TextAndPos{}, true
}

// Does not include the `for`
parse_for_loop :: proc(s: ^ParserState) -> (ForInLoop, bool) {
    label, ok := parse_possible_loop_label(s)
    if !ok {
        return ForInLoop{}, false
    }
    variables: [3]TextAndPos
    variable_index := 0
    variables_loop: for {
        ident, is_ident := s.last_token.(IdentToken)
        if !is_ident || len(ident) != 1 || ident[0].has_dollar_at_end {
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "the name of the variable in a for loop (an identifier with one segment and no dollar sign at the end)",
            )
            if can_be_at := label.text == ""; can_be_at {
                utils.append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    at_description,
                )
            }
            wrong_token_err(s)
            return ForInLoop{}, false
        }
        variables[variable_index] = TextAndPos{ident[0].ident, ident[0].pos}
        variable_index += 1

        get_next_token(s, false)
        #partial switch token in s.last_token {
        case:
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`,`",
                "`in`",
            )
            wrong_token_err(s)
            return ForInLoop{}, false
        case InToken:
            break variables_loop
        case CommaToken:
            if variable_index >= 3 {
                utils.diagnostic(
                    s.r,
                    s.last_token_pos,
                    "There cannot be more than 3 variables in a for loop head (the iteration the for loop is on, the key of the thing being iterated over, and the value of the thing being iterated over)",
                )
                return ForInLoop{}, false
            }
            get_next_token(s, false)
        }
    }

    iter := parse_iterator(s)
    if iter == nil {
        return ForInLoop{}, false
    }

    _, is_open_brace := s.last_token.(OpenBraceToken)
    if !is_open_brace {
        utils.append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`{` to start the body of the for loop",
        )
        wrong_token_err(s)
        return ForInLoop{}, false
    }

    block, ok2 := parse_block(s)
    if !ok2 {
        return ForInLoop{}, false
    }

    return ForInLoop{label, variables, iter, block}, true
}

// Does not include the `if`
parse_if :: proc(s: ^ParserState) -> (^IfElseStatement, bool) {
    get_next_token(s, true)
    condition, condition_ok := parse_unit(s)
    if !condition_ok {
        return nil, false
    }
    #partial switch _ in s.last_token {
    case OpenBraceToken:
    case:
        utils.append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`{` to start the body of the if statement",
        )
        wrong_token_err(s)
        return nil, false
    }

    block, block_ok := parse_block(s)
    if !block_ok {
        return nil, false
    }

    get_next_token(s, true)
    #partial switch _ in s.last_token {
    case ElseToken:
        else_pos := s.last_token_pos
        get_next_token(s, true)
        #partial switch _ in s.last_token {
        case:
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`{`",
                "`if`",
            )
            wrong_token_err(s)
            return nil, false
        case OpenBraceToken:
            else_block, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            get_next_token(s, true)
            return new_clone(IfElseStatement{condition, block, else_block}), true

        case IfToken:
            else_block := make([]Statement, 1)
            else_statement, ok := parse_if(s)
            if !ok {
                return nil, false
            }
            else_block[0] = Statement{else_pos, else_statement^}
            return new_clone(IfElseStatement{condition, block, else_block}), true
        }
    case:
        utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`else`")
        return new_clone(IfElseStatement{condition, block, []Statement{}}), true
    }
}

/*
get_identifier :: proc(
    s: ^ParserState,
    variable_dest_type: VariableDestType,
) -> (
    VariableDest,
    bool,
) {
    idents, is_ident := s.last_token.(IdentToken)
    if !is_ident || len(idents) != 1 {
        append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "an identifier with one segment",
        )
        wrong_token_err(s)
        return VariableDest{}, false
    }
    ident := idents[0]
    get_next_token(s, false)
    _, is_open_square_brace := s.last_token.(OpenSquareBracketToken)
    if !is_open_square_brace {
        append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`[`")
        return VariableDest{ident, variable_dest_type, nil}, true
    }
    get_next_token(s, true)
    value, value_ok := parse_unit(s)
    if !value_ok {
        return VariableDest{}, false
    }
    _, is_close_square_brace := s.last_token.(CloseSquareBracketToken)
    if !is_close_square_brace {
        append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`]`")
        wrong_token_err(s)
        return VariableDest{}, false
    }
    get_next_token(s, true)
    return VariableDest{ident, variable_dest_type, new_clone(value)}, true
}


parse_managed_variable :: proc(s: ^ParserState) -> (VariableDest, bool) {
    #partial switch token in s.last_token {
    case IdentToken:
        return get_identifier(s, .Constant)
    case MutToken:
        get_next_token(s, false)
        #partial switch token2 in s.last_token {
        case IdentToken:
            return get_identifier(s, .Mutable)
        case SymbolsToken:
            if token2 != "+" {
                break
            }
            get_next_token(s, false)
            return get_identifier(s, .MutableAddedToPcs)
        }
        append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`+`",
            "an identifier",
        )
        wrong_token_err(s)
        return VariableDest{}, false
    case SymbolsToken:
        switch token {
        case "~":
            get_next_token(s, false)
            return get_identifier(s, .Mutated)
        case "+":
            get_next_token(s, false)
            return get_identifier(s, .ConstantAddedToPcs)
        }
    }
    append_dynamic_elems(
        &s.last_token_descriptions_of_other_possible_tokens,
        "`mut`",
        "`~`",
        "`+`",
        "an identifier",
    )
    wrong_token_err(s)
    return VariableDest{}, false
}
*/

// Does not include the `{`
parse_block :: proc(s: ^ParserState) -> ([]Statement, bool) {
    utils.append_dynamic(&s.parser_context, ParsingContext{s.last_token_pos, .Block})
    defer utils.pop_dynamic(&s.parser_context)
    out := [dynamic]Statement{}
    get_next_token(s, true)
    for {
        pos := s.last_token_pos
        #partial switch_stmt: switch token in s.last_token {
        case:
            // TODO: I would like to remove this mingling of expected tokens as it makes the error messages less clear
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`do` to create a do while loop",
                "`while` to create a while loop",
                "`if`",
                "`match`",
                "`for`",
                "`return`",
                "`yield`",
                "`continue`",
                "`break`",
                "`unreachable`",
                "`}`",
            )
            unit, ok := parse_unit(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, unit})
        case DoToken:
            // TODO: Support specifying label with @
            get_next_token(s, false)
            _, is_open_brace := s.last_token.(OpenBraceToken)
            if !is_open_brace {
                utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s)
                return nil, false
            }
            body, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            get_next_token(s, false)
            _, is_while := s.last_token.(WhileToken)
            if !is_while {
                utils.append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "`while`",
                )
                wrong_token_err(s)
                return nil, false
            }
            get_next_token(s, false)
            condition, condition_ok := parse_unit(s)
            if !condition_ok {
                return nil, false
            }
            append_elem(
                &out,
                Statement{pos, ConditionControlledLoop{.DoWhileLoop, condition, body}},
            )
        case WhileToken:
            // TODO: Support specifying label with @
            get_next_token(s, false)
            condition, condition_ok := parse_unit(s)
            if !condition_ok {
                return nil, false
            }
            _, is_open_brace := s.last_token.(OpenBraceToken)
            if !is_open_brace {
                utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s)
                return nil, false
            }
            body, ok := parse_block(s)
            if !ok {
                return nil, false
            }
            get_next_token(s, true)
            append_elem(&out, Statement{pos, ConditionControlledLoop{.WhileLoop, condition, body}})
        /*
        case IdentToken:
            get_next_token(s, true)
            #partial switch token2 in s.last_token {
            case:
                append_dynamic_elems(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    fmt.aprintf(
                        "`(` to call a function called `%s`",
                        strings.join(token.ident[:len(token)], "."),
                    ),
                    "`,`",
                    "`=`",
                )
                wrong_token_err(s)
                return nil, false
            case OpenBracketToken:
                args, ok := parse_units_until(s, is_close_bracket, "`)`")
                if !ok {
                    return nil, false
                }
                get_next_token(s, true)
                append_elem(
                    &out,
                    Statement {
                        pos,
                        CallWithBrackets{new_clone(Unit{pos, IdentNode{token}, nil}), args},
                    },
                )
                break switch_stmt
            case CommaToken:
                get_next_token(s, true)
            case AssignToken:
            }
            if len(token) != 1 {
                utils.diagnostic(
                    &s.r,
                    utils.Pos{s.last_token_pos, s.file_ref},
                    "TODO: Support assigns where the destination has more than one segment",
                )
                return nil, false
            }
            stmt: VariableManagement = ---
            ok: bool = ---
            stmt, ok = parse_variable_management_after_first_var(
                s,
                VariableDest{token[0], .Constant, nil},
            )
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, stmt})
            */
        case IfToken:
            if_else: ^IfElseStatement
            ok: bool
            if_else, ok = parse_if(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, if_else^})
        case LoopControlFlowToken:
            get_next_token(s, true)
            label := TextAndPos{}
            _, is_at := s.last_token.(AtToken)
            if is_at {
                get_next_token(s, true)
                ident, is_ident := s.last_token.(IdentToken)
                if !is_ident || len(ident) != 1 || ident[0].has_dollar_at_end {
                    utils.append_dynamic(
                        &s.last_token_descriptions_of_other_possible_tokens,
                        plain_ident_capitalised,
                    )
                    wrong_token_err(s)
                    return nil, false
                }
                label = TextAndPos{ident[0].ident, ident[0].pos}
                get_next_token(s, true)
            }
            append_elem(&out, Statement{pos, LoopControlFlow{label, token.kind}})
        case UnreachableToken:
            get_next_token(s, true)
            append_elem(&out, Statement{pos, UnreachableStatement{}})
        case MatchToken:
            get_next_token(s, true)
            value, value_ok := parse_unit(s)
            if !value_ok {
                return nil, false
            }

            if _, is_open_brace := s.last_token.(OpenBraceToken); !is_open_brace {
                utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`{`")
                wrong_token_err(s)
                return nil, false
            }

            branches := make([dynamic]MatchBranch)
            match_loop: for {
                get_next_token(s, true)
                _, is_close_brace := s.last_token.(CloseBraceToken)
                if is_close_brace {
                    break match_loop
                }

                utils.append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "`}` to finish the match statement",
                )
                branch_label, branch_label_ok := parse_unit(s)
                if !branch_label_ok {
                    return nil, false
                }

                if _, is_open_brace := s.last_token.(OpenBraceToken); !is_open_brace {
                    utils.append_dynamic(
                        &s.last_token_descriptions_of_other_possible_tokens,
                        "`{`",
                    )
                    wrong_token_err(s)
                    return nil, false
                }

                body, body_ok := parse_block(s)
                if !body_ok {
                    return nil, false
                }

                append_elem(&branches, MatchBranch{branch_label, body})
            }
            append_elem(&out, Statement{pos, MatchStatement{value, branches[:]}})
            get_next_token(s, true)
        case ForToken:
            loop, ok := parse_for_loop(s)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, loop})
            get_next_token(s, true)
        case ReturnToken:
            values, ok := parse_units_until(s, is_close_brace, "`}`").([]Unit)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, ReturnStatement(values)})
            return out[:], true
        case YieldToken:
            values, ok := parse_units_until(s, is_close_brace, "`}`").([]Unit)
            if !ok {
                return nil, false
            }
            append_elem(&out, Statement{pos, YieldStatement(values)})
            return out[:], true
        case CloseBraceToken:
            return out[:], true
        }
        _, is_close_brace := s.last_token.(CloseBraceToken)
        if is_close_brace {
            return out[:], true
        } else if !s.last_token_skipped {
            utils.append_dynamic(
                &s.last_token_descriptions_of_other_possible_tokens,
                "A newline or `;` to separate statements",
            )
            wrong_token_err(s)
            return nil, false
        }
    }
}

/*
parse_variable_management_after_first_var :: proc(
    s: ^ParserState,
    first_var: VariableDest,
) -> (
    VariableManagement,
    bool,
) {
    variables := [dynamic]VariableDest{first_var}
    type: MutationType
    loop: for {
        #partial switch token in s.last_token {
        case:
            append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`=`",
                "`,`",
                "`+=`",
                "`-=`",
                "`*=`",
                "`/=`",
            )
            wrong_token_err(s)
            return VariableManagement{}, false
        case SymbolsToken:
            switch token {
            case "+=":
                type = .IncrementBy
                break loop
            case "-=":
                type = .DecrementBy
                break loop
            case "*=":
                type = .MultiplyBy
                break loop
            case "/=":
                type = .DivideBy
                break loop
            }
        case AssignToken:
            type = MutationType.SetTo
            break loop
        case CommaToken:
            get_next_token(s, false)
        }
        ok := false
        var := VariableDest{}
        var, ok = parse_managed_variable(s)
        if !ok {
            return VariableManagement{}, false
        }
        append_elem(&variables, var)
    }
    get_next_token(s, true)
    value, value_ok := parse_unit(s)
    if !value_ok {
        return VariableManagement{}, false
    }
    return VariableManagement{value, variables[:], type}, true
}
*/

// Does not include the `(`
//parse_name_and_type_list :: proc(
//    state: ^TokenizerState,
//    type_required: bool,
//    descriptions_of_possible_end_token: ..string,
//) -> []NameAndUnit {
//    out := [dynamic]NameAndUnit{}
//    for {
//        arg: NameAndUnit
//        switch type, token := get_next_token(state, true, []string{"`)`", "a name"}); type {
//        case: return state.last_error
//        case close_bracket_token: return out[:]
//        case ident_token: arg.name = token.str
//        }
//
//        switch result in try_parse_type(
//            state,
//            ..(type_necesisity == .UnitRequired ? []string{} : join([]string{","}, ..descriptions_of_possible_end_token)),
//        ) {
//        case Failed: return state.last_error
//        case WrongFirstTokenUnit:
//        case Unit: arg.type = result
//        }
//        append_elem(&out, arg)
//        #partial switch token in get_next_token(
//            state,
//            true,
//            type_necesisity == .UnitRequired ? []string{"`,`", "a type"} : []string{"`,`", "`)`"},
//        ) {
//        case: return state.last_error
//        case UnitlessToken(Comma): continue
//        case UnitlessToken(CloseBracket): return out[:]
//        }
//    }
//}

// The boolean returned is whether the function passed successfully
parse_function_def :: proc(s: ^ParserState) -> (FunctionDefinition, bool) {
    get_next_token(s, false)
    _, is_open_bracket_token := s.last_token.(OpenBracketToken)
    if !is_open_bracket_token {
        utils.append_dynamic(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`(` to specify the arguments to the function",
        )
        wrong_token_err(s)
        return FunctionDefinition{}, false
    }

    args := make(#soa[dynamic]FunctionArg)
    loop: for {
        arg: FunctionArg
        get_next_token(s, true)

        utils.append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "an identifier with one segment for the name of a normal function argument",
            "`)`",
        )
        #partial switch token in s.last_token {
        case:
            wrong_token_err(s)
            return FunctionDefinition{}, false
        case CloseBracketToken:
            break loop
        case IdentToken:
            if len(token) != 1 {
                wrong_token_err(s)
                return FunctionDefinition{}, false
            }
            arg.name = token[0]
        }

        get_next_token(s, true)
        #partial switch _ in s.last_token {
        case ColonToken:
        case:
            utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, "`:`")
            wrong_token_err(s)
            return FunctionDefinition{}, false
        }

        get_next_token(s, true)
        arg_value_type, arg_value_type_ok := parse_unit(s)
        if !arg_value_type_ok {
            return FunctionDefinition{}, false
        }
        arg.value_type = arg_value_type
        append_soa_elem(&args, arg)

        #partial switch token in s.last_token {
        case:
            utils.append_dynamic_elems(
                &s.last_token_descriptions_of_other_possible_tokens,
                "`,`",
                "`)`",
            )
            wrong_token_err(s)
            return FunctionDefinition{}, false
        case CommaToken:
            continue
        case CloseBracketToken:
            break loop
        }
    }

    get_next_token(s, true)
    return_type: ^Unit = nil
    open_brace :: "`{` to start the body of the function"
    #partial switch _ in s.last_token {
    case:
        utils.append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "`->`",
            open_brace,
        )
        wrong_token_err(s)
        return FunctionDefinition{}, false
    case ArrowToken:
        get_next_token(s, true)
        parsed_return_type, parsed_return_type_ok := parse_unit(s)
        if !parsed_return_type_ok {
            return FunctionDefinition{}, false
        }
        _, is_open_brace := s.last_token.(OpenBraceToken)
        if !is_open_brace {
            utils.append_dynamic(&s.last_token_descriptions_of_other_possible_tokens, open_brace)
            wrong_token_err(s)
            return FunctionDefinition{}, false
        }
        return_type = new_clone(parsed_return_type)
    case OpenBraceToken:
    }

    block, ok := parse_block(s)
    if !ok {
        return FunctionDefinition{}, false
    }
    return FunctionDefinition{args[:], return_type, block}, true
}

GlobalValueWithGeneric :: struct {
    name:     string,
    generics: []TextAndPos, // The parser checks that the name of each generic argument is unique
    value:    Unit,
    file:     ^utils.CompilerFile,
}

GlobalValueWithoutGeneric :: struct {
    name: string,
    unit: Unit,
    file: ^utils.CompilerFile,
}

GlobalValueWithGenericRef :: struct {
    index: u32, // An index into `CheckerState.global_values_with_generic`
}

GlobalValueWithoutGenericRef :: struct {
    index: uint, // An index into `CheckerState.global_values_without_generics`
}

Import :: struct {
    file: ^utils.CompilerFile,
}

ParsedGlobal :: struct {
    pos:          uint,
    index:        u32,
    has_generics: bool,
}

parse_file :: proc(s: ^ParserState) {
    get_next_token(s, true)
    loop: for {
        utils.append_dynamic_elems(
            &s.last_token_descriptions_of_other_possible_tokens,
            "a newline",
            "a comment",
            "an identifier with one segment and no `$` sign at the end to define a global",
        )
        #partial switch token in s.last_token {
        case:
            wrong_token_err(s)
            return
        case EndOfFileToken:
            return
        case IdentToken:
            position := s.last_token_pos
            if len(token) != 1 || token[0].has_dollar_at_end {
                wrong_token_err(s)
                return
            }
            name := token[0].ident
            if def, exists :=
                   s.parsed_files.d[get_file_index(s.files_cache.files, s.last_token_pos.file)][name];
               exists {
                utils.diagnostic(
                    s.r,
                    position,
                    "The global `%s` is already declared at %v",
                    name,
                    utils.Pos{def.pos, s.last_token_pos.file},
                )
                return
            }
            get_next_token(s, false)
            generic_map := make(map[string]utils.Pos) // The key is the position of the generic arg
            generic := make([dynamic]TextAndPos)
            _, is_open_square_bracket := s.last_token.(OpenSquareBracketToken)
            if is_open_square_bracket {
                for {
                    get_next_token(s, false)
                    segments, is_ident := s.last_token.(IdentToken)
                    if !is_ident || len(segments) != 1 || segments[0].has_dollar_at_end {
                        utils.append_dynamic(
                            &s.last_token_descriptions_of_other_possible_tokens,
                            "An identifier with one segment and no dollar sign at the end",
                        )
                        break
                    }

                    if segments[0].ident in generic_map {
                        pos := generic_map[segments[0].ident]
                        utils.diagnostic(
                            s.r,
                            s.last_token_pos,
                            "There is already a generic argument called `%s` defined on %v in this global type",
                            segments[0].ident,
                            pos,
                        )
                        return
                    }
                    pos := segments[0].pos
                    append_elem(&generic, TextAndPos{segments[0].ident, pos})
                    generic_map[segments[0].ident] = pos

                    get_next_token(s, false)
                    _, is_comma := s.last_token.(CommaToken)
                    if !is_comma {
                        utils.append_dynamic(
                            &s.last_token_descriptions_of_other_possible_tokens,
                            "A comma",
                        )
                        break
                    }
                }

                _, is_close_square_bracket := s.last_token.(CloseSquareBracketToken)
                if !is_close_square_bracket {
                    utils.append_dynamic(
                        &s.last_token_descriptions_of_other_possible_tokens,
                        "`]`",
                    )
                    wrong_token_err(s)
                    return
                }

                get_next_token(s, false)

                if len(generic) == 0 {
                    utils.diagnostic(
                        s.r,
                        position,
                        "The parser is interpreting this as a non-generic value\nThe empty `[]` can be omitted",
                        type = .Warning,
                    )
                }
            } else {
                utils.append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "`[` to define the name of a generic argument to the value",
                )
            }
            #partial switch _ in s.last_token {
            case:
                utils.append_dynamic(
                    &s.last_token_descriptions_of_other_possible_tokens,
                    "`=` to define a global value",
                )
                wrong_token_err(s)
                return
            case AssignToken:
                get_next_token(s, false)
                type, ok := parse_unit(s)
                if !ok {
                    assert(s.r.has_errors(s.r.data))
                    return
                }
                if len(generic) == 0 {
                    s.parsed_files.d[get_file_index(s.files_cache.files, s.last_token_pos.file)][name] =
                        ParsedGlobal {
                            position.index,
                            u32(len(s.global_values_without_generics)),
                            false,
                        }
                    append_elem(
                        &s.global_values_without_generics,
                        GlobalValueWithoutGeneric{name, type, s.last_token_pos.file},
                    )
                } else {
                    s.parsed_files.d[get_file_index(s.files_cache.files, s.last_token_pos.file)][name] =
                        ParsedGlobal{position.index, u32(len(s.global_values_with_generics)), true}
                    append_elem(
                        &s.global_values_with_generics,
                        GlobalValueWithGeneric{name, generic[:], type, s.last_token_pos.file},
                    )
                }
            }
        }
    }
}

ParserOutput :: struct {
    parsed_files:                  utils.Multi(map[string]ParsedGlobal),
    global_values_without_generic: []GlobalValueWithoutGeneric,
    global_values_with_generics:   []GlobalValueWithGeneric,
    function_defs:                 []FunctionDefinition,
}

parse_project :: proc(
    a: ^utils.Arena,
    files_cache: ^utils.FilesCache,
    out: utils.Pipe(io.Writer),
    exit_early: EarlyExitInfo,
    diagnostic_reporter: utils.DiagnosticReporter,
    loc := #caller_location,
) -> ParserOutput {
    utils.call(loc, "parse_project", "", enable_debug = utils.debug_parser)
    state := ParserState {
            r              = diagnostic_reporter,
            files_cache    = files_cache,
            parser_context = utils.arena_make(a, []ParsingContext, 0, resizable = true),
            parsed_files   = utils.arena_make_multi(
                a,
                utils.Multi(map[string]ParsedGlobal),
                0,
                resizable = true,
            ),
            a              = a,
        }
    defer {
        utils.fix_resizable_multi(state.parsed_files)
        utils.fix_resizable_dynamic(state.parser_context)
    }

    state.last_token_pos.file = &state.files_cache.files[0]

    for {
        file_path := state.last_token_pos.file.file_path
        fmt.wprintfln(out.stdout, "Parsing `%s`...", file_path)
        utils.append_multi_dynamic(
            &state.parsed_files,
            get_file_index(state.files_cache.files, state.last_token_pos.file),
            nil,
        )
        state.tokenizer_state = TokenizerState {
                last_token_descriptions_of_other_possible_tokens = utils.arena_make(
                    a,
                    []string,
                    0,
                    resizable = true,
                ),
                last_token_pos                                   = utils.Pos {
                    0,
                    state.last_token_pos.file,
                },
            }
        defer utils.fix_resizable_dynamic(
            state.tokenizer_state.last_token_descriptions_of_other_possible_tokens,
        )
        parse_file(&state)
        next_index := get_file_index(state.files_cache.files, state.last_token_pos.file) + 1
        if next_index >= len(state.files_cache.files) {
            break
        }
        state.last_token_pos.file = &state.files_cache.files[next_index]
    }
    if exit_early_info, exiting_early := exit_early.(^ExitEarly); exiting_early {
        #partial switch &exit_early_info_value in exit_early_info {
        case ExitEarlyAwaitingSourceCodeChange:
            exit_early_info_value.files = state.files_cache.files
        case:
            panic("Unreachable")
        }
    }
    if state.r.has_errors(state.r.data) {
        return ParserOutput{}
    }
    return ParserOutput {
        state.parsed_files,
        state.global_values_without_generics[:],
        state.global_values_with_generics[:],
        state.function_defs[:],
    }
}

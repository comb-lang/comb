package compiler

// Handles namespace operations. Namespace operations are all handled in the
// same file to maintain a consistent set of builtins which cannot be overridden.

import "../utils"
import "core:fmt"
import "core:strings"

builtins_err :: "`%s` is a builtin\nCannot override builtins"

// function_todo1 :: "TODO: Handle function calls where the function isn't a variable reference"
// function_todo2 :: "TODO: Handle function calls where `len(function_name_segments) > 2`"
// function_err1 :: "Compiler functions can only be called in function definitions which are marked with `#comptime`"
// function_err3 :: "In 2 segment function call that is used as a %s where the first segment is `compiler`\nExpected the second segment to be either %s\nGot `%s`"
// function_err4 :: "This function returns a value, so it cannot be used this as a statement"
// function_err5 :: "This function does not return a value, so it cannot be used as a value"
// function_err6 :: "First segment of a 2 segment function call that is used as a statement must be `compiler`\nGot `%s`"
// function_err7 :: "First segment of a 2 segment function call that is used as a value must be either `compiler` or ``\nGot `%s`"

BuiltinFunction :: enum u8 {
    print,
    println,
    eprint,
    eprintln,
    readline,
    read_file,
    write_file,
    clear,
    run_executable,
    exit,
    get_os_args, // TODO
    emit_js_code,
    string_repeat,
    cache_contains,
    cache_set,
    cache_get,
    init_http_server,
    cast_func,
    save_cursor_pos,
    restore_cursor_pos,
    clear_after_cursor,
    make_dir_all,
    expect_uint,
}

GotBuiltin :: struct {
    value: CompileTimeValue,
    type:  Type,
}

// `GotBuiltin.value == nil` if and only if the builtin does not exist
get_builtin :: proc(name: string) -> GotBuiltin {
    switch name {
    case:
        return GotBuiltin{}
    case "print":
        return GotBuiltin{BuiltinFunction.print, .StringToNil}
    case "println":
        return GotBuiltin{BuiltinFunction.println, .StringToNil}
    case "eprint":
        return GotBuiltin{BuiltinFunction.eprint, .StringToNil}
    case "eprintln":
        return GotBuiltin{BuiltinFunction.eprintln, .StringToNil}
    case "readline":
        return GotBuiltin{BuiltinFunction.readline, .StringToString}
    case "read_file":
        return GotBuiltin{BuiltinFunction.read_file, .StringToString}
    case "write_file":
        return GotBuiltin{BuiltinFunction.write_file, .StringStringToNil}
    case "clear":
        return GotBuiltin{BuiltinFunction.clear, .NoArgsToNil}
    case "run_executable":
        return GotBuiltin{BuiltinFunction.run_executable, .ArrayOfStringsToNil}
    case "exit":
        return GotBuiltin{BuiltinFunction.exit, .IntToNil}
    case "string_repeat":
        return GotBuiltin{BuiltinFunction.string_repeat, .StringUintToString}
    case "init_http_server":
        return GotBuiltin{BuiltinFunction.init_http_server, .NoArgsToHttpServer}
    case "cast":
        return GotBuiltin{BuiltinFunction.cast_func, .Unknown}
    case "save_cursor_pos":
        return GotBuiltin{BuiltinFunction.save_cursor_pos, .NoArgsToNil}
    case "restore_cursor_pos":
        return GotBuiltin{BuiltinFunction.restore_cursor_pos, .NoArgsToNil}
    case "clear_after_cursor":
        return GotBuiltin{BuiltinFunction.clear_after_cursor, .NoArgsToNil}
    case "make_dir_all":
        return GotBuiltin{BuiltinFunction.make_dir_all, .StringToNil}
    case "expect_uint":
        return GotBuiltin{BuiltinFunction.expect_uint, .FloatToUInt}
    case "Int":
        return GotBuiltin{Type.Int, .Type}
    case "UInt":
        return GotBuiltin{Type.UInt, .Type}
    case "Float":
        return GotBuiltin{Type.Float, .Type}
    case "Char":
        return GotBuiltin{Type.Char, .Type}
    case "Bool":
        return GotBuiltin{Type.Bool, .Type}
    case "String":
        return GotBuiltin{Type.String, .Type}
    case "Type":
        return GotBuiltin{Type.Type, .Type}
    case "ImportedFile":
        return GotBuiltin{Type.ImportedFile, .Type}
    case "Any":
        return GotBuiltin{Type.Any, .Type}
    case "Compiler":
        return GotBuiltin{Type.Compiler, .Type}
    case "CompilerCache":
        return GotBuiltin{Type.CompilerCache, .Type}
    case "HttpRequest":
        return GotBuiltin{Type.HttpRequest, .Type}
    case "HttpResponse":
        return GotBuiltin{Type.HttpResponse, .Type}
    case "HttpServer":
        return GotBuiltin{Type.HttpServer, .Type}
    }
}

argument_count_mismatch :: proc(
    s: ^CheckerState,
    pos: utils.Pos,
    num_provided: uint,
    num_expected: uint,
    func_name: ..string,
) {
    name := strings.join(func_name, ".")
    defer delete_string(name)
    num_to_str :: proc(num: uint) -> string {
        return num == 1 ? fmt.aprint("1 argument") : fmt.aprintf("%d arguments", num)
    }
    provided := num_to_str(num_provided)
    defer delete_string(provided)
    expected := num_to_str(num_expected)
    defer delete_string(expected)
    utils.diagnostic(
        s.r,
        pos,
        "Argument count mismatch\nFunction call provides %s\nThe `%s` function expects %s",
        provided,
        name,
        expected,
    )
}

to_str :: proc(s: ^CheckerState, pos: utils.Pos, val: CheckedValue, type: Type) -> CheckedValue {
    from_type: ToStringFromType = ---
    #partial switch type {
    case .Bool:
        from_type = .BoolType
    case .String:
        return val
    case .Int:
        from_type = .IntType
    case .UInt:
        from_type = .UIntType
    case .Float:
        from_type = .FloatType
    case .Char:
        from_type = .CharType
    case:
        utils.diagnostic(
            s.r,
            pos,
            "Cannot convert the type `%s` to `String`",
            type_to_string(s, type),
        )
        return nil
    }
    return ToString{from_type, new_clone(val)}
}

add_unnamed_variable :: proc(
    s: ^CheckerState,
    variable_type: Type,
    variable_is_re: bool,
    loc := #caller_location,
) -> VariableRef {
    when utils.debug_checker {
        utils.print_call(loc, "add_unnamed_variable")
    }
    var_ref := VariableRef{len(s.scopes) - 1, len(s.scopes[len(s.scopes) - 1].variables)}
    append_soa_elem(
        &s.scopes[len(s.scopes) - 1].variables,
        ScopeVariable{variable_type, variable_is_re},
    )
    return var_ref
}

// The boolean returned is whether there are errors
add_variable :: proc(
    s: ^CheckerState,
    variable_type: Type,
    variable: Ident, // if `variable.has_dollar_at_end`, then the variable is created as mutable
    loc := #caller_location,
) -> (
    VariableRef,
    bool,
) {
    when utils.debug_checker {
        utils.print_call(loc, "add_variable")
    }
    if _, is_uninitialised := get_type(s.types, variable_type).key.(UninitialisedType);
       is_uninitialised {
        utils.panicf("Unreachable (called from %v)", loc)
    }
    // TODO: Add a warning for unused variables
    expect_snake_case(
        s,
        "variable names",
        TextAndPos{variable.ident, variable.pos},
        can_have_dollar_postfix = true,
    )
    if get_builtin(variable.ident).value != nil {
        utils.diagnostic(s.r, variable.pos, builtins_err, variable.ident)
        return VariableRef{}, false
    }
    if variable.ident in s.variables_map {
        utils.diagnostic(s.r, variable.pos, "Redeclaration of variable `%s`", variable.ident)
        return VariableRef{}, false
    }
    alt_ident := ""
    if variable.has_dollar_at_end {
        alt_ident = variable.ident[:len(variable.ident) - 1]
    } else {
        alt_ident = utils.aprintf(s.a, "%s$", variable.ident)
    }
    if alt_ident in s.variables_map {
        utils.diagnostic(
            s.r,
            variable.pos,
            "Declaring variable called `%s` when variable called `%s` is already declared",
            variable.ident,
            alt_ident,
            type = .Warning,
        )
    }
    var_ref := add_unnamed_variable(s, variable_type, variable.has_dollar_at_end)
    if variable.ident != "" {
        s.variables_map[variable.ident] = var_ref
    }
    return var_ref, true
}

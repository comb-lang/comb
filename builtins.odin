package main

// Handles namespace operations. Namespace operations are all handled in the
// same file to maintain a consistent set of builtins which cannot be overridden.

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
    invalid_builtin = max(u8),
}

get_builtin_func_from_name :: proc(name: string) -> (BuiltinFunction, Type) {
    switch name {
    case "print": return .print, .StringToNil
    case "println": return .println, .StringToNil
    case "eprint": return .eprint, .StringToNil
    case "eprintln": return .eprintln, .StringToNil
    case "readline": return .readline, .StringToString
    case "read_file": return .read_file, .StringToString
    case "write_file": return .write_file, .StringStringToNil
    case "clear": return .clear, .NoArgsToNil
    case "run_executable": return .run_executable, .ArrayOfStringsToNil
    case "exit": return .exit, .IntToNil
    case "string_repeat": return .string_repeat, .StringUintToString
    case "init_http_server": return .init_http_server, .NoArgsToHttpServer
    case "cast": return .cast_func, .Unknown
    case "save_cursor_pos": return .save_cursor_pos, .NoArgsToNil
    case "restore_cursor_pos": return .restore_cursor_pos, .NoArgsToNil
    case "clear_after_cursor": return .clear_after_cursor, .NoArgsToNil
    case "make_dir_all": return .make_dir_all, .StringToNil
    case "expect_uint": return .expect_uint, .FloatToUInt
    case: return .invalid_builtin, .Invalid
    }
}

get_builtin_type_from_name :: proc(name: string) -> Type {
    switch name {
    case "Int": return .Int
    case "UInt": return .UInt
    case "Float": return .Float
    case "Char": return .Char
    case "Bool": return .Bool
    case "String": return .String
    case "Type": return .Type
    case "ImportedFile": return .ImportedFile
    case "Any": return .Any
    case "Compiler": return .Compiler
    case "CompilerCache": return .CompilerCache
    case "HttpRequest": return .HttpRequest
    case "HttpResponse": return .HttpResponse
    case "HttpServer": return .HttpServer
    case: return .Unknown
    }
}

argument_count_mismatch :: proc(
    s: ^CheckerState,
    pos: Pos,
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
    diagnostic(
        s,
        pos,
        "Argument count mismatch\nFunction call provides %s\nThe `%s` function expects %s",
        provided,
        name,
        expected,
    )
}

to_str :: proc(s: ^CheckerState, pos: Pos, val: CheckedValue, type: Type) -> CheckedValue {
    from_type: ToStringFromType = ---
    #partial switch type {
    case .Bool: from_type = .BoolType
    case .String: return val
    case .Int: from_type = .IntType
    case .UInt: from_type = .UIntType
    case .Float: from_type = .FloatType
    case .Char: from_type = .CharType
    case:
        diagnostic(s, pos, "Cannot convert the type `%s` to `String`", type_to_string(s, type))
        return nil
    }
    return ToString{from_type, new_clone(val)}
}

// The boolean returned is whether the name is a builtin
is_builtin :: proc(name: string) -> bool {
    switch name {
    case "Compiler",
         "CompilerCache",
         "cast",
         "print",
         "println",
         "eprint",
         "eprintln",
         "readline",
         "read_file",
         "write_file",
         "clear",
         "run_executable",
         "exit",
         "save_cursor_pos",
         "restore_cursor_pos",
         "clear_after_cursor",
         "make_dir_all",
         "Int",
         "UInt",
         "Float",
         "Char",
         "Bool",
         "String",
         "Type",
         "ImportedFile",
         "OrderedHashMap",
         "Any",
         "to_str",
         "HttpRequest",
         "HttpResponse",
         "HttpServer",
         "init_http_server",
         "expect_uint",
         "string_repeat":
        return true
    case: return false
    }
}

add_unnamed_variable :: proc(
    s: ^CheckerState,
    variable_type: Type,
    variable_is_re: bool,
    loc := #caller_location,
) -> VariableRef {
    when debug_checker {
        print_call(loc, "add_unnamed_variable")
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
    when debug_checker {
        print_call(loc, "add_variable")
    }
    // TODO: Add a warning for unused variables
    expect_snake_case(
        s,
        "variable names",
        TextAndPos{variable.ident, variable.pos},
        can_have_dollar_postfix = true,
    )
    if is_builtin(variable.ident) {
        diagnostic(s, variable.pos, builtins_err, variable.ident)
        return VariableRef{}, false
    }
    if variable.ident in s.variables_map {
        diagnostic(s, variable.pos, "Redeclaration of variable `%s`", variable.ident)
        return VariableRef{}, false
    }
    alt_ident := ""
    if variable.has_dollar_at_end {
        alt_ident = variable.ident[:len(variable.ident) - 1]
    } else {
        alt_ident = aprintf(s.a, "%s$", variable.ident)
    }
    if alt_ident in s.variables_map {
        diagnostic(
            s,
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

package main

import "base:runtime"
import "compiler"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "lsp"
import "utils"

c_warning :: "WARNING: The C emitter is basically unmaintained at this point, and there are many things which it does not implement\n"

position_formatter :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
    if verb != 'v' {
        return false
    }
    pos := cast(^utils.Pos)arg.data
    utils.write_position(fi.writer, pos^)
    return true
}

source_code_location_formatter :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
    if verb != 'v' {
        return false
    }
    loc := cast(^runtime.Source_Code_Location)arg.data
    fmt.wprintf(fi.writer, "file %s at line %d column %d", loc.file_path, loc.line, loc.column)
    return true
}

time_formatter :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
    if verb != 'v' {
        return false
    }
    t := cast(^time.Time)arg.data
    h, m, s := time.clock(t^)
    fmt.wprintf(fi.writer, "%d:%d:%d", h, m, s, flush = false)
    return true
}

@(init)
init :: proc "contextless" () {
    context = runtime.default_context()
    user_formatters := new(map[typeid]fmt.User_Formatter)
    user_formatters[utils.Pos] = position_formatter
    user_formatters[compiler.TokenContents] = compiler.token_formatter
    user_formatters[runtime.Source_Code_Location] = source_code_location_formatter
    user_formatters[time.Time] = time_formatter
    fmt.set_user_formatters(user_formatters)
}

@(fini)
fini :: proc "contextless" () {
    // TODO: Check if there are any `Arena` allocators which have not been deleted when `ODIN_DEBUG == true`
    context = runtime.default_context()
    delete_map(fmt._user_formatters^)
    free(fmt._user_formatters)
}

// The `string` returned is the path to the executable
write_and_compile_c :: proc(c_code: []u8, path: string) -> (string, bool) {
    c_code_path := fmt.aprintf("%s.c", path)
    output_executable_path := fmt.aprintf("%s.bin", path)

    fmt.printfln("Writing C code to `%s`...", c_code_path)
    err := os.write_entire_file(c_code_path, c_code)
    if err != nil {
        fmt.eprintfln("Failed to write to `%s`: %#v", c_code_path, err)
        return "", false
    }

    fmt.printfln("Compiling the C code into an executable at `%s`...", output_executable_path)
    // TODO: Use `CC` environment variable by default, and fallback to `cc` command, than `gcc` command
    command := []string{"gcc", c_code_path, "-o", output_executable_path}
    state, _, _, err2 := os.process_exec(os.Process_Desc{command = command}, context.allocator)
    if err2 != nil {
        fmt.eprintln("Failed to invoke compilation command for `%s`: %#v", c_code_path, err2)
        return "", false
    }
    if state.exit_code != 0 {
        fmt.eprintfln(
            "Failed to compile `%s`:\nCommand ran: `%s`\nExit code: %d",
            c_code_path,
            strings.join(command, " "),
            state.exit_code,
        )
        return "", false
    }
    return output_executable_path, true
}

BuildC :: struct {
    executable_path_store: ^string,
}

Run :: struct {
    program_io:              utils.Pipe(io.Writer),
    stdin:                   io.Reader,
    long_lived_interp_state: ^LongLivedInterpState,
}

Command :: union #no_nil {
    BuildC,
    Run,
}

compile :: proc(
    a: ^utils.Arena,
    func: FunctionRef,
    out: utils.Pipe(io.Writer),
    command: Command,
    exit_early: compiler.EarlyExitInfo,
) -> int {
    // TODO: There are some return paths where `exit_early` is not updated and
    // therefore the `-watch` flag does not auto reload

    start := time.now()
    if exit_early_info, exiting_early := exit_early.(^compiler.ExitEarly); exiting_early {
        exit_early_info^ = compiler.ExitEarlyAwaitingSourceCodeChange{start, nil, time.Time{}}
    }
    defer {
        fmt.wprintfln(out.stdout, "Done in %f ms!", time.duration_milliseconds(time.since(start)))
    }

    files_cache := utils.empty_files_cache(a)
    defer utils.cleanup_files_cache(files_cache)

    file_absolute_path, abs_err := filepath.abs(func.file_name, context.allocator)
    if abs_err != nil {
        fmt.wprintfln(
            out.stderr,
            "Failed to make filepath `%s` absolute: %v",
            func.file_name,
            abs_err,
        )
        return 1
    }

    fmt.wprintfln(out.stdout, "Reading `%s`...", file_absolute_path)
    first_file, read_err := utils.read_file(&files_cache, file_absolute_path)
    if read_err != nil {
        fmt.wprintfln(out.stderr, "Failed to read `%s`: %#v", file_absolute_path, read_err)
        return 1
    }

    reporter_data := new_clone(utils.StandardDiagnosticReporter{io = out})
    reporter := utils.DiagnosticReporter {
        reporter_data,
        utils.standard_has_errors,
        utils.standard_diagnostic_header,
    }
    checker_output := compiler.parse_and_check(
        a,
        &files_cache,
        first_file,
        func.func_name,
        out,
        exit_early,
        reporter,
    )

    function_type := compiler.Type.Unknown
    if checker_output.func_ref.index < len(checker_output.checked_funcs) {
        function_type = checker_output.checked_funcs[checker_output.func_ref.index].type
        if function_type != .Unknown {
            // TODO: Include index in error message position
            switch c in command {
            case BuildC:
                if function_type != .NoArgsToInt {
                    utils.diagnostic(
                        reporter,
                        utils.Pos{max(uint), first_file},
                        "Got the type `%s`\nExpected the type `%s`",
                        compiler.type_to_string2(
                            checker_output.types,
                            checker_output.globals_without_generic,
                            checker_output.globals_with_generic,
                            function_type,
                        ),
                        compiler.type_to_string2(
                            checker_output.types,
                            checker_output.globals_without_generic,
                            checker_output.globals_with_generic,
                            .NoArgsToInt,
                        ),
                    )
                }
            case Run:
                if function_type != .NoArgsToInt && function_type != .CompilerToInt {
                    utils.diagnostic(
                        reporter,
                        utils.Pos{max(uint), first_file},
                        "Got the type `%s`\nExpected the type `%s` or `%s`",
                        compiler.type_to_string2(
                            checker_output.types,
                            checker_output.globals_without_generic,
                            checker_output.globals_with_generic,
                            function_type,
                        ),
                        compiler.type_to_string2(
                            checker_output.types,
                            checker_output.globals_without_generic,
                            checker_output.globals_with_generic,
                            .NoArgsToInt,
                        ),
                        compiler.type_to_string2(
                            checker_output.types,
                            checker_output.globals_without_generic,
                            checker_output.globals_with_generic,
                            .CompilerToInt,
                        ),
                    )
                }
            case:
                panic("Unreachable")
            }
        }
    }

    errors, warnings: string = ---, ---

    if reporter_data.number_of[.Error] == 1 {
        errors = fmt.aprint("1 error")
    } else {
        errors = fmt.aprintf("%d errors", reporter_data.number_of[.Error])
    }
    defer delete_string(errors)

    if reporter_data.number_of[.Warning] == 1 {
        warnings = fmt.aprint("1 warning")
    } else {
        warnings = fmt.aprintf("%d warnings", reporter_data.number_of[.Warning])
    }
    defer delete_string(warnings)

    elapsed_ms := time.duration_milliseconds(time.since(start))

    if reporter_data.number_of[.Error] > 0 {
        fmt.wprintfln(
            out.stderr,
            "Erroneously checked with %s and %s in %f ms",
            errors,
            warnings,
            elapsed_ms,
        )
        return 1
    }

    fmt.wprintfln(
        out.stdout,
        "Successfully checked with %s and %s in %f ms",
        errors,
        warnings,
        elapsed_ms,
    )

    if build_c, is_build_c := command.(BuildC); is_build_c {
        fmt.wprintfln(out.stdout, "Emitting C code...")
        fmt.wprintf(out.stderr, c_warning)
        c := emit_c(checker_output.types, checker_output.checked_funcs, checker_output.func_ref)
        executable_path, ok2 := write_and_compile_c(c, func.file_name)
        if !ok2 {
            return 1
        }
        if build_c.executable_path_store != nil {
            build_c.executable_path_store^ = executable_path
        }
        return 0
    }
    run := command.(Run)

    absolute_file_name, err := filepath.abs(func.file_name, context.allocator)
    if err != nil {
        fmt.wprintfln(out.stderr, "Failed make path absolute: %#v", err)
        return 1
    }
    defer delete(absolute_file_name)

    fmt.wprintfln(out.stdout, "Interpreting `%s`...", func.func_name)

    absolute_file_dir := filepath.dir(absolute_file_name)
    state := ShortLivedInterpState {
        types                   = checker_output.types,
        globals_with_generic    = checker_output.globals_with_generic,
        globals_without_generic = checker_output.globals_without_generic,
        checked_funcs           = checker_output.checked_funcs,
        builtin_handler         = BuiltinHandler {
            &DefaultBuiltinHandlerData{absolute_file_dir, run.program_io, run.stdin},
            default_builtin_handler_procedure,
        },
        exit_early              = exit_early,
    }
    args: []RuntimeValue
    if function_type == .CompilerToInt {
        compiler_cache_struct_fields := make([]RuntimeValue, 3)
        compiler_cache_struct_fields[0] = compiler.BuiltinFunction.cache_contains
        compiler_cache_struct_fields[1] = compiler.BuiltinFunction.cache_set
        compiler_cache_struct_fields[2] = compiler.BuiltinFunction.cache_get

        compiler_struct_fields := make([]RuntimeValue, 2)
        compiler_struct_fields[0] = compiler.BuiltinFunction.emit_js_code
        compiler_struct_fields[1] = RuntimeStruct {
            true,
            compiler_cache_struct_fields,
            .CompilerCache,
        }

        args = make([]RuntimeValue, 1)
        args[0] = RuntimeStruct{true, compiler_struct_fields, .Compiler}
    }
    result := interp_execute_function2(
        InterpState{&state, run.long_lived_interp_state},
        RuntimeFunc{checker_output.func_ref, nil},
        args,
    )
    if compiler.should_exit_early(exit_early) {
        return 1
    } else {
        return expect_int(result.(f64))
    }
}

/*
// The `string` returned is the path to the executable
// Returns `"", false` on failure
    if checker_output.entry_func_type == .BuildFunc {
        if interpret_file {
            fmt.eprintln("Cannot use `interpret` with files that use a custom `build` func")
            return "", false
        }
        fmt.printfln("Interpreting metaprogram...")
        result := interpret(checker_output.checked, builtin_handler, checker_output.entry_func_ref)
        return "", result.(i64) == 0 ? true : false
        /*
        // OLD(METAPROGRAM_IN_C)
        tmp, err := os.temp_directory(context.allocator)
        if err != nil {
            fmt.eprintfln("Failed to get temporary directory: %#v", file_name, err)
            return "", false
        }

        absolute_file_name, err2 := filepath.abs(file_name, context.allocator)
        if err2 != nil {
            fmt.eprintfln("Failed to convert `%s` to an absolute path: %v", file_name, err2)
            return "", false
        }
        absolute_file_dir := filepath.dir(absolute_file_name)

        dir_in_tmp, err3 := filepath.join([]string{tmp, absolute_file_dir}, context.allocator)
        if err3 != nil {
            fmt.eprintfln("Failed to join filepath: %v", err3)
            return "", false
        }
        if !os.exists(dir_in_tmp) {
            err = os.make_directory_all(dir_in_tmp)
            if err != nil {
                fmt.eprintfln("Failed to create directory `%s`: %#v", dir_in_tmp, err)
                return "", false
            }
        }

        c_path, err4 := filepath.join([]string{tmp, absolute_file_name}, context.allocator)
        if err4 != nil {
            fmt.eprintfln("Failed to join filepath: %v", err4)
            return "", false
        }
        executable_path, ok := write_and_compile_c(c, c_path)
        if !ok {
            return "", false
        }

        run_metaprogram(absolute_file_dir, executable_path, checker_output.checked)
        return "", true
        */
    } else if interpret_file {
        fmt.printfln(
            "Finished building in %f ms!",
            time.duration_milliseconds(time.since(build_start)),
        )
        fmt.printfln("Interpreting...")
        result := interpret(checker_output.checked, builtin_handler, checker_output.entry_func_ref)
        return "", result.(i64) == 0 ? true : false
    } else {
    }
    */

/*
// OLD(METAPROGRAM_IN_C)
run_metaprogram :: proc(
    metaprogram_working_dir: string,
    metaprogram_path: string,
    checked: Checked,
) -> bool {
    stdin_reader, stdin_writer, err := os.pipe()
    if err != nil {
        fmt.eprintln("Failed to create pipe: %#v", err)
        return false
    }
    defer os.close(stdin_reader)
    defer os.close(stdin_writer)

    stdout_pipe, err2 := create_buffered_pipe()
    if err2 != nil {
        fmt.eprintln("Failed to create buffered pipe: %#v", err2)
        return false
    }
    defer close_buffered_pipe(stdout_pipe)

    fmt.printfln("Starting metaprogram at `%s`...", metaprogram_path)
    // TODO: Check the exit code of the process
    _, err3 := os.process_start(
        os.Process_Desc {
            working_dir = metaprogram_working_dir,
            command = []string{metaprogram_path},
            stdin = stdin_reader,
            stdout = stdout_pipe.writer,
            stderr = os.stderr,
        },
    )
    if err3 != nil {
        fmt.eprintln("Failed to start %s: %#v", metaprogram_path, err3)
        return false
    }

    for {
        command_raw, err4 := bufio.reader_read_string(stdout_pipe.bufio_reader, EOT)
        if err4 != nil {
            assert(command_raw == "")
            fmt.eprintln("Failed to read string: %#v", err4)
            return false
        }
        defer delete(command_raw)
        assert(command_raw[len(command_raw) - 1] == EOT)
        command := command_raw[:len(command_raw) - 1]

        switch command {
        case done_command:
            return true
        case "compiler.emit_js_code":
            arg_raw, err5 := bufio.reader_read_string(stdout_pipe.bufio_reader, EOT)
            if err5 != nil {
                assert(arg_raw == "")
                fmt.eprintln("Failed to read string: %#v", err5)
                return false
            }
            defer delete(arg_raw)
            assert(arg_raw[len(arg_raw) - 1] == EOT)
            arg, ok := strconv.parse_uint(arg_raw[:len(arg_raw) - 1])
            assert(ok)
            fmt.printfln("Compiler received compiler.emit_js_code(%d) from metaprogram", arg)

            builder := emit_javascript(checked)
            defer strings.builder_destroy(&builder)

            strings.write_byte(&builder, EOT)
            os.write_string(stdin_writer, strings.to_string(builder))

            fmt.printfln("Compiler responded to compiler.emit_js_code")
        case:
            fmt.eprintfln("Received unrecognized command %q from metaprogram", command)
            return false
        }
    }
}
*/

default_file_name :: "./main.code" // TODO: Choose proper file extension
default_func_name :: "main"

print_help :: proc(exit_code: int) -> ! {
    args :: "[file name] [func name] [-watch]"
    fmt.println(
        "- `build_c " +
        args +
        "` transpile a file into C and then build the C code into an executable",
    )
    fmt.println("- `run " + args + "` compile a file and interpret a function within that file")
    fmt.println("- `help` show this help message")
    fmt.println("- For commands that take the arguments `" + args + "`:")
    fmt.println(
        "  - If the last argument specified is `-watch`, then the compiler will automatically restart the compilation when the source code changes",
    )
    fmt.println(
        "  - Of the remaining arguments, if only one argument is specified, and the argument contains only alphanumerics and underscores, the compiler assumes it is the `func name`",
    )
    fmt.println("  - Otherwise, the compiler assumes that the first argument is the `file name`")
    fmt.println(
        "  - If the `file name` is not specified, it defaults to `" + default_file_name + "`",
    )
    fmt.println(
        "  - If the `func name` is not specified, it defaults to `" + default_func_name + "`",
    )
    os.exit(exit_code)
}

FunctionRef :: struct {
    file_name: string,
    func_name: string,
}

// Terminates the program on failure
// The bool returned is whether the `--watch` flag was used
parse_args_after_command :: proc(args_after_command: []string) -> (FunctionRef, bool) {
    watch := false
    func_ref_args := args_after_command
    if len(args_after_command) >= 1 &&
       args_after_command[len(args_after_command) - 1] == "-watch" {
        watch = true
        func_ref_args = args_after_command[:len(args_after_command) - 1]
    }
    switch len(func_ref_args) {
    case 0:
        return FunctionRef{default_file_name, default_func_name}, watch
    case 1:
        for char in func_ref_args[0] {
            if !utils.is_alphanumeric_char_any(char) {
                return FunctionRef{func_ref_args[0], default_func_name}, watch
            }
        }
        return FunctionRef{default_file_name, func_ref_args[0]}, watch
    case 2:
        return FunctionRef{func_ref_args[0], func_ref_args[1]}, watch
    case:
        fmt.eprintln(
            "Expected at most 3 arguments after the name of the command: the file name, the func name, and the `-watch` flag\nGot %d arguments",
            len(args_after_command),
        )
        print_help(1)
    }
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    stdout_buf: [1024]byte
    stderr_buf: [1024]byte
    stdout_writer: bufio.Writer
    stderr_writer: bufio.Writer
    bufio.writer_init_with_buf(&stdout_writer, os.to_stream(os.stdout), stdout_buf[:])
    bufio.writer_init_with_buf(&stderr_writer, os.to_stream(os.stderr), stderr_buf[:])
    std_pipe := utils.Pipe(io.Writer) {
        bufio.writer_to_writer(&stdout_writer),
        bufio.writer_to_writer(&stderr_writer),
    }

    if len(os.args) < 2 {
        fmt.eprintfln("Expected at least one argument for the command to run")
        print_help(1)
    }

    expect_args_finished :: proc(command: string) {
        extra := os.args[2:]
        if len(extra) > 0 {
            fmt.eprintfln(
                "Did not expect any extra argument to be passed to the `%s` command",
                command,
            )
            fmt.eprintfln("Got %d extra arguments", len(extra))
            os.exit(1)
        }
    }

    command: Command
    switch os.args[1] {
    case "build_c":
        command = BuildC{}
    case "run":
        command = Run{std_pipe, io.Reader(os.to_stream(os.stdin)), new(LongLivedInterpState)}
    case "help":
        expect_args_finished("help")
        print_help(0)
    case "lsp":
        expect_args_finished("lsp")
        lsp.run_lsp()
        return
    case:
        fmt.eprintfln("Unexpected command `%s`", os.args[1])
        print_help(1)
    }

    ref, watch := parse_args_after_command(os.args[2:])
    if ref.func_name == "" {
        fmt.eprintfln("Error: Got an empty string as the function name")
        print_help(1)
    }
    early_exit_info: compiler.EarlyExitInfo =
        watch ? new(compiler.ExitEarly) : compiler.NeverExitEarly{}
    a: utils.Arena
    defer utils.cleanup_arena(&a, expect_empty = true, delete_blocks = true)
    for {
        defer utils.cleanup_arena(&a, expect_empty = false, delete_blocks = false)
        ret := compile(&a, ref, std_pipe, command, early_exit_info)
        switch exit_early in early_exit_info {
        case compiler.NeverExitEarly:
            os.exit(ret)
        case ^compiler.ExitEarly:
            switch &exit_early_value in exit_early {
            case compiler.ExitEarlyAwaitingSourceCodeChange:
                if len(exit_early_value.files) == 0 {
                    assert(ret != 0)
                    fmt.eprintln(
                        "`-watch` flag error: Compilation failed too serverly to know when to reattempt compilation",
                    )
                    os.exit(ret)
                }
                fmt.println("Awaiting source code change...")
                for !compiler.source_code_changed(&exit_early_value) {
                    time.sleep(10 * time.Millisecond)
                }
            case compiler.ExitEarlyAfterSourceCodeChanged:
            }
        }
        fmt.println(utils.ansi_clear + "Recompiling after source code change...")
    }
}

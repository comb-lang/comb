package main

// TODO: Implement some stuff so that all examples work in the interpreter and
//       the C emitter
// TODO: Check that the interpreter, the JS emitter, and the C emitter all have
//       the same behavior in all the tests

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:testing"
import "utils"

CompilationFailed :: struct {
    compiler: utils.Pipe(string),
    status:   int,
}

CompilationSuccessful :: struct {
    compiler: utils.Pipe(string),
    program:  utils.Pipe(string),
}

RanExampleViaC :: union {
    CompilationFailed,
    CompilationSuccessful,
}

InterpretedExample :: struct {
    compiler:  utils.Pipe(string),
    program:   utils.Pipe(string),
    exit_code: int,
}

run_example_via_c :: proc(
    t: ^testing.T,
    a: ^utils.Arena,
    absolute_path: string,
    stdin_to_send: string,
) -> RanExampleViaC {
    compiler_pipe := utils.pipe_mock(a)
    executable: string
    cache := utils.empty_files_cache(a)
    defer utils.cleanup_files_cache(cache)
    status := compile(
        a,
        &cache,
        FunctionRef{absolute_path, "main"},
        compiler_pipe,
        BuildC{&executable},
        NeverExitEarly{},
    )
    compiler := utils.get_output(compiler_pipe)
    if status != 0 {
        return CompilationFailed{compiler, status}
    }
    if executable == "" {
        testing.fail(t)
        return nil
    }

    stdin_reader, stdin_writer, err := os.pipe()
    if err != nil {
        testing.fail_now(t, fmt.aprintf("Failed to create pipe: %#v", err))
    }
    defer os.close(stdin_reader)

    _, err2 := os.write(stdin_writer, transmute([]u8)stdin_to_send)
    os.close(stdin_writer)
    if err2 != nil {
        testing.fail_now(t, fmt.aprintf("Failed to write to pipe: %#v", err2))
    }

    // TODO: Check for memory leaks when the process runs
    state, stdout, stderr, err3 := os.process_exec(
        os.Process_Desc{command = []string{executable}, stdin = stdin_reader},
        context.allocator,
    )
    if err3 != nil {
        testing.fail_now(t, fmt.aprintf("Failed to run `%s`: %#v", executable, err3))
    }

    if state.exit_code != 0 {
        fmt.eprintfln(
            "Failed to run `%s`:\nExit code: %d\nStderr:\n%s\nStdout:\n%s",
            executable,
            state.exit_code,
            stdout,
            stderr,
        )
        testing.fail(t)
        return nil
    }
    return CompilationSuccessful{compiler, utils.Pipe(string){string(stdout), string(stderr)}}
}

interpret_example :: proc(
    t: ^testing.T,
    a: ^utils.Arena,
    func: FunctionRef,
    stdin: string = "",
) -> InterpretedExample {
    compiler_pipe := utils.pipe_mock(a)
    program_pipe := utils.pipe_mock(a)
    cache := utils.empty_files_cache(a)
    defer utils.cleanup_files_cache(cache)
    status := compile(
        a,
        &cache,
        func,
        compiler_pipe,
        Run{program_pipe, utils.make_reader(a, stdin), utils.arena_new(a, LongLivedInterpState)},
        NeverExitEarly{},
    )
    return InterpretedExample {
        utils.get_output(compiler_pipe),
        utils.get_output(program_pipe),
        status,
    }
}

@(test)
example_00_fizzbuzz :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(t, &a, FunctionRef{#directory + "examples/00_fizzbuzz.code", "main"})
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, ran.program.stderr == "")
    testing.expect(
        t,
        ran.program.stdout ==
        "1\n2\nFizz\n4\nBuzz\nFizz\n7\n8\nFizz\nBuzz\n11\nFizz\n13\n14\nFizzbuzz\n16\n17\nFizz\n19\nBuzz\nFizz\n22\n23\nFizz\nBuzz\n26\nFizz\n28\n29\nFizzbuzz\n31\n32\nFizz\n34\nBuzz\nFizz\n37\n38\nFizz\nBuzz\n41\nFizz\n43\n44\nFizzbuzz\n46\n47\nFizz\n49\nBuzz\nFizz\n52\n53\nFizz\nBuzz\n56\nFizz\n58\n59\nFizzbuzz\n61\n62\nFizz\n64\nBuzz\nFizz\n67\n68\nFizz\nBuzz\n71\nFizz\n73\n74\nFizzbuzz\n76\n77\nFizz\n79\nBuzz\nFizz\n82\n83\nFizz\nBuzz\n86\nFizz\n88\n89\nFizzbuzz\n91\n92\nFizz\n94\nBuzz\nFizz\n97\n98\nFizz\nBuzz\n",
    )
}

@(test)
example_01_factorial :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(
        t,
        &a,
        FunctionRef{#directory + "examples/01_factorial.code", "main"},
        "",
    )
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, ran.program.stderr == "")
    testing.expect(t, ran.program.stdout == "120\n")
}

@(test)
example_02_primes :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(t, &a, FunctionRef{#directory + "examples/02_primes.code", "main"})
    testing.expect(t, ran.exit_code == 0)
    // testing.expect(t, out.compiler.stderr == "") // TODO: Implement array bounds checking so this line can be uncommented
    testing.expect(t, ran.program.stderr == "")
    e := utils.TestingTextExpecter{0, ran.program.stdout, t}
    utils.expect_string(&e, "The number 1 is not prime\n")
    utils.expect_string(&e, "The number 2 is prime\n")
    utils.expect_string(&e, "The number 3 is prime\n")
    utils.expect_string(&e, "The number 4 is not prime\n")
    utils.expect_string(&e, "The number 5 is prime\n")
    utils.expect_string(&e, "The number 6 is not prime\n")
    utils.expect_string(&e, "The number 7 is prime\n")
    utils.expect_string(&e, "The number 8 is not prime\n")
    utils.expect_string(&e, "The number 9 is not prime\n")
    utils.expect_string(&e, "The number 10 is not prime\n")
    utils.expect_string(&e, "The number 11 is prime\n")
    utils.expect_string(&e, "The number 12 is not prime\n")
    utils.expect_string(&e, "The number 13 is prime\n")
    utils.expect_string(&e, "The number 14 is not prime\n")
    utils.expect_string(&e, "The number 15 is not prime\n")
    utils.expect_string(&e, "The number 16 is not prime\n")
    utils.expect_string(&e, "The number 17 is prime\n")
    utils.expect_string(&e, "The number 18 is not prime\n")
    utils.expect_string(&e, "The number 19 is prime\n")
    utils.expect_string(&e, "The number 20 is not prime\n")
    utils.expect_string(&e, "The number 21 is not prime\n")
    utils.expect_string(&e, "The number 22 is not prime\n")
    utils.expect_string(&e, "The number 23 is prime\n")
    utils.expect_string(&e, "The number 24 is not prime\n")
    utils.expect_string(&e, "The number 25 is not prime\n")
    utils.expect_string(&e, "The number 26 is not prime\n")
    utils.expect_string(&e, "The number 27 is not prime\n")
    utils.expect_string(&e, "The number 28 is not prime\n")
    utils.expect_string(&e, "The number 29 is prime\n")
    utils.expect_string(&e, "The number 30 is not prime\n")
    utils.expect_string(&e, "The number 31 is prime\n")
    utils.expect_string(&e, "The number 32 is not prime\n")
    utils.expect_string(&e, "The number 33 is not prime\n")
    utils.expect_string(&e, "The number 34 is not prime\n")
    utils.expect_string(&e, "The number 35 is not prime\n")
    utils.expect_string(&e, "The number 36 is not prime\n")
    utils.expect_string(&e, "The number 37 is prime\n")
    utils.expect_string(&e, "The number 38 is not prime\n")
    utils.expect_string(&e, "The number 39 is not prime\n")
    utils.expect_string(&e, "The number 40 is not prime\n")
    utils.expect_string(&e, "The number 41 is prime\n")
    utils.expect_string(&e, "The number 42 is not prime\n")
    utils.expect_string(&e, "The number 43 is prime\n")
    utils.expect_string(&e, "The number 44 is not prime\n")
    utils.expect_string(&e, "The number 45 is not prime\n")
    utils.expect_string(&e, "The number 46 is not prime\n")
    utils.expect_string(&e, "The number 47 is prime\n")
    utils.expect_string(&e, "The number 48 is not prime\n")
    utils.expect_string(&e, "The number 49 is not prime\n")
    utils.expect_string(&e, "The number 50 is not prime\n")
    utils.expect_string(&e, "The number 51 is not prime\n")
    utils.expect_string(&e, "The number 52 is not prime\n")
    utils.expect_string(&e, "The number 53 is prime\n")
    utils.expect_string(&e, "The number 54 is not prime\n")
    utils.expect_string(&e, "The number 55 is not prime\n")
    utils.expect_string(&e, "The number 56 is not prime\n")
    utils.expect_string(&e, "The number 57 is not prime\n")
    utils.expect_string(&e, "The number 58 is not prime\n")
    utils.expect_string(&e, "The number 59 is prime\n")
    utils.expect_string(&e, "The number 60 is not prime\n")
    utils.expect_string(&e, "The number 61 is prime\n")
    utils.expect_string(&e, "The number 62 is not prime\n")
    utils.expect_string(&e, "The number 63 is not prime\n")
    utils.expect_string(&e, "The number 64 is not prime\n")
    utils.expect_string(&e, "The number 65 is not prime\n")
    utils.expect_string(&e, "The number 66 is not prime\n")
    utils.expect_string(&e, "The number 67 is prime\n")
    utils.expect_string(&e, "The number 68 is not prime\n")
    utils.expect_string(&e, "The number 69 is not prime\n")
    utils.expect_string(&e, "The number 70 is not prime\n")
    utils.expect_string(&e, "The number 71 is prime\n")
    utils.expect_string(&e, "The number 72 is not prime\n")
    utils.expect_string(&e, "The number 73 is prime\n")
    utils.expect_string(&e, "The number 74 is not prime\n")
    utils.expect_string(&e, "The number 75 is not prime\n")
    utils.expect_string(&e, "The number 76 is not prime\n")
    utils.expect_string(&e, "The number 77 is not prime\n")
    utils.expect_string(&e, "The number 78 is not prime\n")
    utils.expect_string(&e, "The number 79 is prime\n")
    utils.expect_string(&e, "The number 80 is not prime\n")
    utils.expect_string(&e, "The number 81 is not prime\n")
    utils.expect_string(&e, "The number 82 is not prime\n")
    utils.expect_string(&e, "The number 83 is prime\n")
    utils.expect_string(&e, "The number 84 is not prime\n")
    utils.expect_string(&e, "The number 85 is not prime\n")
    utils.expect_string(&e, "The number 86 is not prime\n")
    utils.expect_string(&e, "The number 87 is not prime\n")
    utils.expect_string(&e, "The number 88 is not prime\n")
    utils.expect_string(&e, "The number 89 is prime\n")
    utils.expect_string(&e, "The number 90 is not prime\n")
    utils.expect_string(&e, "The number 91 is not prime\n")
    utils.expect_string(&e, "The number 92 is not prime\n")
    utils.expect_string(&e, "The number 93 is not prime\n")
    utils.expect_string(&e, "The number 94 is not prime\n")
    utils.expect_string(&e, "The number 95 is not prime\n")
    utils.expect_string(&e, "The number 96 is not prime\n")
    utils.expect_string(&e, "The number 97 is prime\n")
    utils.expect_string(&e, "The number 98 is not prime\n")
    utils.expect_string(&e, "The number 99 is not prime\n")
    utils.expect_string(&e, "The number 100 is not prime\n")
    utils.expect_finished(&e)
}

@(test)
example_03_fibonacci :: proc(t: ^testing.T) {
    file :: #directory + "examples/gitignore_fibonacci.txt"
    err := os.remove_all(file)
    testing.expect(t, err == nil || err.(os.General_Error) == .Not_Exist)

    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(t, &a, FunctionRef{#directory + "examples/03_fibonacci.code", "main"})
    testing.expect(t, ran.exit_code == 0)
    // testing.expect(ran.compiler.stderr == "") // TODO: Implement array bounds checking so this line can be uncommented

    data, err2 := os.read_entire_file(file, context.allocator)
    if err2 != nil {
        testing.fail_now(t, fmt.aprintf("Failed to read `%s`: %#v", file, err2))
    }
    defer delete(data, context.allocator)
    testing.expect(t, string(data) == "1597")
}

@(test)
example_04_linked_list :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(
        t,
        &a,
        FunctionRef{#directory + "examples/04_linked_list.code", "main"},
    )
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, ran.program.stderr == "")
    testing.expect(t, ran.program.stdout == "1\n2\n3\nReversed:\n3\n2\n1\n")
}

expect_ui_render :: proc(
    t: ^utils.TestingTextExpecter,
    text: string,
    focused_button_num: int,
    pos := #caller_location,
) {
    utils.expect_string(t, utils.ansi_clear + "- ", pos)
    utils.expect_string(t, text, pos)
    utils.expect_string(t, "\n", pos)
    for i in 1 ..= 3 {
        utils.expect_string(t, i == focused_button_num ? "- Focused button\n" : "- Button\n", pos)
        utils.expect_string(t, "  - Text ", pos)
        utils.expect_string(t, fmt.aprintf("%d", i), pos)
        utils.expect_string(t, "\n", pos)
    }
    utils.expect_string(t, "Enter either `next`, `prev`, `click`, or `quit`: ", pos)
}

@(test)
example_05_ui :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(
        t,
        &a,
        FunctionRef{#directory + "examples/05_ui.code", "main"},
        "next\nclick\nprev\nprev\nclick\nnext\nnext\nnext\nclick\nquit\n",
    )
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, ran.program.stderr == "")

    text_expecter := utils.TestingTextExpecter{0, ran.program.stdout, t}
    expect_ui_render(&text_expecter, "Initial text", 1)
    expect_ui_render(&text_expecter, "Initial text", 2) // After next
    expect_ui_render(&text_expecter, "Text 2", 2) // After click
    expect_ui_render(&text_expecter, "Text 2", 1) // After prev
    expect_ui_render(&text_expecter, "Text 2", 1) // After prev
    expect_ui_render(&text_expecter, "Text 1", 1) // After click
    expect_ui_render(&text_expecter, "Text 1", 2) // After next
    expect_ui_render(&text_expecter, "Text 1", 3) // After next
    expect_ui_render(&text_expecter, "Text 1", 3) // After next
    expect_ui_render(&text_expecter, "Text 3", 3) // After click
    utils.expect_string(&text_expecter, utils.ansi_clear)
    utils.expect_finished(&text_expecter)
}

/*
// OLD(METAPROGRAM_IN_C)
@(test)
buffered_pipe_test :: proc(t: ^testing.T) {
    str :: "Hello world\n"
    pipe, err := create_buffered_pipe()
    testing.expect(t, err == nil)
    defer close_buffered_pipe(pipe)
    os.write_string(pipe.writer, str)
    read_str, err2 := bufio.reader_read_string(pipe.bufio_reader, '\n')
    testing.expect(t, err2 == nil)
    if str != read_str {
        testing.fail_now(t, fmt.aprintf("Expected %q, got %q", str, read_str))
    }
}
*/

// TODO: Mock a browser to test the counter and conways game of life

@(test)
example_06_counter :: proc(t: ^testing.T) {
    file :: #directory + "examples/gitignore_counter/index.html"
    err := os.remove_all(file)
    testing.expect(t, err == nil || err.(os.General_Error) == .Not_Exist)

    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(t, &a, FunctionRef{#directory + "examples/06_counter.code", "build"})
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, os.exists(file))
}

@(test)
example_07_conways_game_of_life :: proc(t: ^testing.T) {
    file :: #directory + "examples/gitignore_conways_game_of_life/index.html"
    err := os.remove_all(file)
    testing.expect(t, err == nil || err.(os.General_Error) == .Not_Exist)

    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(
        t,
        &a,
        FunctionRef{#directory + "examples/07_conways_game_of_life.code", "build"},
    )
    testing.expect(t, ran.exit_code == 0)
    // testing.expect(t, ran.compiler_stderr == "") // TODO: Implement array bounds checking so this line can be uncommented
    testing.expect(t, os.exists(file))
}

@(test)
basic_fuzz_test :: proc(t: ^testing.T) {
    tmp_dir, err := os.temp_directory(context.allocator)
    if err != nil {
        testing.fail_now(t, "err != nil")
    }

    tmp_file, err2 := filepath.join([]string{tmp_dir, "fuzz.code"}, context.allocator)
    if err2 != nil {
        testing.fail_now(t, "err2 != nil")
    }

    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)

    for _ in 0 ..< 100 {
        code := utils.random_string(800)

        // `%q` rather then `%s` to escape invalid runes and ANSI terminal escape codes
        fmt.printfln("Randomly generated code is:\n%q", code)

        err3 := os.write_entire_file(tmp_file, transmute([]u8)code)
        if err3 != nil {
            testing.fail_now(t, "err3 != nil")
        }

        pipe := utils.pipe_mock(&a)
        defer utils.get_output(pipe)
        cache := utils.empty_files_cache(&a)
        defer utils.cleanup_files_cache(cache)
        compile(&a, &cache, FunctionRef{tmp_file, "main"}, pipe, BuildC{}, NeverExitEarly{})
    }
}

@(test)
basic_type_system_test :: proc(t: ^testing.T) {
    a := utils.Arena{}
    defer utils.delete_arena(&a, expect_empty = false)
    types := create_types(&a)
    defer fix_types(types)
    generic_args0 := make([]Type, 1)
    generic_args0[0] = .String
    generic_args1 := make([]Type, 1)
    generic_args1[0] = .Bool
    generic0 := create_type(&types, GenericTypeValue{GlobalValueWithGenericRef{7}, generic_args0})
    generic1 := create_type(&types, GenericTypeValue{GlobalValueWithGenericRef{7}, generic_args0})
    types.values.d[generic1.type].type = .Int
    generic2 := create_type(&types, GenericTypeValue{GlobalValueWithGenericRef{7}, generic_args1})
    testing.expect(t, generic0.type == generic1.type)
    generic0_initialised := get_type(types, generic0.type).value.type
    testing.expect(t, generic0_initialised == .Int)
    testing.expect(t, generic0.type != generic2.type)
}

@(test)
example_08_result :: proc(t: ^testing.T) {
    // TODO: Test inputs other than `dog`
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(
        t,
        &a,
        FunctionRef{#directory + "examples/08_result.code", "main"},
        "dog\n",
    )
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, ran.program.stderr == "")
    if ran.program.stdout != "Enter the name of an animal: You entered the animal dog\n" {
        testing.fail_now(t, fmt.aprintf("Got the stdout `%s`", ran.program.stdout))
    }
}

@(test)
example_09_hashmap :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(
        t,
        &a,
        FunctionRef{#directory + "examples/09_hashmap.code", "main"},
        "add\nbanana\nadd\napple\nadd\nbanana\nremove\napple\nexit\n",
    )
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, ran.program.stderr == "")
    // TODO: Implement the test
}

@(test)
example_10_geometry :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := run_example_via_c(t, &a, #directory + "examples/10_geometry.code", "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.compiler.stderr == c_warning)
    testing.expect(t, out.program.stderr == "")
    e := utils.TestingTextExpecter{0, out.program.stdout, t}
    utils.expect_string(&e, "                              cc                              \n")
    utils.expect_string(&e, "                    cccccccccccccccccccccc                    \n")
    utils.expect_string(&e, "                cccc                      cccc                \n")
    utils.expect_string(&e, "            cccc                              cccc            \n")
    utils.expect_string(&e, "          cccc                                  cccc          \n")
    utils.expect_string(&e, "        cccc                                      cccc        \n")
    utils.expect_string(&e, "      cccc                                          cccc      \n")
    utils.expect_string(&e, "      cc                                              cc      \n")
    utils.expect_string(&e, "    cc                                                  cc    \n")
    utils.expect_string(&e, "    cc                                                  cc    \n")
    utils.expect_string(&e, "  cc                                                      cc  \n")
    utils.expect_string(&e, "  cc                                                      cc  \n")
    utils.expect_string(&e, "  cc                                                      cc  \n")
    utils.expect_string(&e, "  cc                                                      cc  \n")
    utils.expect_string(&e, "  cc                                                      cc  \n")
    utils.expect_string(&e, "cccc                                                      cccc\n")
    utils.expect_string(&e, "  cc                                                      cctt\n")
    utils.expect_string(&e, "  cc                                                      tttt\n")
    utils.expect_string(&e, "  cc                                                    tttttt\n")
    utils.expect_string(&e, "  cc                                                  tttttttt\n")
    utils.expect_string(&e, "  cc                                                tttttttttt\n")
    utils.expect_string(&e, "    cc                                            tttttttttttt\n")
    utils.expect_string(&e, "    cc                                          tttttttttttttt\n")
    utils.expect_string(&e, "      cc                                      tttttttttttttttt\n")
    utils.expect_string(&e, "      cccc                                  tttttttttttttttttt\n")
    utils.expect_string(&e, "        cccc                              tttttttttttttttttttt\n")
    utils.expect_string(&e, "          cccc                          tttttttttttttttttttttt\n")
    utils.expect_string(&e, "            cccc                      tttttttttttttttttttttttt\n")
    utils.expect_string(&e, "                cccc                tttttttttttttttttttttttttt\n")
    utils.expect_string(&e, "                    cccccccccccccctttttttttttttttttttttttttttt\n")
    utils.expect_string(&e, "                              cctttttttttttttttttttttttttttttt\n")
    utils.expect_finished(&e)
}

@(test)
invalid_example_00_uninitialised_global_value_with_generics :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    file :: #directory + "examples/invalid/00_uninitialised_global_value_with_generics.code"
    ran := run_example_via_c(t, &a, file, "")
    if ran == nil {return}
    out := ran.(CompilationFailed)
    e := utils.TestingTextExpecter{0, out.compiler.stderr, t}
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + file + "` (15:13)\n")
    utils.expect_string(
        &e,
        "Expected a func type, but got an uninitialised global value with generics\n",
    )
    utils.expect_string(
        &e,
        "Hint: Try initialising the global value with something like `debug[T]`\n",
    )
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Erroneously checked with 1 error and 0 warnings in ")
    utils.expect_digits(&e)
    utils.expect_string(&e, ".")
    utils.expect_digits(&e)
    utils.expect_string(&e, " ms\n")
    utils.expect_finished(&e)
}

@(test)
invalid_example_01_wrong_identifier_casing :: proc(t: ^testing.T) {
    file :: #directory + "examples/invalid/01_wrong_identifier_casing.code"
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := run_example_via_c(t, &a, file, "")
    if ran == nil {return}
    out := ran.(CompilationSuccessful)
    testing.expect(t, out.program.stderr == "")
    testing.expect(t, out.program.stdout == "Hello world\n")
    testing.expect(t, out.compiler.stderr == c_warning)
    e := utils.TestingTextExpecter{0, out.compiler.stdout, t}
    fmt.println(out.compiler.stdout)
    utils.expect_string(&e, "Reading `" + file + "`...\n")
    utils.expect_string(&e, "Checking...\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Warning compiling `" + #directory)
    utils.expect_string(&e, "examples/invalid/01_wrong_identifier_casing.code` (7:8)\n")
    utils.expect_string(&e, "Expected generic names to be `CamelCase`, got `ok`\n")
    utils.expect_string(
        &e,
        "First character in a camel case identifier must be an uppercase letter\n",
    )
    utils.expect_string(&e, "Got 'o'\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Warning compiling `" + #directory)
    utils.expect_string(&e, "examples/invalid/01_wrong_identifier_casing.code` (7:12)\n")
    utils.expect_string(&e, "Expected generic names to be `CamelCase`, got `err`\n")
    utils.expect_string(
        &e,
        "First character in a camel case identifier must be an uppercase letter\n",
    )
    utils.expect_string(&e, "Got 'e'\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Successfully checked with 0 errors and 2 warnings in ")
    utils.expect_digits(&e)
    utils.expect_string(&e, ".")
    utils.expect_digits(&e)
    utils.expect_string(&e, " ms\n")
    utils.expect_string(&e, "Emitting C code...\n")
    utils.expect_done_message(&e)
    utils.expect_finished(&e)
}

@(test)
invalid_example_02_wrong_main_function_type :: proc(t: ^testing.T) {
    file :: #directory + "examples/invalid/02_wrong_main_function_type.code"
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := run_example_via_c(t, &a, file, "")
    if ran == nil {return}
    out := ran.(CompilationFailed)

    testing.expect(t, out.status == 1)

    e := utils.TestingTextExpecter{0, out.compiler.stdout, t}
    utils.expect_string(&e, "Reading `" + file + "`...\n")
    utils.expect_string(&e, "Checking...\n")
    utils.expect_done_message(&e)
    utils.expect_finished(&e)

    e = utils.TestingTextExpecter{0, out.compiler.stderr, t}
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + file + "`\n")
    utils.expect_string(&e, "Got the type `(String, Int) -> Int`\n")
    utils.expect_string(&e, "Expected the type `() -> Int`\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Erroneously checked with 1 error and 0 warnings in ")
    utils.expect_digits(&e)
    utils.expect_string(&e, ".")
    utils.expect_digits(&e)
    utils.expect_string(&e, " ms\n")
    utils.expect_finished(&e)
}

// Just to test `arena.odin`, so no proper error handling

TreeNode :: union {
    string,
    []TreeNode,
}

string_to_node :: proc(a: ^utils.Arena, i: ^int, text: string) -> TreeNode {
    for text[i^] == ' ' {
        i^ += 1
    }
    switch text[i^] {
    case '(':
        i^ += 1
        children := utils.arena_make(a, []TreeNode, 0, resizable = true)
        for text[i^] != ')' {
            child := string_to_node(a, i, text)
            utils.append_dynamic(&children, child)
        }
        i^ += 1
        utils.fix_resizable_dynamic(children)
        return children
    case '`':
        i^ += 1
        start := i^
        for text[i^] != '`' {
            i^ += 1
        }
        out := text[start:i^]
        i^ += 1
        return out
    case:
        panic("Unreachable")
    }
}

node_to_string := proc(d: ^[]byte, node: TreeNode) {
    switch n in node {
    case string:
        utils.append_dynamic(d, '`')
        for c in transmute([]byte)n {
            utils.append_dynamic(d, c)
        }
        utils.append_dynamic(d, '`')
    case []TreeNode:
        utils.append_dynamic(d, '(')
        first_child := true
        for child in n {
            if first_child == false {
                utils.append_dynamic(d, ' ')
            }
            node_to_string(d, child)
            first_child = false
        }
        utils.append_dynamic(d, ')')
    case:
        panic("Unreachable")
    }
}

@(test)
arena_test :: proc(t: ^testing.T) {
    a := utils.Arena{}
    defer utils.delete_arena(&a, expect_empty = false)

    my_tree_string :: "(((`a` `b` `c`) `d` (`e` `f`)) `g` `h`)"

    index := 0
    my_tree_node := string_to_node(&a, &index, my_tree_string)
    testing.expect(t, index == len(my_tree_string))

    // Even though `my_tree_dynamic_array` was not created with
    // `resizable = false`, it is still resizable because the last
    // allocation is always resizable
    my_tree_dynamic_array := utils.arena_make(&a, []byte, 0, resizable = false)
    defer utils.dealloc(raw_data(my_tree_dynamic_array))
    node_to_string(&my_tree_dynamic_array, my_tree_node)
    my_tree_string2 := string(my_tree_dynamic_array)
    if my_tree_string != my_tree_string2 {
        testing.fail_now(t, fmt.aprintf("%s != %s", my_tree_string, my_tree_string2))
    }

    my_int := utils.arena_new(&a, int)
    defer utils.dealloc(my_int)
    my_int^ = 5
    defer testing.expect(t, my_int^ == 5)

    fibonacci_numbers := utils.arena_make(&a, []int, 0, resizable = false)
    defer utils.dealloc(raw_data(fibonacci_numbers))
    utils.append_dynamic_elems(&fibonacci_numbers, 0, 1, 1)

    for len(fibonacci_numbers) < 15 {
        utils.append_dynamic(
            &fibonacci_numbers,
            fibonacci_numbers[len(fibonacci_numbers) - 1] +
            fibonacci_numbers[len(fibonacci_numbers) - 2],
        )
    }

    fibonacci_string := utils.aprintf(&a, "%v", fibonacci_numbers)
    defer utils.dealloc(raw_data(fibonacci_string))
    if fibonacci_string != "[0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377]" {
        testing.fail_now(t, fmt.aprintf("Fibonacci string is %q", fibonacci_string))
    }
}

@(test)
example_12_lambda_functions :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(
        t,
        &a,
        FunctionRef{#directory + "examples/12_lambda_functions.code", "main"},
    )
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.program.stdout == "")
    testing.expect(t, ran.program.stderr == "")
    testing.expect(t, ran.compiler.stderr == "")
}

@(test)
invalid_example_03_constants_and_reassignables_with_same_name :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    path :: #directory + "examples/invalid/03_constants_and_reassignables_with_same_name.code"
    ran := interpret_example(t, &a, FunctionRef{path, "main"})
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.program.stderr == "")
    testing.expect(t, ran.program.stdout == "")
    testing.expect(t, ran.compiler.stderr == "")
    e := utils.TestingTextExpecter{0, ran.compiler.stdout, t}
    utils.expect_string(&e, "Reading `" + path + "`...\n")
    utils.expect_string(&e, "Checking...\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Warning compiling `" + path + "` (7:2)\n")
    utils.expect_string(
        &e,
        "Declaring variable called `hello` when variable called `hello$` is already declared\n",
    )
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Warning compiling `" + path + "` (13:5)\n")
    utils.expect_string(
        &e,
        "Declaring variable called `hi$` when variable called `hi` is already declared\n",
    )
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Successfully checked with 0 errors and 2 warnings in ")
    utils.expect_digits(&e)
    utils.expect_string(&e, ".")
    utils.expect_digits(&e)
    utils.expect_string(&e, " ms\n")
    utils.expect_string(&e, "Interpreting `main`...\n")
    utils.expect_done_message(&e)
    utils.expect_finished(&e)
}

@(test)
invalid_example_04_invalid_globals :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    path :: #directory + "examples/invalid/04_invalid_globals.code"
    ran := interpret_example(t, &a, FunctionRef{path, "main"})
    testing.expect(t, ran.exit_code == 1)
    testing.expect(t, ran.program.stdout == "")
    testing.expect(t, ran.program.stderr == "")

    e := utils.TestingTextExpecter{0, ran.compiler.stdout, t}
    utils.expect_string(&e, "Reading `" + path + "`...\n")
    utils.expect_string(&e, "Checking...\n")
    utils.expect_done_message(&e)
    utils.expect_finished(&e)

    e = utils.TestingTextExpecter{0, ran.compiler.stderr, t}
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + path + "` (4:12)\n")
    utils.expect_string(&e, "Expected the type `String` but got the type `UInt`\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + path + "` (4:19)\n")
    utils.expect_string(&e, "Expected the type `String` but got the type `UInt`\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + path + "` (8:17)\n")
    utils.expect_string(&e, "The variable `E` is not defined in the file `" + path + "`\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + path + "` (19:22)\n")
    utils.expect_string(
        &e,
        "The variable `InvalidType` is not defined in the file `" + path + "`\n",
    )
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + path + "` (11:13)\n")
    utils.expect_string(&e, "The value before `.len` is of type `Array[Int]`\n")
    utils.expect_string(&e, "Expected a string type, an array type, or an OrderedHashSet type\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Erroneously checked with 5 errors and 0 warnings in ")
    utils.expect_digits(&e)
    utils.expect_string(&e, ".")
    utils.expect_digits(&e)
    utils.expect_string(&e, " ms\n")
    utils.expect_finished(&e)
}

@(test)
example_13_numbers :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    ran := interpret_example(t, &a, FunctionRef{#directory + "examples/13_numbers.code", "main"})
    testing.expect(t, ran.exit_code == 0)
    testing.expect(t, ran.compiler.stderr == "")
    testing.expect(t, ran.program.stdout == "")
    testing.expect(t, ran.program.stderr == "")
}

@(test)
invalid_example_05_invalid_global_sum_type :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    file :: #directory + "examples/invalid/05_invalid_global_sum_type.code"
    ran := interpret_example(t, &a, FunctionRef{file, "main"}, "")
    testing.expect(t, ran.exit_code == 1)
    // TODO: Check ran.compiler
    testing.expect(t, ran.program.stdout == "")
    testing.expect(t, ran.program.stderr == "")
}

@(test)
invalid_example_06_mismatching_types :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    file :: #directory + "examples/invalid/06_mismatching_types.code"
    ran := interpret_example(t, &a, FunctionRef{file, "main"}, "")
    testing.expect(t, ran.exit_code == 1)
    e := utils.TestingTextExpecter{0, ran.compiler.stderr, t}
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + file + "` (13:10)\n")
    utils.expect_string(&e, "Expected the type `Pos` but got the type `String`\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Erroneously checked with 1 error and 0 warnings in ")
    utils.expect_digits(&e)
    utils.expect_string(&e, ".")
    utils.expect_digits(&e)
    utils.expect_string(&e, " ms\n")
    utils.expect_finished(&e)
    testing.expect(t, ran.program.stdout == "")
    testing.expect(t, ran.program.stderr == "")
}

@(test)
invalid_example_07_uses_compiletime_value_at_runtime :: proc(t: ^testing.T) {
    a: utils.Arena
    defer utils.delete_arena(&a, expect_empty = false)
    file :: #directory + "examples/invalid/07_uses_compiletime_value_at_runtime.code"
    ran := interpret_example(t, &a, FunctionRef{file, "main"}, "")
    testing.expect(t, ran.exit_code == 1)
    testing.expect(t, ran.program.stdout == "")
    testing.expect(t, ran.program.stderr == "")
    e := utils.TestingTextExpecter{0, ran.compiler.stderr, t}
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Error compiling `" + file + "` (2:13)\n")
    utils.expect_string(&e, "This value can only be used at compile time\n")
    utils.expect_string(&e, "\n")
    utils.expect_string(&e, "Erroneously checked with 1 error and 0 warnings in ")
    utils.expect_digits(&e)
    utils.expect_string(&e, ".")
    utils.expect_digits(&e)
    utils.expect_string(&e, " ms\n")
    utils.expect_finished(&e)
}

// TODO: Add a fuzz test where the code that gets compiled never has any syntax errors

// TODO: Add a fuzz test where the code that gets compiled has no invalid utf8 runes

// TODO: Test big numbers implementation

//@(test)
//run_examples :: proc(t: ^testing.T) {
//    examples_dir := fmt.aprintf("%s/examples", #directory)
//
//    opened, err := os.open(examples_dir)
//    if err != nil {
//        testing.fail_now(t, fmt.aprintf("Failed to open examples directory: %#v", err))
//    }
//
//    files: []os.File_Info
//    files, err = os.read_dir(opened, -1, context.allocator)
//    if err != nil {
//        testing.fail_now(t, fmt.aprintf("Failed to read examples directory: %#v", err))
//    }
//
//    for file in files {
//        if strings.ends_with(file.fullpath, ".code") {
//            run_example(t, file.fullpath)
//        }
//    }
//}

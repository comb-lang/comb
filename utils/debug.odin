package utils

import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:os"

debug_tokenizer :: false // You can use this to debug the parser
debug_parser :: false
debug_checker :: false
debug_emitter :: false
debug_key_to_index :: false
debug_interpreter :: false
debug_diagnostics :: false
debug_arena :: false
debug_dynamic_array :: false
debug_builder :: false

debug_writer := io.Writer{}

@(private = "file")
format :: "func: %q, call_site: %v, call_info: %q"

when ODIN_DEBUG {
    call_stack: ^CallStack = nil
    debug_nesting := 0

    CallStack :: struct {
        handle_debug:    bool,
        func_name:       string,
        call_info:       string,
        call_site:       runtime.Source_Code_Location,
        call_site_stack: ^CallStack,
    }

    should_debug :: proc() -> bool {
        return call_stack != nil && call_stack.handle_debug == true
    }

    print_call_stack :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
        if verb != 'v' {
            return false
        }
        stack := cast(^CallStack)arg.data
        for {
            fmt.wprintf(
                fi.writer,
                format + "\n",
                stack.func_name,
                stack.call_site,
                stack.call_info,
            )
            stack = stack.call_site_stack
            if stack == nil {
                return true
            }
        }
    }

    CallStackOnDebug :: CallStack
    StringOnDebug :: string
} else {
    CallStackOnDebug :: struct {}
    StringOnDebug :: struct {}
}

get_call_stack_on_debug :: proc(loc := #caller_location) -> CallStackOnDebug {
    when ODIN_DEBUG {
        return CallStackOnDebug{should_debug(), "get_call_stack_on_debug", "", loc, call_stack}
    } else {
        return CallStackOnDebug{}
    }
}

DebugValue :: struct(T: typeid) {
    v:             T,
    created_at:    CallStackOnDebug,
    creation_info: StringOnDebug,
    mutated_at:    CallStackOnDebug,
}

to_debug_value :: proc(
    v: $T,
    creation_info_format := "",
    creation_info_args: ..any,
    loc := #caller_location,
) -> DebugValue(T) {
    call_stack := get_call_stack_on_debug(loc)
    when ODIN_DEBUG {
        creation_info := fmt.aprintf(creation_info_format, ..creation_info_args)
    } else {
        creation_info := StringOnDebug{}
    }
    return DebugValue(T){v, call_stack, creation_info, call_stack}
}

@(deferred_in_out = call_finished)
call :: proc(
    loc: runtime.Source_Code_Location,
    func_name: string,
    info_format: string,
    info_args: ..any,
    enable_debug: bool = false,
) {
    when ODIN_DEBUG {
        info := fmt.aprintf(info_format, ..info_args)
        call_stack = new_clone(
            CallStack{enable_debug || should_debug(), func_name, info, loc, call_stack},
        )
        debug(format, func_name, loc, info)
        debug_nesting += 1
    }
}

call_finished :: proc(
    _: runtime.Source_Code_Location,
    func_name: string,
    info_format: string,
    info_args: ..any,
    enable_debug := false,
) {
    when ODIN_DEBUG {
        debug("%s returned from", func_name)
        debug_nesting -= 1
        call_stack = call_stack.call_site_stack
    }
}

// Print flushing is necessary even when we know that a flushing print call is
// going to happen because flush does not work properly
// See https://github.com/odin-lang/Odin/issues/6656
// In this case flush is not necersarry because we are printing to a writer
// rather than using the `fmt.print` family
flush_needed :: false

debug :: proc(format: string, args: ..any, loc := #caller_location) {
    when ODIN_DEBUG {
        if should_debug() == false {
            return
        }

        if debug_writer.data == nil {
            buffer := make([]byte, 1024)
            bufio_writer := new(bufio.Writer)
            bufio.writer_init_with_buf(bufio_writer, os.to_stream(os.stdout), buffer)
            debug_writer = bufio.writer_to_writer(bufio_writer)
        }

        max_line_length :: 100
        line_padding := (4 * debug_nesting) + 4

        formatted := fmt.aprintf(format, ..args)
        defer delete_string(formatted)
        assert(formatted != "")

        for _ in 0 ..< debug_nesting {
            fmt.wprint(debug_writer, "│   ", flush = flush_needed)
        }
        fmt.wprint(debug_writer, "├── ", flush = flush_needed)

        if line_padding >= max_line_length {
            fmt.wprintln(debug_writer, formatted)
        } else {
            col := line_padding
            if len(formatted) > 1 {
                for char in formatted[0:len(formatted) - 1] {
                    fmt.wprint(debug_writer, char, flush = flush_needed)
                    if char == '\n' {
                        col = 0
                    } else {
                        col += 1
                        if col >= max_line_length {
                            fmt.wprint(debug_writer, "\n...", flush = flush_needed)
                            col = 3
                        } else {
                            continue
                        }
                    }
                    for _ in col ..< line_padding {
                        fmt.wprint(debug_writer, ' ', flush = flush_needed)
                    }
                    col = line_padding
                }
            }
            fmt.wprintfln(debug_writer, "%c", formatted[len(formatted) - 1])
        }

        when false {
            fmt.wprint(debug_writer, "Press enter to continue")
            buf := make([]byte, 1)
            os.read(os.stdin, buf)
            delete(buf)
            fmt.wprint(debug_writer, up_line + erase_line)
        }
    }
}

print_arg :: proc(arg_name: string, arg_value: any) {
    debug("arg `%s`: %v", arg_name, arg_value)
}

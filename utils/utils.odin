package utils

import "base:runtime"
import "core:bufio"
import "core:fmt"
import "core:io"
import "core:math/rand"
import "core:os"
import "core:strings"
import "core:testing"

Position :: struct {
    line: uint,
    col:  uint `json:"character"`,
}

get_position :: proc(p: Pos) -> Position {
    out := Position{0, 0}
    for char in p.file.code[:p.index] {
        if char == '\n' {
            out.line += 1
            out.col = 0
        } else {
            out.col += 1
        }
    }
    return out
}

OverriddenCloseHandlerStreamData :: struct {
    original_stream: io.Stream,
    new_data:        rawptr,
    new_close_proc:  proc(data: ^OverriddenCloseHandlerStreamData),
}

overridden_close_handler_stream_proc :: proc(
    data: rawptr,
    mode: io.Stream_Mode,
    p: []byte,
    offset: i64,
    whence: io.Seek_From,
) -> (
    i64,
    io.Error,
) {
    d := cast(^OverriddenCloseHandlerStreamData)data
    if mode != .Close {
        return d.original_stream.procedure(d.original_stream.data, mode, p, offset, whence)
    }
    assert(p == nil && offset == 0 && whence == io.Seek_From(0))
    d->new_close_proc()
    return 0, nil
}

override_close_handler :: proc(
    s: io.Stream,
    new_close_proc_data: rawptr,
    new_close_proc: proc(data: ^OverriddenCloseHandlerStreamData),
) -> io.Stream {
    return io.Stream {
        overridden_close_handler_stream_proc,
        new_clone(OverriddenCloseHandlerStreamData{s, new_close_proc_data, new_close_proc}),
    }
}

panicf :: proc(format: string, args: ..any) -> ! {
    panic(fmt.aprintf(format, ..args))
}

reader_stream_proc :: proc(
    data: rawptr,
    mode: io.Stream_Mode,
    p: []byte,
    offset: i64,
    whence: io.Seek_From,
) -> (
    i64,
    io.Error,
) {
    assert(offset == 0 && whence == nil)
    if mode == .Close {
        assert(len(p) == 0)
        return 0, nil
    }
    assert(mode == .Read)
    d := (^[]byte)(data)
    end := min(len(d), len(p))
    for b, i in d[:end] {
        p[i] = b
    }
    d^ = d[end:]
    if len(p) > end {
        return i64(end), .EOF
    }
    return i64(end), .None
}

make_reader :: proc(a: ^Arena, s: string) -> io.Reader {
    data := arena_new(a, []byte)
    data^ = transmute([]byte)s
    return io.Reader{reader_stream_proc, data}
}

panic_stream_proc :: proc(
    _: rawptr,
    _: io.Stream_Mode,
    _: []byte,
    _: i64,
    _: io.Seek_From,
) -> (
    i64,
    io.Error,
) {
    panic("Unreachable")
}

panic_stream :: io.Stream{panic_stream_proc, nil}

string_builder_stream_proc :: proc(
    data: rawptr,
    mode: io.Stream_Mode,
    p: []byte,
    offset: i64,
    whence: io.Seek_From,
) -> (
    i64,
    io.Error,
) {
    assert(offset == 0 && whence == nil)
    if mode == .Close || mode == .Flush {
        assert(len(p) == 0)
        return 0, nil
    }
    if mode != .Write {
        panicf("Mode is %v", mode)
    }
    d := (^[]byte)(data)
    append_dynamic_elems(d, ..p)
    return i64(len(p)), nil
}

StringBuilder :: io.Writer

make_builder :: proc(a: ^Arena, loc := #caller_location) -> StringBuilder {
    call(loc, "make_builder", "", enable_debug = debug_builder)
    data := arena_new(a, []byte)
    data^ = arena_make(a, []byte, 0, resizable = true)
    return StringBuilder{string_builder_stream_proc, data}
}

finish_building :: proc(s: StringBuilder, loc := #caller_location) -> string {
    call(loc, "finish_building", "", enable_debug = debug_builder)
    data := (^[]byte)(s.data)
    fix_resizable_dynamic(data^)
    return string(data^)
}

delete_builder :: proc(s: StringBuilder, loc := #caller_location) {
    call(loc, "delete_builder", "", enable_debug = debug_builder)
    data := (^[]byte)(s.data)
    dealloc(raw_data(data^))
    dealloc(data)
}

aprintf :: proc(a: ^Arena, format: string, args: ..any) -> string {
    array := arena_make(a, []byte, 0)
    fmt.wprintf(io.Writer{string_builder_stream_proc, &array}, format, ..args)
    return string(array)
}

// FNV-1a 32-bit
simple_hash :: proc(data: []byte) -> u32 {
    h: u32 = 0x811c_9dc5 // FNV 32-bit offset basis
    for b in data {
        h = (h ~ u32(b)) * 0x0100_0193 // FNV 32-bit prime
    }
    return h
}

simple_hash_string :: proc(data: string) -> u32 {
    return simple_hash(transmute([]byte)data)
}

/*
file_mock :: proc() -> (^os.File, ^strings.Builder) {
    builder := new_clone(strings.builder_make())
    stream_proc: os.File_Stream_Proc : proc(
        stream_data: rawptr,
        mode: os.File_Stream_Mode,
        p: []byte,
        offset: i64,
        whence: io.Seek_From,
        _: runtime.Allocator,
    ) -> (
        i64,
        os.Error,
    ) {
        assert(mode == .Write)
        assert(offset == 0)
        assert(whence == io.Seek_From(0))
        file := cast(^os.File)stream_data
        builder := cast(^strings.Builder)file.stream.data
        strings.write_bytes(builder, p)
        return i64(len(p)), nil
    }
    return new_clone(os.File{nil, os.File_Stream{stream_proc, builder}}), builder
}
*/

pipe_mock :: proc(a: ^Arena) -> Pipe(StringBuilder) {
    stdout_writer := make_builder(a)
    stderr_writer := make_builder(a)
    return Pipe(io.Writer){stdout_writer, stderr_writer}
}

get_output :: proc(p: Pipe(StringBuilder)) -> Pipe(string) {
    return Pipe(string){finish_building(p.stdout), finish_building(p.stderr)}
}

random_string :: proc(max_length: int, gen := context.random_generator) -> string {
    context.random_generator = gen
    length := rand.int_max(max_length / 4)
    out := make([]byte, length * 4)
    for i in 0 ..< length {
        char_group := rand.uint32()
        out[i * 4] = byte(char_group)
        out[i * 4 + 1] = byte(char_group >> 8)
        out[i * 4 + 2] = byte(char_group >> 16)
        out[i * 4 + 3] = byte(char_group >> 32)
    }
    return string(out)
}

ansi_clear :: "\033[1;1H\033[2J"

/*
// OLD(METAPROGRAM_IN_C)
EOT :: '\x04'

BufferedPipe :: struct {
    writer:        ^os.File,
    file_reader:   ^os.File,
    stream_reader: io.Stream,
    bufio_reader:  ^bufio.Reader,
}

create_buffered_pipe :: proc() -> (BufferedPipe, os.Error) {
    file_reader, writer, err := os.pipe()
    if err != nil {
        return BufferedPipe{}, err
    }
    out := BufferedPipe{writer, file_reader, os.to_stream(file_reader), new(bufio.Reader)}
    bufio.reader_init(out.bufio_reader, out.stream_reader)
    return out, nil
}

close_buffered_pipe :: proc(pipe: BufferedPipe) {
    bufio.reader_destroy(pipe.bufio_reader)
    free(pipe.bufio_reader)
    io.close(pipe.stream_reader)
    os.close(pipe.writer)
    os.close(pipe.file_reader)
}

// read_message :: proc(pipe: BufferedPipe) -> (string, bool) {
//     msg, err := bufio.reader_read_string(pipe.bufio_reader, EOT)
//     if err != nil {
//         assert(msg == "")
//         fmt.eprintln("Failed to read string: %#v", err)
//         return "", false
//     }
// }
*/

TestingTextExpecter :: struct {
    index:    uint,
    got_text: string,
    t:        ^testing.T,
}

build_error_info :: proc(
    first_location: runtime.Source_Code_Location,
    other_locations: []runtime.Source_Code_Location,
) -> strings.Builder {
    format :: "expect_string called from %v"
    b := strings.builder_make()
    fmt.sbprintfln(&b, format, first_location)
    for other_location in other_locations {
        fmt.sbprintfln(&b, format, other_location)
    }
    return b
}

// The string returned is the error
expect_string_helper :: proc(
    expected: string,
    got: string,
    first_location: runtime.Source_Code_Location,
    other_locations: []runtime.Source_Code_Location,
) -> string {
    if got == expected {
        return ""
    }
    builder := build_error_info(first_location, other_locations)
    strings.write_string(&builder, "Mismatching expect_string: Got ")
    strings.write_quoted_string(&builder, got)
    strings.write_string(&builder, " expected ")
    strings.write_quoted_string(&builder, expected)
    return strings.to_string(builder)
}

expect_string :: proc(
    comparer: ^TestingTextExpecter,
    expected: string,
    first_location := #caller_location,
    other_locations: ..runtime.Source_Code_Location,
) {
    start := comparer.index
    comparer.index += len(expected)
    err := expect_string_helper(
        expected,
        comparer.got_text[start:min(comparer.index, uint(len(comparer.got_text)))],
        first_location,
        other_locations,
    )
    if err != "" {
        testing.fail_now(comparer.t, err)
    }
}

expect_string2 :: proc(r: ^bufio.Reader, expected: string, loc := #caller_location) {
    got := make([]byte, len(expected))
    defer delete(got)
    n := 0
    for n < len(expected) {
        num_read, err := bufio.reader_read(r, got)
        if num_read == 0 {
            panicf("Failed to read: %v", err)
        }
        assert(err == nil || err == .EOF)
        expect_string_helper(expected[n:n + num_read], string(got[:num_read]), loc, nil)
        n += num_read
    }
}

parse_uint :: proc(r: ^bufio.Reader) -> uint {
    b, err := bufio.reader_read_byte(r)
    assert(err == nil)
    assert('0' <= b && b <= '9')

    n := uint(b - '0')
    for {
        b, err = bufio.reader_read_byte(r)
        if err == .EOF {
            return n
        }
        assert(err == nil)
        if !('0' <= b && b <= '9') {
            bufio.reader_unread_byte(r)
            return n
        }

        n = n * 10 + uint(b - '0')
    }
}

is_nothing_char :: proc(c: byte) -> bool {
    return c == ' ' || c == '\t'
}

is_letter :: proc(c: $T) -> bool {
    return c == '_' || ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
}

is_alphanumeric_char_any :: proc(c: $T) -> bool {
    return is_letter(c) || ('0' <= c && c <= '9')
}

is_alphanumeric_char :: proc(c: byte) -> bool {
    return is_alphanumeric_char_any(c)
}

is_digit_char :: proc(c: byte) -> bool {
    return '0' <= c && c <= '9'
}

is_symbol_char :: proc(c: byte) -> bool {
    switch c {
    case '=', '+', '-', '*', '/', '.', '<', '>', '%', '~', '&', '!':
        return true
    case:
        return false
    }
}

expect_digits :: proc(
    e: ^TestingTextExpecter,
    first_location := #caller_location,
    other_locations: ..runtime.Source_Code_Location,
) {
    if e.index >= len(e.got_text) {
        builder := build_error_info(first_location, other_locations)
        strings.write_string(&builder, "Expected text is longer than got text")
        testing.fail_now(e.t, strings.to_string(builder))
    }

    if !is_digit_char(e.got_text[e.index]) {
        builder := build_error_info(first_location, other_locations)
        fmt.sbprintf(&builder, "Expected a digit, but got the character '%c'", e.got_text[e.index])
        testing.fail_now(e.t, strings.to_string(builder))
    }

    e.index += 1

    for e.index < len(e.got_text) && is_digit_char(e.got_text[e.index]) {
        e.index += 1
    }
}

expect_done_message :: proc(
    e: ^TestingTextExpecter,
    first_location := #caller_location,
    other_locations: ..runtime.Source_Code_Location,
) {
    expect_string(e, "Done in ")
    expect_digits(e)
    expect_string(e, ".")
    expect_digits(e)
    expect_string(e, " ms!\n")
}

expect_finished :: proc(e: ^TestingTextExpecter) {
    if e.index < len(e.got_text) {
        testing.fail_now(e.t, fmt.aprintf("Got additional code %q", e.got_text[e.index:]))
    } else {
        testing.expect(e.t, e.index == len(e.got_text))
    }
}

/*
// Supported operations:
// - Iterate in order with the key and the value
// - Append to the end
// - Lookup based on the key

OrderedMapElement :: struct(Key: typeid, Value: typeid) {
    key: Key,
    value: Value,
}

OrderedMap :: struct(Key: typeid, Value: typeid) {
    elements: []OrderedMapElement(Key, Value),
    map: map[Key]uint,
}

combine_u32 :: proc(a: u32, b: u32) -> (out: u64) {
    out = u64(a) << 32
    out += u64(b)
    return
}

separate_u64 :: proc(combined: u64) -> (a: u32, b: u32) {
    a = u32(combined >> 32)
    b = u32(combined)
    return
}
*/

/*
append2 :: proc(
    a_array: ^[dynamic]$A,
    b_array: ^[^]$B,
    a_elem: A,
    b_elem: B,
) -> runtime.Allocator_Error {
    a_raw := (^runtime.Raw_Dynamic_Array)(a_array)

    if a_raw.len + 1 > a_raw.cap {
        if a_raw.allocator.procedure == nil {
            a_raw.allocator = context.allocator
            assert(a_raw.allocator.procedure != nil)
        }

        new_cap := 2 * a_raw.cap + runtime.DEFAULT_DYNAMIC_ARRAY_CAPACITY

        a_raw_data, err := runtime.mem_resize(
            a_raw.data,
            a_raw.cap * size_of(A),
            new_cap * size_of(A),
            align_of(A),
            a_raw.allocator,
        )
        if err != nil {
            return err
        }
        a_raw.data = raw_data(a_raw_data)

        b_raw_data, err2 := runtime.mem_resize(
            b_array^,
            a_raw.cap * size_of(B),
            new_cap * size_of(B),
            align_of(B),
            a_raw.allocator,
        )
        if err2 != nil {
            return err2
        }
        b_array^ = ([^]B)(raw_data(b_raw_data))

        a_raw.cap = new_cap
    }

    ([^]A)(a_raw.data)[a_raw.len] = a_elem
    b_array[a_raw.len] = b_elem
    a_raw.len += 1

    return nil
}
*/

// Like a dynamic array, except can also be inserted into in average O(1) time
DoubleDynamic :: struct(T: typeid) {
    elems:       [dynamic]T,
    start_index: int,
}

dynamic_grow_front :: proc(array: ^DoubleDynamic($T), grow_by: int) {
    old_start_index := array.start_index
    array.start_index += grow_by

    old_elems := array.elems
    array.elems = make([dynamic]T, len(array.elems) + grow_by, cap(array.elems) + grow_by)

    copy_slice(array.elems[array.start_index:], old_elems[old_start_index:])
    delete(old_elems)
}

dynamic_insert :: proc(array: ^DoubleDynamic($T), elems: ..T) {
    if array.start_index < len(elems) {
        dynamic_grow_front(array, max(len(array.elems), len(elems)))
    }
    array.start_index -= len(elems)
    copy(array.elems[array.start_index:], elems)
}

dynamic_append_elem :: proc(array: ^DoubleDynamic($T), elem: T) {
    append_elem(&array.elems, elem)
}

dynamic_to_fixed :: proc(array: DoubleDynamic($T)) -> []T {
    return array.elems[array.start_index:]
}

up_line :: "\033[A"
erase_line :: "\033[2K"
to_beginning :: "\r"

/*
join :: proc(slice0: $TypeDefinition/[]$Elem, slice1: ..Elem) -> []Elem {
    dyn := slice.clone_to_dynamic(slice0)
    append_elems(&dyn, ..slice1)
    return dyn[:]
}

OutputBuilder :: struct {
    file:   ^os.File,
    b:      strings.Builder,
    footer: string,
}

write :: proc(output_builder: ^OutputBuilder) {
    strings.write_string(&output_builder.b, footer)
    fmt.fprint(output_builder.file, strings.to_string(output_builder.b))
    strings.builder_destroy(&output_builder.b)
}
*/

Pipe :: struct(T: typeid) {
    stdout: T,
    stderr: T,
}

/*
debug_exact_checked_type :: proc(s: ^CheckerState, type: Type) {
    debug("type is %#v", type)
    debug_nesting += 1
    #partial switch value in type {
    case GenericTypeRef:
        info, index := get_info(s.generic_types[:], value.generic_type_index)
        debug("simplified index is %d", index)
        debug("generic arg")
        debug_nesting += 1
        debug_exact_checked_type(s, info.generic_arg)
        debug_nesting -= 1
        debug("global type index is %d", info.global_type_index)
    // debug("type %v", info.type)
    }
    debug_nesting -= 1
}
*/

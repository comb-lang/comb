package main

import "utils"

Type :: enum u32 {
    DynamicArrayOfStrings, // []String
    StringToNil, // (String)
    StringStringToNil, // (String, String)
    StringToString, // (String) -> String
    StringAnyOrderedHashmap, // OrderedHashMap[String, Any]
    NoArgsToNil, // () -> ()
    ArrayOfStringsToNil, // ([]String)
    IntToNil, // (Int) -> ()
    StringUintToString, // (String, UInt) -> String
    StringAnyOrderedHashmapAndStringToString, // (OrderedHashMap[String, Any], String) -> String
    StringToBool, // (String) -> Bool
    NoArgsToInt, // () -> Int
    StringAnyToNil, // (String, Any) -> ()
    StringToAny, // (String) -> Any
    FloatToUInt, // (Float) -> UInt

    // {
    //   contains: (String) -> Bool,
    //   set: (String, Any) -> (),
    //   get: (String) -> Any
    // }
    CompilerCache,

    // {
    //   emit_js_code: string_any_ordered_hashmap_and_string_to_string_type,
    //   cache: compiler_cache_type,
    // }
    Compiler,
    CompilerToInt, // (Compiler) -> Int

    // {
    //   url: String,
    //   method: String,
    // }
    HttpRequest,

    // {body: String}
    HttpResponseBody,

    // TODO: Add more response types:
    // - Ico
    // - Gif
    // - Jpeg
    // - Js
    // - Json
    // - Png
    // - Svg
    // - Url_Encoded
    // - Xml
    // - Zip
    // - Wasm
    //
    // <
    //   .Plain{body: String},
    //   .Css{body: String},
    //   .Html{body: String},
    // >
    HttpResponse,

    // (HttpRequest) -> HttpResponse
    HttpRequestHandler,

    // (HttpRequestHandler) -> ()
    HttpRequestHandlerToNil,

    // {
    //   set_handler: (HttpRequestHandler) -> (),
    //   listen_and_serve: () -> (),
    //   port: Int,
    // }
    HttpServer,

    // () -> HttpServer
    NoArgsToHttpServer,

    // Primitive types
    String = max(u32),
    UInt = max(u32) - 1, // Numbers without a decimal >= 0
    Int = max(u32) - 2, // Numbers without a decimal
    Float = max(u32) - 3, // Numbers with a decimal
    Char = max(u32) - 5,
    ImportedFile = max(u32) - 6, // TODO: Create a struct type for the type of imported files rather than using `imported_file_type`
    Any = max(u32) - 7,
    Type = max(u32) - 8,
    Bool = max(u32) - 9,
    Invalid = max(u32) - 10,
    Unknown = max(u32) - 11, // TODO: Ideally `unknown_type` would not be necersarry
    MaxIndex = max(u32) - 12,
}

response_type_variant_index_to_content_type :: proc(variant_index: u32) -> string {
    switch variant_index {
    case 0:
        return "text/plain"
    case 1:
        return "text/css"
    case 2:
        return "text/html"
    case:
        panic("Unreachable")
    }
}

GlobalType :: struct {
    global: GlobalValueWithoutGenericRef,
}

GenericTypeValue :: struct {
    global:       GlobalValueWithGenericRef,
    generic_args: []Type,
}

get_hash_of_array_of_types :: proc(arr: []Type) -> u32 {
    result: u32 = 0
    for value in arr {
        result ~= u32(value)
    }
    return result
}

TypeKey :: union {
    ArrayType,
    OrderedHashMapTypeWithStringKey,
    OrderedHashMapTypeWithIntKey,
    FuncType,
    SumType,
    StructType,

    // Both of these are included to be able to prevent cycles
    GlobalType, // The `TypeValue.type` is the initialised type, which is set to `unknown_type` when the global is not initialised yet
    GenericTypeValue, // The `TypeValue.type` is the initialised type, which is set to `unknown_type` when the generic is not initialised yet
}

fix_types :: proc(t: Types) {
    utils.fix_key_to_index(t.m)
    utils.fix_resizable_multi(t.values)
}

create_types :: proc(a: ^utils.Arena) -> Types {
    out := Types {
        utils.make_key_to_index(a, utils.KeyToIndex(TypeKey)),
        utils.arena_make_multi(a, utils.Multi(TypeValue), 0, resizable = true),
    }

    array_with_string_type := utils.arena_make(a, []Type, 1)
    array_with_string_type[0] = .String

    array_with_float_type := utils.arena_make(a, []Type, 1)
    array_with_float_type[0] = .Float

    array_with_2string_types := utils.arena_make(a, []Type, 2)
    array_with_2string_types[0] = .String
    array_with_2string_types[1] = .String

    array_with_int_type := utils.arena_make(a, []Type, 1)
    array_with_int_type[0] = .Int

    array_with_uint_type := utils.arena_make(a, []Type, 1)
    array_with_uint_type[0] = .UInt

    array_with_string_any_ordered_hash_map_and_string := utils.arena_make(a, []Type, 2)
    array_with_string_any_ordered_hash_map_and_string[0] = .StringAnyOrderedHashmap
    array_with_string_any_ordered_hash_map_and_string[1] = .String

    array_with_dynamic_array_of_strings := utils.arena_make(a, []Type, 1)
    array_with_dynamic_array_of_strings[0] = .DynamicArrayOfStrings

    array_with_string_uint_types := utils.arena_make(a, []Type, 2)
    array_with_string_uint_types[0] = .String
    array_with_string_uint_types[1] = .UInt

    array_with_compiler_type := utils.arena_make(a, []Type, 1)
    array_with_compiler_type[0] = .Compiler

    array_with_string_any_type := utils.arena_make(a, []Type, 2)
    array_with_string_any_type[0] = .String
    array_with_string_any_type[1] = .Any

    array_with_bool_type := utils.arena_make(a, []Type, 1)
    array_with_bool_type[0] = .Bool

    array_with_any_type := utils.arena_make(a, []Type, 1)
    array_with_any_type[0] = .Any

    array_with_http_request := utils.arena_make(a, []Type, 1)
    array_with_http_request[0] = .HttpRequest

    array_with_http_response := utils.arena_make(a, []Type, 1)
    array_with_http_response[0] = .HttpResponse

    array_with_http_request_handler := utils.arena_make(a, []Type, 1)
    array_with_http_request_handler[0] = .HttpRequestHandler

    array_with_http_server := utils.arena_make(a, []Type, 1)
    array_with_http_server[0] = .HttpServer

    assert(.DynamicArrayOfStrings == create_type(&out, ArrayType{0, .String}).type)
    assert(.StringToNil == create_type(&out, FuncType{array_with_string_type, nil}).type)
    assert(.StringStringToNil == create_type(&out, FuncType{array_with_2string_types, nil}).type)
    assert(
        .StringToString ==
        create_type(&out, FuncType{array_with_string_type, array_with_string_type}).type,
    )
    assert(
        .StringAnyOrderedHashmap == create_type(&out, OrderedHashMapTypeWithStringKey{.Any}).type,
    )
    assert(.NoArgsToNil == create_type(&out, FuncType{nil, nil}).type)
    assert(
        .ArrayOfStringsToNil ==
        create_type(&out, FuncType{array_with_dynamic_array_of_strings, nil}).type,
    )
    assert(.IntToNil == create_type(&out, FuncType{array_with_int_type, nil}).type)
    assert(
        .StringUintToString ==
        create_type(&out, FuncType{array_with_string_uint_types, array_with_string_type}).type,
    )
    assert(
        .StringAnyOrderedHashmapAndStringToString ==
        create_type(&out, FuncType{array_with_string_any_ordered_hash_map_and_string, array_with_string_type}).type,
    )
    assert(
        .StringToBool ==
        create_type(&out, FuncType{array_with_string_type, array_with_bool_type}).type,
    )
    assert(.NoArgsToInt == create_type(&out, FuncType{nil, array_with_int_type}).type)
    assert(.StringAnyToNil == create_type(&out, FuncType{array_with_string_any_type, nil}).type)
    assert(
        .StringToAny ==
        create_type(&out, FuncType{array_with_string_type, array_with_any_type}).type,
    )
    assert(
        .FloatToUInt ==
        create_type(&out, FuncType{array_with_float_type, array_with_uint_type}).type,
    )

    positions := utils.arena_make_multi(a, utils.Multi(utils.Pos), 3)
    positions.d[0] = utils.unknown_pos
    positions.d[1] = utils.unknown_pos
    positions.d[2] = utils.unknown_pos

    compiler_cache_map := utils.make_key_to_index(a, utils.KeyToIndex(string))
    i, _ := utils.lookup_or_insert(&compiler_cache_map, "contains", utils.string_to_index_procs)
    assert(i.index == 0)
    i, _ = utils.lookup_or_insert(&compiler_cache_map, "set", utils.string_to_index_procs)
    assert(i.index == 1)
    i, _ = utils.lookup_or_insert(&compiler_cache_map, "get", utils.string_to_index_procs)
    assert(i.index == 2)
    utils.fix_key_to_index(compiler_cache_map)

    compiler_cache_types := utils.arena_make(a, []Type, 3)
    compiler_cache_types[0] = .StringToBool
    compiler_cache_types[1] = .StringAnyToNil
    compiler_cache_types[2] = .StringToAny

    assert(
        .CompilerCache ==
        create_type(&out, StructType{compiler_cache_map, positions, utils.array_to_multi(compiler_cache_types)}).type,
    )

    compiler_map := utils.make_key_to_index(a, utils.KeyToIndex(string))
    i, _ = utils.lookup_or_insert(&compiler_map, "emit_js_code", utils.string_to_index_procs)
    assert(i.index == 0)
    i, _ = utils.lookup_or_insert(&compiler_map, "cache", utils.string_to_index_procs)
    assert(i.index == 1)
    utils.fix_key_to_index(compiler_map)

    compiler_types := utils.arena_make(a, []Type, 2)
    compiler_types[0] = .StringAnyOrderedHashmapAndStringToString
    compiler_types[1] = .CompilerCache

    assert(
        .Compiler ==
        create_type(&out, StructType{compiler_map, positions, utils.array_to_multi(compiler_types)}).type,
    )

    assert(
        .CompilerToInt ==
        create_type(&out, FuncType{array_with_compiler_type, array_with_int_type}).type,
    )

    http_request_map := utils.make_key_to_index(a, utils.KeyToIndex(string))
    i, _ = utils.lookup_or_insert(&http_request_map, "url", utils.string_to_index_procs)
    assert(i.index == 0)
    i, _ = utils.lookup_or_insert(&http_request_map, "method", utils.string_to_index_procs)
    assert(i.index == 1)
    utils.fix_key_to_index(http_request_map)

    http_request_types := utils.arena_make(a, []Type, 2)
    http_request_types[0] = .String
    http_request_types[1] = .String
    assert(
        .HttpRequest ==
        create_type(&out, StructType{http_request_map, positions, utils.array_to_multi(http_request_types)}).type,
    )

    http_response_body_map := utils.make_key_to_index(a, utils.KeyToIndex(string))
    i, _ = utils.lookup_or_insert(&http_response_body_map, "body", utils.string_to_index_procs)
    assert(i.index == 0)
    utils.fix_key_to_index(http_response_body_map)

    assert(
        .HttpResponseBody ==
        create_type(&out, StructType{http_response_body_map, positions, utils.array_to_multi(array_with_string_type)}).type,
    )

    http_response_map := utils.make_key_to_index(a, utils.KeyToIndex(string))
    i, _ = utils.lookup_or_insert(&http_response_map, "Plain", utils.string_to_index_procs)
    assert(i.index == 0)
    i, _ = utils.lookup_or_insert(&http_response_map, "Css", utils.string_to_index_procs)
    assert(i.index == 1)
    i, _ = utils.lookup_or_insert(&http_response_map, "Html", utils.string_to_index_procs)
    assert(i.index == 2)
    utils.fix_key_to_index(http_response_map)

    http_response_types := utils.arena_make(a, []Type, 3)
    http_response_types[0] = .HttpResponseBody
    http_response_types[1] = .HttpResponseBody
    http_response_types[2] = .HttpResponseBody

    assert(
        .HttpResponse ==
        create_type(&out, SumType{http_response_map, positions, utils.array_to_multi(http_response_types)}).type,
    )

    assert(
        .HttpRequestHandler ==
        create_type(&out, FuncType{array_with_http_request, array_with_http_response}).type,
    )

    assert(
        .HttpRequestHandlerToNil ==
        create_type(&out, FuncType{array_with_http_request_handler, nil}).type,
    )

    http_server_map := utils.make_key_to_index(a, utils.KeyToIndex(string))
    i, _ = utils.lookup_or_insert(&http_server_map, "set_handler", utils.string_to_index_procs)
    assert(i.index == 0)
    i, _ = utils.lookup_or_insert(
        &http_server_map,
        "listen_and_serve",
        utils.string_to_index_procs,
    )
    assert(i.index == 1)
    i, _ = utils.lookup_or_insert(&http_server_map, "port", utils.string_to_index_procs)
    assert(i.index == 2)
    utils.fix_key_to_index(http_server_map)

    http_server_types := utils.arena_make(a, []Type, 3)
    http_server_types[0] = .HttpRequestHandlerToNil
    http_server_types[1] = .NoArgsToNil
    http_server_types[2] = .Int
    assert(
        .HttpServer ==
        create_type(&out, StructType{http_server_map, positions, utils.array_to_multi(http_server_types)}).type,
    )

    assert(.NoArgsToHttpServer == create_type(&out, FuncType{nil, array_with_http_server}).type)

    return out
}

TypeValue :: struct {
    // aliases: [dynamic]string, // TODO

    // Either `.unknown_type` or a simplification of the type
    // Should only be a simplification of the type if the type is `GlobalType`
    // or `GenericTypeValue`
    type: Type,
}

Types :: struct {
    m:      utils.KeyToIndex(TypeKey),
    values: utils.Multi(TypeValue),
}

GotType :: struct {
    key:   TypeKey,
    value: TypeValue,
}

get_type :: proc(types: Types, t: Type) -> GotType {
    if t > Type.MaxIndex {
        return GotType{nil, TypeValue{}}
    }
    return GotType{types.m.keys[t].key, types.values.d[t]}
}

CreatedType :: struct {
    type:       Type,
    type_value: TypeValue,
    result:     utils.Result,
}

create_type :: proc(types: ^Types, value: TypeKey, loc := #caller_location) -> CreatedType {
    when utils.debug_checker {
        print_call(loc, "create_type")
        debug("value: %v", value)
    }
    type, result := utils.lookup_or_insert(
        &types.m,
        value,
        utils.KeyToIndexProcs(TypeKey){hash_type_value, type_key_is_equal},
        loc,
    )
    if result == .Inserted {
        utils.resize_multi(&types.values, len(types.m.keys))
        types.values.d[type.index] = TypeValue{.Unknown}
    }

    out := CreatedType{Type(type.index), types.values.d[type.index], result}
    when utils.debug_checker {
        debug("out: %v", out)
    }
    return out
}

hash_type_value :: proc(value: TypeKey) -> u32 {
    switch v in value {
    case ArrayType:
        return v.length ~ u32(v.item_type)
    case OrderedHashMapTypeWithStringKey:
        return u32(v.value_type) + 1
    case OrderedHashMapTypeWithIntKey:
        return u32(v.value_type) + 2
    case SumType:
        return hash_sum_type(v)
    case StructType:
        return hash_struct_type(v)
    case FuncType:
        return hash_func_type(v)
    case GenericTypeValue:
        return v.global.index ~ get_hash_of_array_of_types(v.generic_args)
    case GlobalType:
        return u32(v.global.index)
    }
    panic("Unreachable")
}

hash_struct_type :: proc(value: StructType) -> u32 {
    result: u32
    for field, i in value.m.keys {
        for c in field.key {
            result ~= u32(c) ~ u32(i)
        }
        result ~= u32(value.types.d[i])
    }
    return result
}

hash_sum_type :: proc(value: SumType) -> u32 {
    result: u32
    for variant, i in value.m.keys {
        for c in variant.key {
            result ~= u32(c)
        }
        result ~= u32(value.payloads.d[i])
    }
    return result
}

hash_func_type :: proc(value: FuncType) -> u32 {
    result: u32
    for arg in value.args {
        result ~= u32(arg)
    }
    for ret in value.return_types {
        result ~= u32(ret)
    }
    return result
}

type_key_is_equal :: proc(a: TypeKey, b: TypeKey) -> bool {
    switch va in a {
    case OrderedHashMapTypeWithStringKey:
        vb, ok := b.(OrderedHashMapTypeWithStringKey)
        return ok && va.value_type == vb.value_type
    case OrderedHashMapTypeWithIntKey:
        vb, ok := b.(OrderedHashMapTypeWithIntKey)
        return ok && va.value_type == vb.value_type
    case ArrayType:
        vb, ok := b.(ArrayType)
        return ok && va.length == vb.length && va.item_type == vb.item_type
    case SumType:
        vb, ok := b.(SumType)
        if !ok {
            return false
        }
        return sum_types_are_equal(va, vb)
    case StructType:
        vb, ok := b.(StructType)
        if !ok {
            return false
        }
        return struct_types_are_equal(va, vb)
    case FuncType:
        vb, ok := b.(FuncType)
        if !ok {
            return false
        }
        return func_types_are_equal(va, vb)
    case GenericTypeValue:
        vb, ok := b.(GenericTypeValue)
        if !ok {
            return false
        }
        if va.global.index != vb.global.index {
            return false
        }
        if len(va.generic_args) != len(vb.generic_args) {
            return false
        }
        for arg, i in va.generic_args {
            if arg != vb.generic_args[i] {
                return false
            }
        }
        return true
    case GlobalType:
        vb, ok := b.(GlobalType)
        if !ok {
            return false
        }
        return va.global == vb.global
    case:
        panic("Unreachable")
    }
}

struct_types_are_equal :: proc(a: StructType, b: StructType) -> bool {
    if len(a.m.keys) != len(b.m.keys) {
        return false
    }
    for a_key, i in a.m.keys {
        if a_key.key != b.m.keys[i].key {
            return false
        }
        if a.types.d[i] != b.types.d[i] {
            return false
        }
    }
    return true
}

sum_types_are_equal :: proc(a: SumType, b: SumType) -> bool {
    if len(a.m.keys) != len(b.m.keys) {
        return false
    }
    for a_key, i in a.m.keys {
        if a_key.key != b.m.keys[i].key {
            return false
        }
        if a.payloads.d[i] != b.payloads.d[i] {
            return false
        }
    }
    return true
}

func_types_are_equal :: proc(a: FuncType, b: FuncType) -> bool {
    if len(a.args) != len(b.args) {
        return false
    }
    if len(a.return_types) != len(b.return_types) {
        return false
    }
    for arg, i in a.args {
        if arg != b.args[i] {
            return false
        }
    }
    for ret, i in a.return_types {
        if ret != b.return_types[i] {
            return false
        }
    }
    return true
}

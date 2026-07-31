package main

Type :: enum u32 {
    dynamic_array_of_strings, // []String
    string_to_nil_type, // (String)
    string_string_to_nil_type, // (String, String)
    string_to_string_type, // (String) -> String
    string_any_ordered_hashmap_type, // OrderedHashMap[String, Any]
    no_args_to_nil_type, // () -> ()
    array_of_strings_to_nil_type, // ([]String)
    int_to_nil_type, // (Int) -> ()
    string_uint_to_string_type, // (String, UInt) -> String
    string_any_ordered_hashmap_and_string_to_string_type, // (OrderedHashMap[String, Any], String) -> String
    string_to_bool_type, // (String) -> Bool
    no_args_to_int_type, // () -> Int
    string_any_to_nil_type, // (String, Any) -> ()
    string_to_any_type, // (String) -> Any
    float_to_uint_type, // (Float) -> UInt

    // {
    //   contains: (String) -> Bool,
    //   set: (String, Any) -> (),
    //   get: (String) -> Any
    // }
    compiler_cache_type,

    // {
    //   emit_js_code: string_any_ordered_hashmap_and_string_to_string_type,
    //   cache: compiler_cache_type,
    // }
    compiler_type,
    compiler_to_int_type, // (Compiler) -> Int

    // {
    //   url: String,
    //   method: String,
    // }
    http_request_type,

    // {body: String}
    http_response_body_type,

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
    http_response_type,

    // (HttpRequest) -> HttpResponse
    http_request_handler_type,

    // (HttpRequestHandler) -> ()
    http_request_handler_to_nil_type,

    // {
    //   set_handler: (HttpRequestHandler) -> (),
    //   listen_and_serve: () -> (),
    //   port: Int,
    // }
    http_server_type,

    // () -> HttpServer
    no_args_to_http_server_type,

    // Primitive types
    string_type = max(u32),
    uint_type = max(u32) - 1, // Numbers without a decimal >= 0
    int_type = max(u32) - 2, // Numbers without a decimal
    float_type = max(u32) - 3, // Numbers with a decimal
    char_type = max(u32) - 5,
    imported_file_type = max(u32) - 6, // TODO: Create a struct type for the type of imported files rather than using `imported_file_type`
    any_type = max(u32) - 7,
    type_type = max(u32) - 8,
    bool_type = max(u32) - 9,
    invalid_type = max(u32) - 10,
    unknown_type = max(u32) - 11, // TODO: Ideally `unknown_type` would not be necersarry
    max_index = max(u32) - 12,
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
    StructType, // The `TypeValue.type` is the initialisation function

    // Both of these are included to be able to prevent cycles
    GlobalType, // The `TypeValue.type` is the initialised type, which is set to `unknown_type` when the global is not initialised yet
    GenericTypeValue, // The `TypeValue.type` is the initialised type, which is set to `unknown_type` when the generic is not initialised yet
}

init_struct_type :: proc(types: ^Types, type: Type, fields: []Type) {
    assert(types.values.d[type].type == .unknown_type)

    return_types := make([]Type, 1) // TODO: free `return_types`
    return_types[0] = type

    t := create_type(types, FuncType{fields, return_types}).type
    types.values.d[type].type = t
}

fix_types :: proc(t: Types) {
    fix_key_to_index(t.m)
    fix_resizable_multi(t.values)
}

create_types :: proc(a: ^Arena) -> Types {
    out := Types {
        make_key_to_index(a, KeyToIndex(TypeKey)),
        arena_make_multi(a, Multi(TypeValue), 0, resizable = true),
    }

    array_with_string_type := arena_make(a, []Type, 1)
    array_with_string_type[0] = .string_type

    array_with_float_type := arena_make(a, []Type, 1)
    array_with_float_type[0] = .float_type

    array_with_2string_types := arena_make(a, []Type, 2)
    array_with_2string_types[0] = .string_type
    array_with_2string_types[1] = .string_type

    array_with_int_type := arena_make(a, []Type, 1)
    array_with_int_type[0] = .int_type

    array_with_uint_type := arena_make(a, []Type, 1)
    array_with_uint_type[0] = .uint_type

    array_with_string_any_ordered_hash_map_and_string := arena_make(a, []Type, 2)
    array_with_string_any_ordered_hash_map_and_string[0] = .string_any_ordered_hashmap_type
    array_with_string_any_ordered_hash_map_and_string[1] = .string_type

    array_with_dynamic_array_of_strings := arena_make(a, []Type, 1)
    array_with_dynamic_array_of_strings[0] = .dynamic_array_of_strings

    array_with_string_uint_types := arena_make(a, []Type, 2)
    array_with_string_uint_types[0] = .string_type
    array_with_string_uint_types[1] = .uint_type

    array_with_compiler_type := arena_make(a, []Type, 1)
    array_with_compiler_type[0] = .compiler_type

    array_with_string_any_type := arena_make(a, []Type, 2)
    array_with_string_any_type[0] = .string_type
    array_with_string_any_type[1] = .any_type

    array_with_bool_type := arena_make(a, []Type, 1)
    array_with_bool_type[0] = .bool_type

    array_with_any_type := arena_make(a, []Type, 1)
    array_with_any_type[0] = .any_type

    array_with_http_request := arena_make(a, []Type, 1)
    array_with_http_request[0] = .http_request_type

    array_with_http_response := arena_make(a, []Type, 1)
    array_with_http_response[0] = .http_response_type

    array_with_http_request_handler := arena_make(a, []Type, 1)
    array_with_http_request_handler[0] = .http_request_handler_type

    array_with_http_server := arena_make(a, []Type, 1)
    array_with_http_server[0] = .http_server_type

    assert(.dynamic_array_of_strings == create_type(&out, ArrayType{0, .string_type}).type)
    assert(.string_to_nil_type == create_type(&out, FuncType{array_with_string_type, nil}).type)
    assert(
        .string_string_to_nil_type ==
        create_type(&out, FuncType{array_with_2string_types, nil}).type,
    )
    assert(
        .string_to_string_type ==
        create_type(&out, FuncType{array_with_string_type, array_with_string_type}).type,
    )
    assert(
        .string_any_ordered_hashmap_type ==
        create_type(&out, OrderedHashMapTypeWithStringKey{.any_type}).type,
    )
    assert(.no_args_to_nil_type == create_type(&out, FuncType{nil, nil}).type)
    assert(
        .array_of_strings_to_nil_type ==
        create_type(&out, FuncType{array_with_dynamic_array_of_strings, nil}).type,
    )
    assert(.int_to_nil_type == create_type(&out, FuncType{array_with_int_type, nil}).type)
    assert(
        .string_uint_to_string_type ==
        create_type(&out, FuncType{array_with_string_uint_types, array_with_string_type}).type,
    )
    assert(
        .string_any_ordered_hashmap_and_string_to_string_type ==
        create_type(&out, FuncType{array_with_string_any_ordered_hash_map_and_string, array_with_string_type}).type,
    )
    assert(
        .string_to_bool_type ==
        create_type(&out, FuncType{array_with_string_type, array_with_bool_type}).type,
    )
    assert(.no_args_to_int_type == create_type(&out, FuncType{nil, array_with_int_type}).type)
    assert(
        .string_any_to_nil_type ==
        create_type(&out, FuncType{array_with_string_any_type, nil}).type,
    )
    assert(
        .string_to_any_type ==
        create_type(&out, FuncType{array_with_string_type, array_with_any_type}).type,
    )
    assert(
        .float_to_uint_type ==
        create_type(&out, FuncType{array_with_float_type, array_with_uint_type}).type,
    )

    positions := arena_make_multi(a, Multi(Pos), 3)
    positions.d[0] = unknown_pos
    positions.d[1] = unknown_pos
    positions.d[2] = unknown_pos

    compiler_cache_map := make_key_to_index(a, KeyToIndex(string))
    i, _ := lookup_or_insert(&compiler_cache_map, "contains", string_to_index_procs)
    assert(i.index == 0)
    i, _ = lookup_or_insert(&compiler_cache_map, "set", string_to_index_procs)
    assert(i.index == 1)
    i, _ = lookup_or_insert(&compiler_cache_map, "get", string_to_index_procs)
    assert(i.index == 2)
    fix_key_to_index(compiler_cache_map)

    compiler_cache_types := arena_make(a, []Type, 3)
    compiler_cache_types[0] = .string_to_bool_type
    compiler_cache_types[1] = .string_any_to_nil_type
    compiler_cache_types[2] = .string_to_any_type

    assert(
        .compiler_cache_type ==
        create_type(&out, StructType{compiler_cache_map, positions, array_to_multi(compiler_cache_types)}).type,
    )

    compiler_map := make_key_to_index(a, KeyToIndex(string))
    i, _ = lookup_or_insert(&compiler_map, "emit_js_code", string_to_index_procs)
    assert(i.index == 0)
    i, _ = lookup_or_insert(&compiler_map, "cache", string_to_index_procs)
    assert(i.index == 1)
    fix_key_to_index(compiler_map)

    compiler_types := arena_make(a, []Type, 2)
    compiler_types[0] = .string_any_ordered_hashmap_and_string_to_string_type
    compiler_types[1] = .compiler_cache_type

    assert(
        .compiler_type ==
        create_type(&out, StructType{compiler_map, positions, array_to_multi(compiler_types)}).type,
    )

    assert(
        .compiler_to_int_type ==
        create_type(&out, FuncType{array_with_compiler_type, array_with_int_type}).type,
    )

    http_request_map := make_key_to_index(a, KeyToIndex(string))
    i, _ = lookup_or_insert(&http_request_map, "url", string_to_index_procs)
    assert(i.index == 0)
    i, _ = lookup_or_insert(&http_request_map, "method", string_to_index_procs)
    assert(i.index == 1)
    fix_key_to_index(http_request_map)

    http_request_types := arena_make(a, []Type, 2)
    http_request_types[0] = .string_type
    http_request_types[1] = .string_type
    assert(
        .http_request_type ==
        create_type(&out, StructType{http_request_map, positions, array_to_multi(http_request_types)}).type,
    )

    http_response_body_map := make_key_to_index(a, KeyToIndex(string))
    i, _ = lookup_or_insert(&http_response_body_map, "body", string_to_index_procs)
    assert(i.index == 0)
    fix_key_to_index(http_response_body_map)

    assert(
        .http_response_body_type ==
        create_type(&out, StructType{http_response_body_map, positions, array_to_multi(array_with_string_type)}).type,
    )

    http_response_map := make_key_to_index(a, KeyToIndex(string))
    i, _ = lookup_or_insert(&http_response_map, "Plain", string_to_index_procs)
    assert(i.index == 0)
    i, _ = lookup_or_insert(&http_response_map, "Css", string_to_index_procs)
    assert(i.index == 1)
    i, _ = lookup_or_insert(&http_response_map, "Html", string_to_index_procs)
    assert(i.index == 2)
    fix_key_to_index(http_response_map)

    http_response_types := arena_make(a, []Type, 3)
    http_response_types[0] = .http_response_body_type
    http_response_types[1] = .http_response_body_type
    http_response_types[2] = .http_response_body_type

    assert(
        .http_response_type ==
        create_type(&out, SumType{http_response_map, positions, array_to_multi(http_response_types)}).type,
    )

    assert(
        .http_request_handler_type ==
        create_type(&out, FuncType{array_with_http_request, array_with_http_response}).type,
    )

    assert(
        .http_request_handler_to_nil_type ==
        create_type(&out, FuncType{array_with_http_request_handler, nil}).type,
    )

    http_server_map := make_key_to_index(a, KeyToIndex(string))
    i, _ = lookup_or_insert(&http_server_map, "set_handler", string_to_index_procs)
    assert(i.index == 0)
    i, _ = lookup_or_insert(&http_server_map, "listen_and_serve", string_to_index_procs)
    assert(i.index == 1)
    i, _ = lookup_or_insert(&http_server_map, "port", string_to_index_procs)
    assert(i.index == 2)
    fix_key_to_index(http_server_map)

    http_server_types := arena_make(a, []Type, 3)
    http_server_types[0] = .http_request_handler_to_nil_type
    http_server_types[1] = .no_args_to_nil_type
    http_server_types[2] = .int_type
    assert(
        .http_server_type ==
        create_type(&out, StructType{http_server_map, positions, array_to_multi(http_server_types)}).type,
    )

    assert(
        .no_args_to_http_server_type ==
        create_type(&out, FuncType{nil, array_with_http_server}).type,
    )

    init_struct_type(&out, .compiler_type, compiler_types)
    init_struct_type(&out, .compiler_cache_type, compiler_cache_types)
    init_struct_type(&out, .http_request_type, http_request_types)
    init_struct_type(&out, .http_response_body_type, array_with_string_type)
    init_struct_type(&out, .http_server_type, http_server_types)

    return out
}

TypeValue :: struct {
    // aliases: [dynamic]string, // TODO
    type: Type, // Usually `unknown_type`
}

Types :: struct {
    m:      KeyToIndex(TypeKey),
    values: Multi(TypeValue),
}

GotType :: struct {
    key:   TypeKey,
    value: TypeValue,
}

get_type :: proc(types: Types, t: Type) -> GotType {
    if t > Type.max_index {
        return GotType{nil, TypeValue{}}
    }
    return GotType{types.m.keys[t].key, types.values.d[t]}
}

CreatedType :: struct {
    type:       Type,
    type_value: TypeValue,
    result:     Result,
}

create_type :: proc(types: ^Types, value: TypeKey, loc := #caller_location) -> CreatedType {
    when debug_checker {
        print_call(loc, "create_type")
        debug("value: %v", value)
    }
    type, result := lookup_or_insert(
        &types.m,
        value,
        KeyToIndexProcs(TypeKey){hash_type_value, type_key_is_equal},
        loc,
    )
    if result == .Inserted {
        resize_multi(&types.values, len(types.m.keys))
        types.values.d[type.index] = TypeValue{.unknown_type}
    }

    out := CreatedType{Type(type.index), types.values.d[type.index], result}
    when debug_checker {
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


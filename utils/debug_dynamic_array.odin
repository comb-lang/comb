package utils

debug_dynamic_array_append :: proc(
    a: ^DebugValue([dynamic]$E),
    elems: ..E,
    loc := #caller_location,
) {
    append_elems(&a.v, ..elems, loc = loc)
    a.mutated_at = get_call_stack_on_debug(loc)
}

debug_dynamic_array_to_slice :: proc(a: DebugValue([dynamic]$E)) -> DebugValue([]E) {
    return DebugValue([]E){a.v[:], a.created_at, a.mutated_at}
}

debug_dynamic_array_len :: proc(a: DebugValue([dynamic]$E)) -> int {
    return len(a.v)
}

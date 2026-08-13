package utils

// Zero collision "key to index" implementation

// TODO: Benchmarks:
// - without the hash being cached in `Key`

import "core:mem"

Index :: struct {
    index: u32, // An index into `KeyToIndex.keys`
}

Key :: struct(T: typeid) {
    key:      T,
    key_hash: u32,
}

KeyToIndex :: struct(K: typeid) {
    // Always allocated using an `Arena`
    // In the case of collisions, the next slot is used
    // `len(slots)` is always a power of 2
    hash_to_possible_indexes: HashToPossibleIndexes,
    keys:                     []Key(K),
}

make_key_to_index :: proc(a: ^Arena, $T: typeid/KeyToIndex($K)) -> KeyToIndex(K) {
    return KeyToIndex(K) {
        make_hash_to_possible_indexes(a),
        arena_make(a, []Key(K), 0, resizable = true),
    }
}

fix_key_to_index :: proc(key_to_index: KeyToIndex($Key)) {
    fix_hash_to_possible_indexes(key_to_index.hash_to_possible_indexes)
    fix_resizable_dynamic(key_to_index.keys)
}

@(private = "file")
get_index :: proc(slots_len: $T, hash: T) -> T {
    return hash & (slots_len - 1)
}

@(private = "file")
resize_key_to_index :: proc(
    key_to_index: ^KeyToIndex($Key),
    new_slots_len: int,
    loc := #caller_location,
) {
    when debug_key_to_index {
        print_call(loc, "resize")
        debug("new_slots_len: %d", new_slots_len)
    }
    resize_dynamic(&key_to_index.hash_to_possible_indexes.slots, int(new_slots_len))
    set_to_ones(key_to_index.hash_to_possible_indexes.slots)

    for key, index in key_to_index.keys {
        r := get_possible_indexes(key_to_index.hash_to_possible_indexes, key.key_hash)
        when debug_key_to_index {
            debug("index: %d", index)
            debug("r: %v", r)
        }
        key_to_index.hash_to_possible_indexes.slots[r.next_empty_slot.index] = Index{u32(index)}
    }
}

KeyToIndexProcs :: struct(K: typeid) {
    hash_proc:  proc(_: K) -> u32,

    // The `bool` returned is whether the keys are equal
    equal_proc: proc(_: K, _: K) -> bool,
}

string_to_index_procs :: KeyToIndexProcs(string) {
    simple_hash_string,
    proc(a: string, b: string) -> bool {
        return a == b
    },
}

Result :: enum {
    Inserted,
    LookedUp,
}

does_not_exist :: Index{max(u32)}

lookup :: proc(
    key_to_index: KeyToIndex($K),
    key: K,
    procs: KeyToIndexProcs(K),
    loc := #caller_location,
) -> Index {
    when debug_key_to_index {
        print_call(loc, "lookup")
        debug("key: %v", key)
    }

    if len(key_to_index.keys) == 0 {
        return does_not_exist
    }
    assert(len(key_to_index.hash_to_possible_indexes.slots) > 0)

    key_hash := procs.hash_proc(key)
    r := get_possible_indexes(key_to_index.hash_to_possible_indexes, key_hash)
    for i in r.possible_indexes {
        if procs.equal_proc(key_to_index.keys[i.index].key, key) {
            return i
        }
    }
    return does_not_exist
}

lookup_or_insert :: proc(
    key_to_index: ^KeyToIndex($K),
    key: K,
    procs: KeyToIndexProcs(K),
    loc := #caller_location,
) -> (
    Index,
    Result,
) {
    when debug_key_to_index {
        print_call(loc, "lookup_or_insert")
        debug("key: %v", key)
    }

    full_key := Key(K){key, procs.hash_proc(key)}

    if new_size := size_after_next_insertion(key_to_index.hash_to_possible_indexes);
       new_size != len(key_to_index.hash_to_possible_indexes.slots) {
        resize_key_to_index(key_to_index, new_size)
    }

    r := get_possible_indexes(key_to_index.hash_to_possible_indexes, full_key.key_hash)
    for i in r.possible_indexes {
        if procs.equal_proc(key_to_index.keys[i.index].key, key) {
            return i, .LookedUp
        }
    }

    out := Index{u32(len(key_to_index.keys))}
    append_dynamic(&key_to_index.keys, full_key)
    key_to_index.hash_to_possible_indexes.slots[r.next_empty_slot.index] = out
    key_to_index.hash_to_possible_indexes.number_of_used_slots += 1
    return out, .Inserted
}

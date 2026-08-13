package utils

// TODO: Benchmarks:
// - u64 hashes instead of u32 hashes
// - different values for `hash_to_possible_indexes_min_scale_factor`

// HashToPossibleIndexes.number_of_used_slots * hash_to_possible_indexes_min_scale_factor <= len(HashToPossibleIndexes.slots)
@(private = "file")
hash_to_possible_indexes_min_scale_factor :: 3

// math.next_power_of_two(hash_to_possible_indexes_min_scale_factor)
@(private = "file")
hash_to_possible_indexes_size_with_one_elem :: 4

HashToPossibleIndexes :: struct {
    // Always allocated using an `Arena`
    // In the case of collisions, the next slot is used
    // If the next slot overflows, then the previous empty slot is used
    // `len(slots)` is always a power of 2
    slots:                []Index,
    number_of_used_slots: int,
}

make_hash_to_possible_indexes :: proc(a: ^Arena) -> HashToPossibleIndexes {
    return HashToPossibleIndexes{arena_make(a, []Index, 0, resizable = true), 0}
}

size_after_next_insertion :: proc(h: HashToPossibleIndexes) -> int {
    if h.number_of_used_slots == 0 {
        return hash_to_possible_indexes_size_with_one_elem
    }
    minimum_number_of_slots :=
        (h.number_of_used_slots + 1) * hash_to_possible_indexes_min_scale_factor
    if minimum_number_of_slots <= len(h.slots) {
        return len(h.slots)
    }
    new_size := len(h.slots) << 1
    assert(new_size > minimum_number_of_slots)
    return new_size
}

fix_hash_to_possible_indexes :: proc(h: HashToPossibleIndexes) {
    fix_resizable_dynamic(h.slots)
}

@(private = "file")
get_index :: proc(slots_len: $T, hash: T) -> T {
    return hash & (slots_len - 1)
}

// Becomes out-dated when the hash to possible indexes is resized
SlotIndex :: struct {
    // An index into `HashToPossibleIndexes.slots`
    index: int,
}

GetPossibleIndexesResult :: struct {
    possible_indexes: []Index,
    next_empty_slot:  SlotIndex,
}

get_possible_indexes :: proc(
    hash_to_possible_indexes: HashToPossibleIndexes,
    hash: u32,
    loc := #caller_location,
) -> GetPossibleIndexesResult {
    when false {
        print_call(loc, "get_possible_indexes")
    }
    start_index := get_index(len(hash_to_possible_indexes.slots), int(hash))
    end_index := start_index

    for {
        if hash_to_possible_indexes.slots[end_index].index == max(u32) {
            return GetPossibleIndexesResult {
                hash_to_possible_indexes.slots[start_index:end_index],
                SlotIndex{end_index},
            }
        }
        end_index += 1
        if end_index >= len(hash_to_possible_indexes.slots) {
            break
        }
    }

    for {
        start_index -= 1
        if hash_to_possible_indexes.slots[start_index].index == max(u32) {
            return GetPossibleIndexesResult {
                hash_to_possible_indexes.slots[start_index + 1:end_index],
                SlotIndex{start_index},
            }
        }
    }
}

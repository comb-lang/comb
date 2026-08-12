package utils

// TODO: Benchmarks:
// - u64 hashes instead of u32 hashes

HashToPossibleIndexes :: struct {
    // Always allocated using an `Arena`
    // In the case of collisions, the next slot is used
    // If the next slot overflows, then the previous empty slot is used
    // `len(slots)` is always a power of 2
    slots: []Index,
}

make_hash_to_possible_indexes :: proc(a: ^Arena) -> HashToPossibleIndexes {
    return HashToPossibleIndexes{arena_make(a, []Index, 0, resizable = true)}
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
) -> GetPossibleIndexesResult {
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

package compiler

import "../utils"

get_range :: proc {
    get_range_from_unit,
    get_range_from_text_and_pos,
    get_range_from_ident_and_pos,
}

get_last :: proc(u: Unit) -> UnitSegment {
    return len(u.rest) == 0 ? u.first : u.rest[len(u.rest) - 1]
}

get_range_from_unit :: proc(u: Unit, loc := #caller_location) -> utils.Range {
    when ODIN_DEBUG {
        utils.call(loc, "get_range_from_unit", "")
    }
    start := u.first.range.start
    last_range := get_last(u).range
    end := last_range.start + last_range.length.v
    return utils.Range {
        start,
        utils.to_debug_value(
            end - start,
            "last_range.length: value: %d, created_at: %v",
            last_range.length.v,
            last_range.length.created_at,
        ),
        u.first.range.file,
    }
}

get_range_from_text_and_pos :: proc(t: TextAndPos, loc := #caller_location) -> utils.Range {
    when ODIN_DEBUG {
        utils.call(loc, "get_range_from_text_and_pos", "")
    }
    return utils.Range{t.pos.index, utils.to_debug_value(uint(len(t.text))), t.pos.file}
}

get_range_from_ident_and_pos :: proc(t: IdentAndPos, loc := #caller_location) -> utils.Range {
    when ODIN_DEBUG {
        utils.call(loc, "get_range_from_ident_and_pos", "")
    }
    return utils.Range{t.pos.index, utils.to_debug_value(uint(len(t.ident))), t.pos.file}
}

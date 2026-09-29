package compiler

import "../utils"
import "core:fmt"
import "core:os"
import "core:time"

source_code_changed :: proc(early_exit_value: ^ExitEarlyAwaitingSourceCodeChange) -> bool {
    // TODO: Make this code quicker so caching is not necersarry
    if time.since(early_exit_value.last_checked) < 10 * time.Millisecond {
        return false
    }
    defer early_exit_value.last_checked = time.now()
    for file in early_exit_value.files {
        info, err := os.stat(file.file_path, context.allocator)
        if err == os.General_Error.Not_Exist {
            return true
        }
        if err != nil {
            panic(fmt.aprintf("Failed to stat file: %v", err))
        }
        defer os.file_info_delete(info, context.allocator)
        if info.modification_time._nsec > early_exit_value.compilation_start._nsec {
            return true
        }
    }
    return false
}

should_exit_early :: proc(early_exit_info: EarlyExitInfo) -> bool {
    switch early_exit in early_exit_info {
    case NeverExitEarly:
        return false
    case ^ExitEarly:
        switch &early_exit_value in early_exit {
        case ExitEarlyAfterSourceCodeChanged:
            return true
        case ExitEarlyAwaitingSourceCodeChange:
            if !source_code_changed(&early_exit_value) {
                return false
            }
            early_exit^ = ExitEarlyAfterSourceCodeChanged{}
            return true
        case:
            panic("Unreachable")
        }
    case:
        panic("Unreachable")
    }
}

NeverExitEarly :: struct {}

ExitEarlyAwaitingSourceCodeChange :: struct {
    compilation_start: time.Time,
    files:             []utils.CompilerFile,
    last_checked:      time.Time,
}

ExitEarlyAfterSourceCodeChanged :: struct {}

ExitEarly :: union #no_nil {
    ExitEarlyAwaitingSourceCodeChange,
    ExitEarlyAfterSourceCodeChanged,
}

EarlyExitInfo :: union #no_nil {
    NeverExitEarly,
    ^ExitEarly, // A pointer so that the variant can be changed
}

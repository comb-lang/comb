package compiler

import "../utils"
import "core:fmt"
import "core:io"

parse_and_check :: proc(
    a: ^utils.Arena,
    files_cache: ^utils.FilesCache,
    first_file: ^utils.CompilerFile,
    func_name: string,
    out: utils.Pipe(io.Writer),
    exit_early: EarlyExitInfo,
    diagnostic_reporter: utils.DiagnosticReporter,
) -> CheckerOutput {
    parsed := parse_project(a, files_cache, out, exit_early, diagnostic_reporter)
    if diagnostic_reporter.has_errors(diagnostic_reporter.data) {
        return CheckerOutput{}
    }

    when utils.debug_parser_output {
        utils.debug("Printing function defs")
        utils.debug_nesting += 1
        for function_def, i in parsed.function_defs {
            utils.debug("Function def %d", i)
            utils.debug_nesting += 1
            utils.debug("%#v", function_def)
            utils.debug_nesting -= 1
        }
        utils.debug_nesting -= 1
    }

    fmt.wprintfln(out.stdout, "Checking...")
    return check(a, parsed, files_cache.files, func_name, first_file, out, diagnostic_reporter)
}

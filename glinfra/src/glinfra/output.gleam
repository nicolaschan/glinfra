import gleam/int
import gleam/io
import gleam/list
import gleam/string
import simplifile

// ANSI escape codes
const reset = "\u{001b}[0m"

const green = "\u{001b}[32m"

const yellow = "\u{001b}[33m"

const red = "\u{001b}[31m"

const dim = "\u{001b}[2m"

/// Result of attempting to write a single file
pub type FileResult {
  /// File was written because content changed (or file was new)
  Changed(path: String)
  /// File was skipped because content is identical to existing
  Unchanged(path: String)
  /// File write failed
  WriteError(path: String, reason: String)
}

/// Display grouped file results to stderr.
/// Groups files by their parent directory and shows a summary line per group,
/// listing changed files underneath. Errors are collected and shown at the end.
pub fn display(results: List(FileResult)) -> Nil {
  let groups = group_by_directory(results)
  let errors = collect_errors(results)

  // Print each directory group
  list.each(groups, fn(group) {
    let #(dir, files) = group
    let changed =
      list.filter(files, fn(f) {
        case f {
          Changed(_) -> True
          _ -> False
        }
      })
    let unchanged =
      list.filter(files, fn(f) {
        case f {
          Unchanged(_) -> True
          _ -> False
        }
      })
    let changed_count = list.length(changed)
    let unchanged_count = list.length(unchanged)

    // Summary line: ✓ dir  N changed, M unchanged
    let changed_text = case changed_count {
      0 -> dim <> int.to_string(changed_count) <> " changed" <> reset
      _ -> yellow <> int.to_string(changed_count) <> " changed" <> reset
    }
    let unchanged_text =
      dim <> int.to_string(unchanged_count) <> " unchanged" <> reset

    io.println_error(
      green
      <> "✓ "
      <> reset
      <> dir
      <> "  "
      <> changed_text
      <> ", "
      <> unchanged_text,
    )

    // List changed files underneath
    list.each(changed, fn(f) {
      case f {
        Changed(path) -> {
          let filename = basename(path)
          io.println_error("  " <> yellow <> "~ " <> reset <> filename)
        }
        _ -> Nil
      }
    })
  })

  // Print errors at the end
  case errors {
    [] -> Nil
    _ -> {
      io.println_error("")
      io.println_error(red <> "Errors:" <> reset)
      list.each(errors, fn(err) {
        case err {
          WriteError(path, reason) ->
            io.println_error(
              "  " <> red <> "✗ " <> reset <> path <> ": " <> reason,
            )
          _ -> Nil
        }
      })
    }
  }

  Nil
}

/// Write a file only if its content has changed. Returns a FileResult indicating
/// what happened: Changed (file was new or content differed), Unchanged (content
/// was identical so write was skipped), or Error (write failed).
pub fn smart_write(path: String, contents: String) -> FileResult {
  let existing = simplifile.read(path)
  case existing {
    Ok(existing_contents) ->
      case existing_contents == contents {
        True -> Unchanged(path)
        False ->
          case simplifile.write(to: path, contents: contents) {
            Ok(Nil) -> Changed(path)
            Error(err) -> WriteError(path, string.inspect(err))
          }
      }
    Error(_) ->
      case simplifile.write(to: path, contents: contents) {
        Ok(Nil) -> Changed(path)
        Error(err) -> WriteError(path, string.inspect(err))
      }
  }
}

/// Group FileResults by their parent directory.
/// Returns a list of (directory, files) pairs, preserving insertion order.
fn group_by_directory(
  results: List(FileResult),
) -> List(#(String, List(FileResult))) {
  list.fold(results, [], fn(groups, result) {
    let path = result_path(result)
    let dir = dirname(path)
    case list.key_find(groups, dir) {
      Ok(existing) -> {
        list.map(groups, fn(g) {
          case g.0 == dir {
            True -> #(dir, list.append(existing, [result]))
            False -> g
          }
        })
      }
      Error(_) -> list.append(groups, [#(dir, [result])])
    }
  })
}

/// Collect all Error results
fn collect_errors(results: List(FileResult)) -> List(FileResult) {
  list.filter(results, fn(f) {
    case f {
      WriteError(_, _) -> True
      _ -> False
    }
  })
}

/// Extract the path from a FileResult
fn result_path(result: FileResult) -> String {
  case result {
    Changed(path) -> path
    Unchanged(path) -> path
    WriteError(path, _) -> path
  }
}

/// Extract the parent directory from a path.
/// e.g. "../manifests/monad/baybridge.yaml" -> "../manifests/monad"
fn dirname(path: String) -> String {
  case string.split(path, "/") {
    [] -> "."
    parts -> {
      let without_last = list.take(parts, list.length(parts) - 1)
      case without_last {
        [] -> "."
        _ -> string.join(without_last, "/")
      }
    }
  }
}

/// Extract the filename from a path.
/// e.g. "../manifests/monad/baybridge.yaml" -> "baybridge.yaml"
fn basename(path: String) -> String {
  case string.split(path, "/") {
    [] -> ""
    parts -> {
      case list.last(parts) {
        Ok(last) -> last
        Error(_) -> ""
      }
    }
  }
}

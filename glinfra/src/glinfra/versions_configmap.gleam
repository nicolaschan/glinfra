import gleam/list
import gleam/string
import glinfra/blueprint/image.{type Image}
import simplifile

/// An entry in the versions ConfigMap: one image with its variable name,
/// current ref, and the $imagepolicy marker.
pub type VersionEntry {
  VersionEntry(
    /// The variable name (e.g. "GHCR_IO_NICOLASCHAN_BAYBRIDGE_IMAGE")
    variable: String,
    /// The full image ref (e.g. "ghcr.io/nicolaschan/baybridge:master-123")
    image_ref: String,
    /// The $imagepolicy value (e.g. "baybridge:ghcr-io-nicolaschan-baybridge")
    image_policy: String,
  )
}

/// Build a VersionEntry from an Image and its namespace.
pub fn entry_from_image(img: Image, namespace: String) -> VersionEntry {
  let slug = image.name_to_slug(img.name)
  VersionEntry(
    variable: image.variable_name(img),
    image_ref: image.to_ref(img),
    image_policy: namespace <> ":" <> slug,
  )
}

/// Generate the full ConfigMap YAML as a raw string with $imagepolicy comments.
/// The ConfigMap is placed in the flux-system namespace so it can be referenced
/// by Kustomization CRDs.
pub fn generate(name: String, entries: List(VersionEntry)) -> String {
  let data_lines =
    list.map(entries, fn(entry) {
      "  "
      <> entry.variable
      <> ": \""
      <> entry.image_ref
      <> "\""
      <> " # {\"$imagepolicy\": \""
      <> entry.image_policy
      <> "\"}"
    })
    |> string.join("\n")

  "---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: "
  <> name
  <> "\n  namespace: flux-system\ndata:\n"
  <> data_lines
  <> "\n"
}

/// Read an existing versions ConfigMap YAML file and extract variable->image_ref pairs.
/// Returns an empty list if the file doesn't exist or can't be parsed.
/// This is used to preserve image refs that FluxCD ImageUpdateAutomation has updated,
/// preventing `gleam run` from reverting automation updates.
pub fn read_existing(path: String) -> List(#(String, String)) {
  case simplifile.read(path) {
    Ok(contents) -> parse_data_lines(contents)
    Error(_) -> []
  }
}

/// Parse ConfigMap data lines to extract variable name -> image ref pairs.
/// Each data line looks like:
///   VAR_NAME: "image:tag" # {"$imagepolicy": "..."}
fn parse_data_lines(contents: String) -> List(#(String, String)) {
  contents
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    let trimmed = string.trim(line)
    // Look for lines matching pattern: KEY: "value" ...
    case string.split_once(trimmed, ": \"") {
      Ok(#(key, rest)) -> {
        // Extract the value before the closing quote
        case string.split_once(rest, "\"") {
          Ok(#(value, _)) -> Ok(#(string.trim(key), value))
          Error(_) -> Error(Nil)
        }
      }
      Error(_) -> Error(Nil)
    }
  })
}

/// Merge seed entries with existing values from a previously generated file.
/// For each entry, if an existing value is found for the same variable name,
/// use the existing image_ref (preserving automation updates). Otherwise use
/// the seed value from the Gleam code.
pub fn merge_with_existing(
  entries: List(VersionEntry),
  existing: List(#(String, String)),
) -> List(VersionEntry) {
  list.map(entries, fn(entry) {
    case list.find(existing, fn(pair) { pair.0 == entry.variable }) {
      Ok(#(_, existing_ref)) -> VersionEntry(..entry, image_ref: existing_ref)
      Error(_) -> entry
    }
  })
}

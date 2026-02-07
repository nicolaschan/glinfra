import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile
import yay

pub type Image {
  Image(name: String, tag: String, update: Option(ImageUpdate))
}

pub type ImageUpdate {
  ImageUpdate(pattern: String)
}

pub fn latest(name: String) -> Image {
  Image(name, "latest", None)
}

pub fn from_version_file(path: String) -> Image {
  let assert Ok(contents) = simplifile.read(path)
  let assert Ok([doc, ..]) = yay.parse_string(contents)
  let root = yay.document_root(doc)
  let assert Ok(ref) = yay.extract_string(root, "image")

  case string.split_once(ref, ":") {
    Ok(#(name, tag)) -> Image(name: name, tag: tag, update: None)
    Error(_) -> Image(name: ref, tag: "latest", update: None)
  }
}

pub fn with_update_pattern(image: Image, pattern: String) -> Image {
  Image(..image, update: Some(ImageUpdate(pattern)))
}

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

pub fn new(name: String, tag: String) -> Image {
  Image(name, tag, None)
}

pub fn from_string(image_string: String) -> Image {
  case string.split_once(image_string, ":") {
    Ok(#(name, tag)) -> Image(name: name, tag: tag, update: None)
    Error(_) -> Image(name: image_string, tag: "latest", update: None)
  }
}

pub fn from_version_file(path: String) -> Image {
  let assert Ok(contents) = simplifile.read(path)
  let assert Ok([doc, ..]) = yay.parse_string(contents)
  let root = yay.document_root(doc)
  let assert Ok(ref) = yay.extract_string(root, "image")
  from_string(ref)
}

pub fn with_update_pattern(image: Image, pattern: String) -> Image {
  Image(..image, update: Some(ImageUpdate(pattern)))
}

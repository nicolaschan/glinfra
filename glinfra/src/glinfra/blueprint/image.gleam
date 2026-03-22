import gleam/option.{type Option, None, Some}
import gleam/string

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

pub fn with_update_pattern(image: Image, pattern: String) -> Image {
  Image(..image, update: Some(ImageUpdate(pattern)))
}

pub fn to_ref(img: Image) -> String {
  img.name <> ":" <> img.tag
}

pub fn variable_name(img: Image) -> String {
  img.name
  |> string.replace("/", "_")
  |> string.replace(".", "_")
  |> string.replace("-", "_")
  |> string.uppercase
  |> string.append("_IMAGE")
}

/// Convert an image name to a slug suitable for Kubernetes resource names.
/// e.g. "ghcr.io/nicolaschan/baybridge" -> "ghcr-io-nicolaschan-baybridge"
pub fn name_to_slug(name: String) -> String {
  name
  |> string.replace("/", "-")
  |> string.replace(".", "-")
}

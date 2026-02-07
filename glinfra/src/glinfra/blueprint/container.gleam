import gleam/option.{type Option, None, Some}
import glinfra/blueprint/image.{type Image}
import glinfra/blueprint/storage.{type StorageRef}

pub type Container {
  Container(
    image: Image,
    args: Option(List(String)),
    storage: List(#(String, StorageRef)),
  )
}

pub fn new(image_string: String) -> Container {
  Container(image.from_string(image_string), None, [])
}

pub fn image(image: Image) -> Container {
  Container(image, None, [])
}

pub fn with_args(container: Container, args: List(String)) -> Container {
  Container(..container, args: Some(args))
}

pub fn add_storage(
  container: Container,
  mount_path: String,
  storage_ref: StorageRef,
) -> Container {
  Container(..container, storage: [
    #(mount_path, storage_ref),
    ..container.storage
  ])
}

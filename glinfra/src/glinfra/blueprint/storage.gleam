import gleam/option.{type Option, Some}

pub type Storage {
  Storage(
    name: String,
    size: String,
    storage_class: Option(String),
    access_modes: List(String),
    annotations: List(#(String, String)),
  )
}

pub type StorageRef {
  StorageRef(name: String, read_only: Bool)
}

pub fn new(name: String, size: String) -> Storage {
  Storage(
    name: name,
    size: size,
    storage_class: Some("local-path"),
    access_modes: [
      "ReadWriteOnce",
    ],
    annotations: [],
  )
}

pub fn with_storage_class(storage: Storage, class: String) -> Storage {
  Storage(..storage, storage_class: option.Some(class))
}

pub fn with_default_storage_class(storage: Storage) -> Storage {
  Storage(..storage, storage_class: option.None)
}

pub fn with_access_modes(storage: Storage, modes: List(String)) -> Storage {
  Storage(..storage, access_modes: modes)
}

pub fn with_annotations(
  storage: Storage,
  annotations: List(#(String, String)),
) -> Storage {
  Storage(..storage, annotations: annotations)
}

pub fn ref(storage: Storage) -> StorageRef {
  StorageRef(name: storage.name, read_only: False)
}

pub fn readonly_ref(storage: Storage) -> StorageRef {
  StorageRef(name: storage.name, read_only: True)
}

pub fn external(name: String) -> StorageRef {
  StorageRef(name: name, read_only: False)
}

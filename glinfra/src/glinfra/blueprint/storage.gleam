import gleam/option.{type Option, Some}

pub type Storage {
  Storage(
    name: String,
    size: String,
    storage_class: Option(String),
    access_modes: List(String),
  )
}

pub type StorageRef {
  StorageRef(name: String)
}

pub fn new(name: String, size: String) -> Storage {
  Storage(
    name: name,
    size: size,
    storage_class: Some("local-path"),
    access_modes: [
      "ReadWriteOnce",
    ],
  )
}

pub fn with_storage_class(storage: Storage, class: String) -> Storage {
  Storage(..storage, storage_class: option.Some(class))
}

pub fn with_access_modes(storage: Storage, modes: List(String)) -> Storage {
  Storage(..storage, access_modes: modes)
}

pub fn ref(storage: Storage) -> StorageRef {
  StorageRef(name: storage.name)
}

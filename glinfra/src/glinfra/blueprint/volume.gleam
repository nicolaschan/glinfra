import gleam/list
import gleam/result
import gleam/string
import glinfra/blueprint/storage.{type StorageRef}

pub type VolumeRef {
  VolumeRef(source: VolumeSource, mount_path: String, read_only: Bool)
}

pub type VolumeSource {
  Pvc(claim_name: String)
  Secret(secret_name: String)
  HostPath(path: String)
}

pub fn pvc(
  mount_path: String,
  claim_name: String,
  read_only: Bool,
) -> VolumeRef {
  VolumeRef(
    source: Pvc(claim_name: claim_name),
    mount_path: mount_path,
    read_only: read_only,
  )
}

pub fn secret(mount_path: String, secret_name: String) -> VolumeRef {
  VolumeRef(
    source: Secret(secret_name: secret_name),
    mount_path: mount_path,
    read_only: True,
  )
}

pub fn host_path(mount_path: String, path: String) -> VolumeRef {
  VolumeRef(
    source: HostPath(path: path),
    mount_path: mount_path,
    read_only: True,
  )
}

pub fn from_storage_ref(mount_path: String, ref: StorageRef) -> VolumeRef {
  pvc(mount_path, ref.name, ref.read_only)
}

pub fn writable(ref: VolumeRef) -> VolumeRef {
  VolumeRef(..ref, read_only: False)
}

pub fn read_only(ref: VolumeRef) -> Bool {
  ref.read_only
}

pub fn mount_path(ref: VolumeRef) -> String {
  ref.mount_path
}

pub fn volume_name(ref: VolumeRef) -> String {
  source_name(ref.source) <> "-volume"
}

fn source_name(source: VolumeSource) -> String {
  case source {
    Pvc(claim_name) -> claim_name
    Secret(secret_name) -> secret_name
    HostPath(path) ->
      path
      |> string.split("/")
      |> list.last
      |> result.unwrap(path)
      |> string.split(".")
      |> list.first
      |> result.unwrap(path)
  }
}

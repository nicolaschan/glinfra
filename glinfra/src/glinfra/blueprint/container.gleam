import gleam/option.{type Option, None, Some}
import glinfra/blueprint/image.{type Image}
import glinfra/blueprint/storage.{type StorageRef}
import glinfra/k8s/deployment

pub type SecretVolumeRef {
  SecretVolumeRef(name: String, mount_path: String, read_only: Bool)
}

pub type Container {
  Container(
    image: Image,
    args: Option(List(String)),
    storage: List(#(String, StorageRef)),
    env: List(#(String, String)),
    secret_volumes: List(SecretVolumeRef),
    lifecycle: Option(deployment.Lifecycle),
  )
}

pub fn new(image_string: String) -> Container {
  Container(
    image: image.from_string(image_string),
    args: None,
    storage: [],
    env: [],
    secret_volumes: [],
    lifecycle: None,
  )
}

pub fn image(img: Image) -> Container {
  Container(
    image: img,
    args: None,
    storage: [],
    env: [],
    secret_volumes: [],
    lifecycle: None,
  )
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

pub fn add_env(container: Container, name: String, value: String) -> Container {
  Container(..container, env: [#(name, value), ..container.env])
}

pub fn secret_volume(secret_name: String, mount_path: String) -> SecretVolumeRef {
  SecretVolumeRef(name: secret_name, mount_path: mount_path, read_only: True)
}

pub fn writable(ref: SecretVolumeRef) -> SecretVolumeRef {
  SecretVolumeRef(..ref, read_only: False)
}

pub fn add_secret_volume(
  container: Container,
  ref: SecretVolumeRef,
) -> Container {
  Container(..container, secret_volumes: [ref, ..container.secret_volumes])
}

pub fn with_lifecycle(
  container: Container,
  lifecycle: deployment.Lifecycle,
) -> Container {
  Container(..container, lifecycle: Some(lifecycle))
}

pub fn post_start(
  container: Container,
  handler: deployment.LifecycleHandler,
) -> Container {
  let lifecycle = case container.lifecycle {
    Some(lc) -> deployment.Lifecycle(..lc, post_start: Some(handler))
    None -> deployment.Lifecycle(post_start: Some(handler), pre_stop: None)
  }
  Container(..container, lifecycle: Some(lifecycle))
}

pub fn post_start_exec(container: Container, command: List(String)) -> Container {
  post_start(container, deployment.ExecHandler(command: command))
}

pub fn pre_stop(
  container: Container,
  handler: deployment.LifecycleHandler,
) -> Container {
  let lifecycle = case container.lifecycle {
    Some(lc) -> deployment.Lifecycle(..lc, pre_stop: Some(handler))
    None -> deployment.Lifecycle(post_start: None, pre_stop: Some(handler))
  }
  Container(..container, lifecycle: Some(lifecycle))
}

pub fn pre_stop_exec(container: Container, command: List(String)) -> Container {
  pre_stop(container, deployment.ExecHandler(command: command))
}

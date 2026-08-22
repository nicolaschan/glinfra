import gleam/option.{type Option, None, Some}
import glinfra/blueprint/image.{type Image}
import glinfra/blueprint/storage.{type StorageRef}
import glinfra/blueprint/volume.{type VolumeRef}
import glinfra/k8s/deployment

pub type SecretEnvRef {
  SecretEnvRef(name: String)
}

pub type Env {
  Literal(key: String, value: String)
  AllFromSecret(secret: SecretEnvRef)
}

pub type Container {
  Container(
    image: Image,
    args: Option(List(String)),
    volumes: List(VolumeRef),
    env: List(Env),
    lifecycle: Option(deployment.Lifecycle),
    image_pull_policy: Option(deployment.ImagePullPolicy),
  )
}

pub fn new(image_string: String) -> Container {
  Container(
    image: image.from_string(image_string),
    args: None,
    volumes: [],
    env: [],
    lifecycle: None,
    image_pull_policy: None,
  )
}

pub fn image(img: Image) -> Container {
  Container(
    image: img,
    args: None,
    volumes: [],
    env: [],
    lifecycle: None,
    image_pull_policy: None,
  )
}

pub fn with_image_pull_policy(
  container: Container,
  policy: deployment.ImagePullPolicy,
) -> Container {
  Container(..container, image_pull_policy: Some(policy))
}

pub fn with_args(container: Container, args: List(String)) -> Container {
  Container(..container, args: Some(args))
}

pub fn add_volume(container: Container, ref: VolumeRef) -> Container {
  Container(..container, volumes: [ref, ..container.volumes])
}

pub fn add_storage(
  container: Container,
  mount_path: String,
  storage_ref: StorageRef,
) -> Container {
  add_volume(container, volume.from_storage_ref(mount_path, storage_ref))
}

pub fn add_env(container: Container, name: String, value: String) -> Container {
  Container(..container, env: [Literal(name, value), ..container.env])
}

pub fn add_env_from_secret(
  container: Container,
  ref: SecretEnvRef,
) -> Container {
  Container(..container, env: [AllFromSecret(ref), ..container.env])
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

pub fn post_start_exec(
  container: Container,
  command: List(String),
) -> Container {
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

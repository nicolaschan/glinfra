import gleam/list
import glinfra/blueprint/storage.{type StorageRef}
import glinfra/blueprint/volume.{type VolumeRef}

pub type Job {
  Job(
    name: String,
    image: String,
    schedule: String,
    command: List(String),
    volumes: List(VolumeRef),
    env: List(JobEnv),
  )
}

pub type JobEnv {
  SecretEnv(name: String, secret_name: String, key: String)
}

pub fn new(
  name: String,
  image: String,
  schedule: String,
  command: List(String),
) -> Job {
  Job(
    name: name,
    image: image,
    schedule: schedule,
    command: command,
    volumes: [],
    env: [],
  )
}

pub fn mount_pvc(job: Job, mount_path: String, storage: StorageRef) -> Job {
  Job(
    ..job,
    volumes: list.append(job.volumes, [
      volume.from_storage_ref(mount_path, storage),
    ]),
  )
}

pub fn mount_secret(job: Job, mount_path: String, secret_name: String) -> Job {
  Job(
    ..job,
    volumes: list.append(job.volumes, [
      volume.secret(mount_path, secret_name),
    ]),
  )
}

pub fn mount_host_path(job: Job, mount_path: String, path: String) -> Job {
  Job(
    ..job,
    volumes: list.append(job.volumes, [
      volume.host_path(mount_path, path),
    ]),
  )
}

pub fn add_env(job: Job, env: JobEnv) -> Job {
  Job(..job, env: list.append(job.env, [env]))
}

pub fn secret_env(name: String, secret_name: String, key: String) -> JobEnv {
  SecretEnv(name: name, secret_name: secret_name, key: key)
}

import gleam/list
import glinfra/blueprint/storage.{type StorageRef}

pub type Job {
  Job(
    name: String,
    image: String,
    schedule: String,
    command: List(String),
    volumes: List(JobVolume),
    env: List(JobEnv),
  )
}

pub type JobVolume {
  PvcVolume(mount_path: String, storage: StorageRef)
  SecretVolume(mount_path: String, secret_name: String)
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
    volumes: list.append(job.volumes, [PvcVolume(mount_path, storage)]),
  )
}

pub fn mount_secret(job: Job, mount_path: String, secret_name: String) -> Job {
  Job(
    ..job,
    volumes: list.append(job.volumes, [SecretVolume(mount_path, secret_name)]),
  )
}

pub fn add_env(job: Job, env: JobEnv) -> Job {
  Job(..job, env: list.append(job.env, [env]))
}

pub fn secret_env(name: String, secret_name: String, key: String) -> JobEnv {
  SecretEnv(name: name, secret_name: secret_name, key: key)
}

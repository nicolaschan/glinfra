import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type ObjectMeta}

pub type CronJob {
  CronJob(metadata: ObjectMeta, spec: CronJobSpec)
}

pub type CronJobSpec {
  CronJobSpec(
    schedule: String,
    concurrency_policy: String,
    job_template: JobTemplate,
  )
}

pub type JobTemplate {
  JobTemplate(
    backoff_limit: Int,
    ttl_seconds: Int,
    restart_policy: String,
    containers: List(JobContainer),
    volumes: List(JobVolume),
  )
}

pub type JobContainer {
  JobContainer(
    name: String,
    image: String,
    image_pull_policy: Option(String),
    env: List(EnvVar),
    volume_mounts: List(JobVolumeMount),
    command: List(String),
  )
}

pub type EnvVar {
  PlainEnvVar(name: String, value: String)
  SecretEnvVar(name: String, secret_name: String, key: String)
}

pub type JobVolumeMount {
  JobVolumeMount(name: String, mount_path: String, read_only: Option(Bool))
}

pub type JobVolume {
  PvcVolume(name: String, claim_name: String)
  SecretVolume(name: String, secret_name: String, default_mode: Option(Int))
}

pub fn to_cymbal(c: CronJob) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("batch/v1")),
    #("kind", cymbal.string("CronJob")),
    #("metadata", k8s.object_meta_to_cymbal(c.metadata)),
    #("spec", cronjob_spec_to_cymbal(c.spec)),
  ])
}

pub fn to_yaml(c: CronJob) -> String {
  cymbal.encode(to_cymbal(c))
}

fn cronjob_spec_to_cymbal(s: CronJobSpec) -> cymbal.Yaml {
  cymbal.block([
    #("concurrencyPolicy", cymbal.string(s.concurrency_policy)),
    #("schedule", cymbal.string(s.schedule)),
    #("jobTemplate", job_template_to_cymbal(s.job_template)),
  ])
}

fn job_template_to_cymbal(t: JobTemplate) -> cymbal.Yaml {
  cymbal.block([
    #(
      "spec",
      cymbal.block([
        #("backoffLimit", cymbal.int(t.backoff_limit)),
        #("ttlSecondsAfterFinished", cymbal.int(t.ttl_seconds)),
        #(
          "template",
          cymbal.block([
            #(
              "spec",
              pod_spec_to_cymbal(t.containers, t.volumes, t.restart_policy),
            ),
          ]),
        ),
      ]),
    ),
  ])
}

fn pod_spec_to_cymbal(
  containers: List(JobContainer),
  volumes: List(JobVolume),
  restart_policy: String,
) -> cymbal.Yaml {
  let fields = [
    #("volumes", cymbal.array(list.map(volumes, volume_to_cymbal))),
    #("containers", cymbal.array(list.map(containers, container_to_cymbal))),
    #("restartPolicy", cymbal.string(restart_policy)),
  ]

  cymbal.block(fields)
}

fn container_to_cymbal(c: JobContainer) -> cymbal.Yaml {
  let fields = [
    #("name", cymbal.string(c.name)),
    #("image", cymbal.string(c.image)),
  ]

  let fields = case c.image_pull_policy {
    Some(policy) ->
      list.append(fields, [#("imagePullPolicy", cymbal.string(policy))])
    None -> fields
  }

  let fields = case c.env {
    [] -> fields
    env ->
      list.append(fields, [
        #("env", cymbal.array(list.map(env, env_var_to_cymbal))),
      ])
  }

  let fields = case c.volume_mounts {
    [] -> fields
    mounts ->
      list.append(fields, [
        #(
          "volumeMounts",
          cymbal.array(list.map(mounts, volume_mount_to_cymbal)),
        ),
      ])
  }

  let fields = case c.command {
    [] -> fields
    cmd ->
      list.append(fields, [
        #("command", cymbal.array(list.map(cmd, cymbal.string))),
      ])
  }

  cymbal.block(fields)
}

fn env_var_to_cymbal(e: EnvVar) -> cymbal.Yaml {
  case e {
    PlainEnvVar(name, value) ->
      cymbal.block([
        #("name", cymbal.string(name)),
        #("value", cymbal.string(value)),
      ])
    SecretEnvVar(name, secret_name, key) ->
      cymbal.block([
        #("name", cymbal.string(name)),
        #(
          "valueFrom",
          cymbal.block([
            #(
              "secretKeyRef",
              cymbal.block([
                #("name", cymbal.string(secret_name)),
                #("key", cymbal.string(key)),
              ]),
            ),
          ]),
        ),
      ])
  }
}

fn volume_mount_to_cymbal(m: JobVolumeMount) -> cymbal.Yaml {
  let fields = [
    #("mountPath", cymbal.string(m.mount_path)),
    #("name", cymbal.string(m.name)),
  ]

  let fields = case m.read_only {
    Some(True) -> list.append(fields, [#("readOnly", cymbal.bool(True))])
    _ -> fields
  }

  cymbal.block(fields)
}

fn volume_to_cymbal(v: JobVolume) -> cymbal.Yaml {
  case v {
    PvcVolume(name, claim_name) ->
      cymbal.block([
        #("name", cymbal.string(name)),
        #(
          "persistentVolumeClaim",
          cymbal.block([#("claimName", cymbal.string(claim_name))]),
        ),
      ])
    SecretVolume(name, secret_name, default_mode) -> {
      let secret_fields = [#("secretName", cymbal.string(secret_name))]
      let secret_fields = case default_mode {
        Some(mode) ->
          list.append(secret_fields, [#("defaultMode", cymbal.int(mode))])
        None -> secret_fields
      }
      cymbal.block([
        #("name", cymbal.string(name)),
        #("secret", cymbal.block(secret_fields)),
      ])
    }
  }
}

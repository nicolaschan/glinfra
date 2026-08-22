import cymbal
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/blueprint/app.{
  type App, type AppPlugin, type HelmApp, type StackApp, App, ContainerApp,
  HelmApp, HelmChartApp,
}
import glinfra/blueprint/container
import glinfra/blueprint/environment.{type Environment, Provider, Resource}
import glinfra/blueprint/image
import glinfra/blueprint/job
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage.{type Storage}
import glinfra/blueprint/volume.{type VolumeRef}
import glinfra/k8s
import glinfra/k8s/cronjob
import glinfra/k8s/deployment
import glinfra/k8s/helm_release
import glinfra/k8s/helm_repository
import glinfra/k8s/ingress
import glinfra/k8s/namespace
import glinfra/k8s/persistent_volume_claim
import glinfra/k8s/service

pub type StackPlugin {
  StackPlugin(
    app_plugins: List(AppPlugin),
    dependencies: List(environment.Resource),
  )
}

pub type Stacks {
  Stacks(stack_plugins: List(StackPlugin), stacks: List(Stack))
}

pub fn stacks() -> Stacks {
  Stacks(stack_plugins: [], stacks: [])
}

pub fn plugins(s: Stacks, p: List(AppPlugin)) -> Stacks {
  Stacks(
    ..s,
    stack_plugins: list.append(s.stack_plugins, [
      StackPlugin(app_plugins: p, dependencies: []),
    ]),
  )
}

pub fn stack_plugin(
  app_plugins: List(AppPlugin),
  dependencies: List(environment.Resource),
) -> StackPlugin {
  StackPlugin(app_plugins:, dependencies:)
}

pub fn add_stack_plugin(s: Stacks, p: StackPlugin) -> Stacks {
  Stacks(..s, stack_plugins: list.append(s.stack_plugins, [p]))
}

pub fn add(s: Stacks, stack: Stack) -> Stacks {
  Stacks(..s, stacks: [stack, ..s.stacks])
}

pub fn add_all(env: Environment, s: Stacks) -> Environment {
  let all_app_plugins =
    list.flat_map(s.stack_plugins, fn(sp) { sp.app_plugins })
  let all_dependencies =
    list.flat_map(s.stack_plugins, fn(sp: StackPlugin) { sp.dependencies })

  list.fold(list.reverse(s.stacks), env, fn(env, stack) {
    let provider =
      Provider(resources: [
        Resource(
          name: stack.name,
          dependencies: all_dependencies,
          render: fn(_env) { stack_to_cymbal(stack, all_app_plugins) },
        ),
      ])
    environment.add_provider(env, provider)
  })
}

/// Create a standalone Resource from a Stack (without plugins).
/// Used when a provider needs to pull in a stack as a dependency.
pub fn stack_to_resource(stack: Stack) -> environment.Resource {
  Resource(name: stack.name, dependencies: [], render: fn(_env) {
    stack_to_cymbal(stack, [])
  })
}

fn stack_to_cymbal(
  stack: Stack,
  global_plugins: List(AppPlugin),
) -> List(cymbal.Yaml) {
  let ns = namespace.new(stack.name)
  let docs = [namespace.to_cymbal(ns)]

  // Generate core app resources (Deployments, Services, Ingresses, HelmRepos, HelmReleases)
  // but NOT ExtraResources yet
  let docs =
    list.fold(stack.apps, docs, fn(docs, application) {
      stack_app_to_core_cymbal(ns: stack.name, global_plugins:, application:)
      |> list.append(docs, _)
    })

  // Generate jobs (CronJobs) — these come after core app resources
  let docs =
    list.append(
      docs,
      list.map(stack.jobs, fn(j) { job_to_cronjob(stack.name, j) }),
    )

  // Generate ExtraResources from app plugins — these come after jobs
  let docs =
    list.fold(stack.apps, docs, fn(docs, application) {
      let plugins =
        list.append(global_plugins, app.stack_app_plugins(application))
      apply_extra_resources(docs, stack.name, application, plugins)
    })

  // Generate storage (PVCs) — these come last
  let docs =
    list.append(
      docs,
      list.map(stack.storage, fn(s) {
        storage_to_pvc(stack.name, s) |> persistent_volume_claim.to_cymbal
      }),
    )

  docs
}

fn stack_app_to_core_cymbal(
  ns ns: String,
  global_plugins global_plugins: List(AppPlugin),
  application application: StackApp,
) -> List(cymbal.Yaml) {
  case application {
    ContainerApp(a) -> app_to_core_cymbal(ns, global_plugins, a)
    HelmChartApp(a) -> helm_app_to_core_cymbal(ns, a)
  }
}

fn app_to_core_cymbal(
  ns: String,
  global_plugins: List(AppPlugin),
  a: App,
) -> List(cymbal.Yaml) {
  let App(name, port, containers, plugins, strategy) = a
  let labels = [#("app", name)]
  let all_plugins = list.append(global_plugins, plugins)
  let stack_app = ContainerApp(a)

  let docs = [
    app_to_deployment(ns, name, port, containers, labels, strategy)
    |> apply_deployment_plugins(stack_app, all_plugins)
    |> deployment.to_cymbal,
  ]

  let docs = case port {
    [] -> docs
    _ ->
      list.append(docs, [
        app_to_service(ns, name, port, labels)
        |> apply_service_plugins(stack_app, all_plugins)
        |> service.to_cymbal,
      ])
  }

  case app_to_ingress(ns, name, port, labels) {
    Some(ing) ->
      list.append(docs, [
        ing
        |> apply_ingress_plugins(stack_app, all_plugins)
        |> ingress.to_cymbal,
      ])
    None -> docs
  }
}

fn helm_app_to_core_cymbal(ns: String, a: HelmApp) -> List(cymbal.Yaml) {
  let HelmApp(_name, release, repo, _plugins) = a
  let repo_doc =
    helm_repository.to_cymbal(helm_repository.HelmRepository(
      metadata: k8s.ObjectMeta(..repo.metadata, namespace: Some(ns)),
      spec: repo.spec,
    ))
  let release_doc =
    helm_release.to_cymbal(helm_release.HelmRelease(
      metadata: k8s.ObjectMeta(..release.metadata, namespace: Some(ns)),
      spec: release.spec,
    ))
  [repo_doc, release_doc]
}

fn apply_deployment_plugins(
  dep: deployment.Deployment,
  application: StackApp,
  plugins: List(AppPlugin),
) -> deployment.Deployment {
  list.fold(plugins, dep, fn(d, plugin) {
    case plugin {
      app.DeploymentPlugin(modify) -> modify(application, d)
      _ -> d
    }
  })
}

fn apply_ingress_plugins(
  ing: ingress.Ingress,
  application: StackApp,
  plugins: List(AppPlugin),
) -> ingress.Ingress {
  list.fold(plugins, ing, fn(i, plugin) {
    case plugin {
      app.IngressPlugin(modify) -> modify(application, i)
      _ -> i
    }
  })
}

fn apply_service_plugins(
  svc: service.Service,
  application: StackApp,
  plugins: List(AppPlugin),
) -> service.Service {
  list.fold(plugins, svc, fn(s, plugin) {
    case plugin {
      app.ServicePlugin(modify) -> modify(application, s)
      _ -> s
    }
  })
}

fn apply_extra_resources(
  docs: List(cymbal.Yaml),
  ns: String,
  application: StackApp,
  plugins: List(AppPlugin),
) -> List(cymbal.Yaml) {
  list.fold(plugins, docs, fn(docs, plugin) {
    case plugin {
      app.ExtraResources(generate) ->
        list.append(docs, generate(ns, application))
      _ -> docs
    }
  })
}

fn app_to_deployment(
  ns: String,
  name: String,
  port: List(app.Port),
  app_containers: List(container.Container),
  labels: List(#(String, String)),
  explicit_strategy: Option(deployment.Strategy),
) -> deployment.Deployment {
  let has_pvc =
    list.any(app_containers, fn(c) {
      list.any(c.volumes, fn(v) {
        case v.source {
          volume.Pvc(_) -> True
          _ -> False
        }
      })
    })

  let strategy = case explicit_strategy {
    Some(s) -> Some(s)
    None ->
      case has_pvc {
        True -> Some(deployment.Recreate)
        False -> None
      }
  }

  let volumes =
    list.flat_map(app_containers, fn(c) {
      list.map(c.volumes, volume_to_pod_volume)
    })

  let container_count = list.length(app_containers)
  let containers =
    list.index_map(app_containers, fn(c, i) {
      let image_ref = case c.image.update {
        Some(_) -> "${" <> image.variable_name(c.image) <> "}"
        None -> c.image.name <> ":" <> c.image.tag
      }
      let ports =
        list.map(port, fn(p) {
          deployment.ContainerPort(
            container_port: p.number,
            protocol: Some("TCP"),
          )
        })
      let volume_mounts = list.map(c.volumes, volume_to_pod_mount)
      let env =
        list.flat_map(list.reverse(c.env), fn(e) {
          case e {
            container.Literal(key, value) -> [
              deployment.EnvVar(name: key, value: value),
            ]
            _ -> []
          }
        })
      let env_from =
        list.flat_map(list.reverse(c.env), fn(e) {
          case e {
            container.AllFromSecret(secret) -> [
              deployment.SecretEnvFrom(secret_name: secret.name),
            ]
            _ -> []
          }
        })
      let container_name = case container_count {
        1 -> name
        _ -> name <> "-" <> int.to_string(i)
      }
      deployment.Container(
        name: container_name,
        image: image_ref,
        args: c.args,
        ports: ports,
        env: env,
        env_from: env_from,
        volume_mounts: volume_mounts,
        resources: deployment.ResourceRequirements(limits: [], requests: []),
        lifecycle: c.lifecycle,
        image_pull_policy: c.image_pull_policy,
      )
    })

  deployment.Deployment(
    metadata: k8s.ObjectMeta(
      name: name,
      namespace: Some(ns),
      labels: labels,
      annotations: [],
    ),
    spec: deployment.DeploymentSpec(
      replicas: 1,
      selector: k8s.LabelSelector(match_labels: labels),
      strategy: strategy,
      template: deployment.PodTemplateSpec(
        metadata: k8s.ObjectMeta(
          name: name,
          namespace: None,
          labels: labels,
          annotations: [],
        ),
        containers: containers,
        volumes: volumes,
        runtime_class_name: None,
      ),
    ),
  )
}

fn volume_to_pod_volume(ref: VolumeRef) -> deployment.Volume {
  case ref.source {
    volume.Pvc(claim_name) ->
      deployment.PvcVolume(
        name: volume.volume_name(ref),
        claim_name: claim_name,
        read_only: volume_read_only(ref),
      )
    volume.Secret(secret_name) ->
      deployment.SecretVolume(
        name: volume.volume_name(ref),
        secret_name: secret_name,
      )
    volume.HostPath(path) ->
      deployment.HostPathVolume(name: volume.volume_name(ref), path: path)
  }
}

fn volume_to_pod_mount(ref: VolumeRef) -> deployment.VolumeMount {
  deployment.VolumeMount(
    name: volume.volume_name(ref),
    mount_path: volume.mount_path(ref),
    read_only: mount_read_only(ref),
  )
}

fn volume_read_only(ref: VolumeRef) -> Option(Bool) {
  case ref.read_only {
    True -> Some(True)
    False -> None
  }
}

fn mount_read_only(ref: VolumeRef) -> Option(Bool) {
  // k8s only has a read-only field on the claim for PVCs; secret and
  // hostPath sources express read-only on the mount.
  case ref.source {
    volume.Pvc(_) -> None
    _ -> volume_read_only(ref)
  }
}

fn volume_to_cronjob_volume(ref: VolumeRef) -> cronjob.JobVolume {
  case ref.source {
    volume.Pvc(claim_name) ->
      cronjob.PvcVolume(name: volume.volume_name(ref), claim_name: claim_name)
    volume.Secret(secret_name) ->
      cronjob.SecretVolume(
        name: volume.volume_name(ref),
        secret_name: secret_name,
        default_mode: Some(256),
      )
    volume.HostPath(path) ->
      cronjob.HostPathVolume(name: volume.volume_name(ref), path: path)
  }
}

fn volume_to_cronjob_mount(ref: VolumeRef) -> cronjob.JobVolumeMount {
  cronjob.JobVolumeMount(
    name: volume.volume_name(ref),
    mount_path: volume.mount_path(ref),
    read_only: mount_read_only(ref),
  )
}

fn storage_to_pvc(
  ns: String,
  s: Storage,
) -> persistent_volume_claim.PersistentVolumeClaim {
  let annotations = [k8s.no_prune_annotation, ..s.annotations]
  persistent_volume_claim.PersistentVolumeClaim(
    metadata: k8s.ObjectMeta(
      name: s.name,
      namespace: Some(ns),
      labels: [],
      annotations: annotations,
    ),
    spec: persistent_volume_claim.PvcSpec(
      access_modes: s.access_modes,
      storage: s.size,
      storage_class_name: s.storage_class,
      volume_name: None,
    ),
  )
}

fn app_to_service(
  ns: String,
  name: String,
  port: List(app.Port),
  labels: List(#(String, String)),
) -> service.Service {
  let ports =
    list.index_map(port, fn(p, i) {
      let port_name = case list.length(port) > 1 {
        True -> Some(name <> "-" <> int.to_string(i))
        False -> None
      }
      service.ServicePort(
        name: port_name,
        port: p.number,
        target_port: p.number,
        protocol: Some("TCP"),
      )
    })

  service.Service(
    metadata: k8s.ObjectMeta(
      name: name,
      namespace: Some(ns),
      labels: labels,
      annotations: [],
    ),
    spec: service.ServiceSpec(selector: labels, ports: ports),
  )
}

fn app_to_ingress(
  ns: String,
  name: String,
  port: List(app.Port),
  _labels: List(#(String, String)),
) -> Option(ingress.Ingress) {
  let rules =
    list.flat_map(port, fn(p) {
      list.map(p.ingress, fn(ing) {
        ingress.IngressRule(host: ing.host, paths: [
          ingress.IngressPath(
            path: "/",
            path_type: "Prefix",
            backend: ingress.IngressBackend(
              service_name: name,
              service_port: p.number,
            ),
          ),
        ])
      })
    })

  let hosts =
    list.flat_map(port, fn(p) { list.map(p.ingress, fn(ing) { ing.host }) })

  case rules {
    [] -> None
    _ ->
      Some(ingress.Ingress(
        metadata: k8s.ObjectMeta(
          name: name,
          namespace: Some(ns),
          labels: [],
          annotations: [],
        ),
        spec: ingress.IngressSpec(ingress_class_name: None, rules: rules, tls: [
          ingress.IngressTls(hosts: hosts, secret_name: name <> "-cert"),
        ]),
      ))
  }
}

fn job_to_cronjob(ns: String, j: job.Job) -> cymbal.Yaml {
  let volumes = list.map(j.volumes, volume_to_cronjob_volume)
  let volume_mounts = list.map(j.volumes, volume_to_cronjob_mount)

  let env =
    list.map(j.env, fn(e) {
      case e {
        job.SecretEnv(name, secret_name, key) ->
          cronjob.SecretEnvVar(name: name, secret_name: secret_name, key: key)
      }
    })

  let cj =
    cronjob.CronJob(
      metadata: k8s.ObjectMeta(
        name: j.name,
        namespace: Some(ns),
        labels: [],
        annotations: [],
      ),
      spec: cronjob.CronJobSpec(
        schedule: j.schedule,
        concurrency_policy: "Forbid",
        job_template: cronjob.JobTemplate(
          backoff_limit: 1,
          ttl_seconds: 18_000,
          restart_policy: "Never",
          containers: [
            cronjob.JobContainer(
              name: "backup-container",
              image: j.image,
              image_pull_policy: Some("IfNotPresent"),
              env: env,
              volume_mounts: volume_mounts,
              command: j.command,
            ),
          ],
          volumes: volumes,
        ),
      ),
    )

  cronjob.to_cymbal(cj)
}

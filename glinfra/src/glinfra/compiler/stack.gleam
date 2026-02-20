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
import glinfra/blueprint/job
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage.{type Storage}
import glinfra/k8s
import glinfra/k8s/cronjob
import glinfra/k8s/deployment
import glinfra/k8s/helm_release
import glinfra/k8s/helm_repository
import glinfra/k8s/ingress
import glinfra/k8s/namespace
import glinfra/k8s/persistent_volume_claim
import glinfra/k8s/service

pub type Stacks {
  Stacks(plugins: List(AppPlugin), stacks: List(Stack))
}

pub fn stacks() -> Stacks {
  Stacks(plugins: [], stacks: [])
}

pub fn plugins(s: Stacks, p: List(AppPlugin)) -> Stacks {
  Stacks(..s, plugins: list.append(s.plugins, p))
}

pub fn add(s: Stacks, stack: Stack) -> Stacks {
  Stacks(..s, stacks: [stack, ..s.stacks])
}

pub fn add_all(env: Environment, s: Stacks) -> Environment {
  list.fold(list.reverse(s.stacks), env, fn(env, stack) {
    let provider =
      Provider(resources: [
        Resource(name: stack.name, render: fn(_env) {
          stack_to_cymbal(stack, s.plugins)
        }),
      ])
    environment.add_provider(env, provider)
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
  let App(name, port, containers, plugins) = a
  let labels = [#("app", name)]
  let all_plugins = list.append(global_plugins, plugins)
  let stack_app = ContainerApp(a)

  let docs = [
    app_to_deployment(ns, name, port, containers, labels)
      |> apply_deployment_plugins(stack_app, all_plugins)
      |> deployment.to_cymbal,
    app_to_service(ns, name, port, labels)
      |> apply_service_plugins(stack_app, all_plugins)
      |> service.to_cymbal,
  ]

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
) -> deployment.Deployment {
  let has_storage =
    list.any(app_containers, fn(c) { !list.is_empty(c.storage) })

  let strategy = case has_storage {
    True -> Some(deployment.Recreate)
    False -> None
  }

  let volumes =
    list.flat_map(app_containers, fn(c) {
      list.map(c.storage, fn(s) {
        let #(_mount_path, storage_ref) = s
        let pvc_name = storage_ref.name
        deployment.PvcVolume(name: pvc_name <> "-volume", claim_name: pvc_name)
      })
    })

  let containers =
    list.index_map(app_containers, fn(c, i) {
      let image_ref = c.image.name <> ":" <> c.image.tag
      let ports =
        list.map(port, fn(p) {
          deployment.ContainerPort(
            container_port: p.number,
            protocol: Some("TCP"),
          )
        })
      let volume_mounts =
        list.map(c.storage, fn(s) {
          let #(mount_path, storage_ref) = s
          deployment.VolumeMount(
            name: storage_ref.name <> "-volume",
            mount_path: mount_path,
          )
        })
      let container_name = name <> "-" <> int.to_string(i)
      deployment.Container(
        name: container_name,
        image: image_ref,
        ports: ports,
        env: [],
        volume_mounts: volume_mounts,
        resources: deployment.ResourceRequirements(limits: [], requests: []),
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

fn storage_to_pvc(
  ns: String,
  s: Storage,
) -> persistent_volume_claim.PersistentVolumeClaim {
  persistent_volume_claim.PersistentVolumeClaim(
    metadata: k8s.ObjectMeta(
      name: s.name,
      namespace: Some(ns),
      labels: [],
      annotations: [],
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
  let volumes =
    list.map(j.volumes, fn(v) {
      case v {
        job.PvcVolume(_, storage_ref) ->
          cronjob.PvcVolume(
            name: storage_ref.name <> "-volume",
            claim_name: storage_ref.name,
          )
        job.SecretVolume(_, secret_name) ->
          cronjob.SecretVolume(
            name: secret_name <> "-volume",
            secret_name: secret_name,
            default_mode: Some(256),
          )
      }
    })

  let volume_mounts =
    list.map(j.volumes, fn(v) {
      case v {
        job.PvcVolume(mount_path, storage_ref) ->
          cronjob.JobVolumeMount(
            name: storage_ref.name <> "-volume",
            mount_path: mount_path,
            read_only: None,
          )
        job.SecretVolume(mount_path, secret_name) ->
          cronjob.JobVolumeMount(
            name: secret_name <> "-volume",
            mount_path: mount_path,
            read_only: Some(True),
          )
      }
    })

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

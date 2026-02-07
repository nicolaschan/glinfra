import cymbal
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/environment.{type Environment, Provider}
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage.{type Storage}
import glinfra/k8s
import glinfra/k8s/deployment
import glinfra/k8s/ingress
import glinfra/k8s/namespace
import glinfra/k8s/persistent_volume_claim
import glinfra/k8s/service

pub type StackPlugin {
  StackPlugin(
    service_annotations: fn(App) -> List(#(String, String)),
    ingress_annotations: fn(App) -> List(#(String, String)),
    extra_resources: fn(String, App) -> List(cymbal.Yaml),
  )
}

pub type StackCompiler {
  StackCompiler(plugins: List(StackPlugin))
}

pub fn compiler(plugins: List(StackPlugin)) -> StackCompiler {
  StackCompiler(plugins: plugins)
}

pub fn to_provider(sc: StackCompiler, stack: Stack) -> environment.Provider {
  let plugins = sc.plugins
  Provider(resources: [
    #(stack.name, fn(_env) { stack_to_cymbal(stack, plugins) }),
  ])
}

pub fn add(env: Environment, stack: Stack, sc: StackCompiler) -> Environment {
  environment.add_provider(env, to_provider(sc, stack))
}

fn stack_to_cymbal(
  stack: Stack,
  plugins: List(StackPlugin),
) -> List(cymbal.Yaml) {
  let ns = namespace.new(stack.name)
  let docs = [namespace.to_cymbal(ns)]

  let docs =
    list.fold(stack.apps, docs, fn(docs, application) {
      app_to_cymbal(stack.name, plugins, application)
      |> list.append(docs, _)
    })

  let docs =
    list.append(
      docs,
      list.map(stack.storage, fn(s) {
        storage_to_pvc(stack.name, s) |> persistent_volume_claim.to_cymbal
      }),
    )

  docs
}

fn app_to_cymbal(
  ns: String,
  plugins: List(StackPlugin),
  application: App,
) -> List(cymbal.Yaml) {
  let labels = [#("app", application.name)]

  let service_annotations =
    list.flat_map(plugins, fn(p) { p.service_annotations(application) })
  let ingress_annotations =
    list.flat_map(plugins, fn(p) { p.ingress_annotations(application) })

  let docs = [
    app_to_deployment(ns, application, labels)
      |> deployment.to_cymbal,
    app_to_service(ns, application, labels, service_annotations)
      |> service.to_cymbal,
  ]

  let docs = case app_to_ingress(ns, application, labels, ingress_annotations) {
    Some(ing) -> list.append(docs, [ingress.to_cymbal(ing)])
    None -> docs
  }

  let docs =
    list.fold(plugins, docs, fn(docs, plugin) {
      list.append(docs, plugin.extra_resources(ns, application))
    })

  docs
}

fn app_to_deployment(
  ns: String,
  application: App,
  labels: List(#(String, String)),
) -> deployment.Deployment {
  let has_storage =
    list.any(application.containers, fn(c) { !list.is_empty(c.storage) })

  let strategy = case has_storage {
    True -> Some(deployment.Recreate)
    False -> None
  }

  let volumes =
    list.flat_map(application.containers, fn(c) {
      list.map(c.storage, fn(s) {
        let #(_mount_path, storage_ref) = s
        let pvc_name = storage_ref.name
        deployment.PvcVolume(name: pvc_name <> "-volume", claim_name: pvc_name)
      })
    })

  let containers =
    list.index_map(application.containers, fn(c, i) {
      let image_ref = c.image.name <> ":" <> c.image.tag
      let ports =
        list.map(application.port, fn(p) {
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
      let name = application.name <> "-" <> int.to_string(i)
      deployment.Container(
        name: name,
        image: image_ref,
        ports: ports,
        env: [],
        volume_mounts: volume_mounts,
      )
    })

  deployment.Deployment(
    metadata: k8s.ObjectMeta(
      name: application.name,
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
          name: application.name,
          namespace: None,
          labels: labels,
          annotations: [],
        ),
        containers: containers,
        volumes: volumes,
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
  application: App,
  labels: List(#(String, String)),
  annotations: List(#(String, String)),
) -> service.Service {
  let ports =
    list.index_map(application.port, fn(p, i) {
      let name = case list.length(application.port) > 1 {
        True -> Some(application.name <> "-" <> int.to_string(i))
        False -> None
      }
      service.ServicePort(
        name: name,
        port: p.number,
        target_port: p.number,
        protocol: Some("TCP"),
      )
    })

  service.Service(
    metadata: k8s.ObjectMeta(
      name: application.name,
      namespace: Some(ns),
      labels: labels,
      annotations: annotations,
    ),
    spec: service.ServiceSpec(selector: labels, ports: ports),
  )
}

fn app_to_ingress(
  ns: String,
  application: App,
  _labels: List(#(String, String)),
  annotations: List(#(String, String)),
) -> Option(ingress.Ingress) {
  let rules =
    list.flat_map(application.port, fn(p) {
      list.map(p.ingress, fn(ing) {
        ingress.IngressRule(host: ing.host, paths: [
          ingress.IngressPath(
            path: "/",
            path_type: "Prefix",
            backend: ingress.IngressBackend(
              service_name: application.name,
              service_port: p.number,
            ),
          ),
        ])
      })
    })

  let hosts =
    list.flat_map(application.port, fn(p) {
      list.map(p.ingress, fn(ing) { ing.host })
    })

  case rules {
    [] -> None
    _ ->
      Some(ingress.Ingress(
        metadata: k8s.ObjectMeta(
          name: application.name,
          namespace: Some(ns),
          labels: [],
          annotations: annotations,
        ),
        spec: ingress.IngressSpec(ingress_class_name: None, rules: rules, tls: [
          ingress.IngressTls(
            hosts: hosts,
            secret_name: application.name <> "-cert",
          ),
        ]),
      ))
  }
}

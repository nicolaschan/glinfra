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

pub fn to_provider(
  global_plugins: List(app.AppPlugin),
  stack: Stack,
) -> environment.Provider {
  Provider(resources: [
    #(stack.name, fn(_env) { stack_to_cymbal(stack, global_plugins) }),
  ])
}

pub fn add(
  env: Environment,
  stack: Stack,
  global_plugins: List(app.AppPlugin),
) -> Environment {
  environment.add_provider(env, to_provider(global_plugins, stack))
}

fn stack_to_cymbal(
  stack: Stack,
  global_plugins: List(app.AppPlugin),
) -> List(cymbal.Yaml) {
  let ns = namespace.new(stack.name)
  let docs = [namespace.to_cymbal(ns)]

  let docs =
    list.fold(stack.apps, docs, fn(docs, application) {
      app_to_cymbal(stack.name, global_plugins, application)
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
  global_plugins: List(app.AppPlugin),
  application: App,
) -> List(cymbal.Yaml) {
  let labels = [#("app", application.name)]
  let all_plugins = list.append(global_plugins, application.plugins)

  let docs = [
    app_to_deployment(ns, application, labels)
      |> apply_deployment_plugins(application, all_plugins)
      |> deployment.to_cymbal,
    app_to_service(ns, application, labels)
      |> apply_service_plugins(application, all_plugins)
      |> service.to_cymbal,
  ]

  let docs = case app_to_ingress(ns, application, labels) {
    Some(ing) ->
      list.append(docs, [
        ing
        |> apply_ingress_plugins(application, all_plugins)
        |> ingress.to_cymbal,
      ])
    None -> docs
  }

  let docs = apply_extra_resources(docs, ns, application, all_plugins)

  docs
}

fn apply_deployment_plugins(
  dep: deployment.Deployment,
  application: App,
  plugins: List(app.AppPlugin),
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
  application: App,
  plugins: List(app.AppPlugin),
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
  application: App,
  plugins: List(app.AppPlugin),
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
  application: App,
  plugins: List(app.AppPlugin),
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
        resources: deployment.ResourceRequirements(limits: [], requests: []),
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
  application: App,
  labels: List(#(String, String)),
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
      annotations: [],
    ),
    spec: service.ServiceSpec(selector: labels, ports: ports),
  )
}

fn app_to_ingress(
  ns: String,
  application: App,
  _labels: List(#(String, String)),
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
          annotations: [],
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

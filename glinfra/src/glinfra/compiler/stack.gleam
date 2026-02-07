import cymbal
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/environment.{
  type Environment, type Provider, type UpdateConfig, Provider,
}
import glinfra/blueprint/image.{type Image}
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage.{type Storage}
import glinfra/k8s
import glinfra/k8s/deployment
import glinfra/k8s/image_policy
import glinfra/k8s/image_repository
import glinfra/k8s/image_update_automation
import glinfra/k8s/ingress
import glinfra/k8s/namespace
import glinfra/k8s/persistent_volume_claim
import glinfra/k8s/service

pub fn to_provider(stack: Stack) -> Provider {
  Provider(
    service_annotations: fn(_) { [] },
    ingress_annotations: fn(_) { [] },
    resources: [#(stack.name, fn(env) { stack_to_cymbal(stack, env) })],
  )
}

pub fn add(env: Environment, stack: Stack) -> Environment {
  environment.add_provider(env, to_provider(stack))
}

fn stack_to_cymbal(stack: Stack, env: Environment) -> List(cymbal.Yaml) {
  let ns = namespace.new(stack.name)
  let docs = [namespace.to_cymbal(ns)]

  let docs =
    list.fold(stack.apps, docs, fn(docs, application) {
      app_to_cymbal(stack.name, env.update, env.providers, application)
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
  update: Option(UpdateConfig),
  providers: List(Provider),
  application: App,
) -> List(cymbal.Yaml) {
  let labels = [#("app", application.name)]

  let service_annotations =
    list.flat_map(providers, fn(p) { p.service_annotations(application) })
  let ingress_annotations =
    list.flat_map(providers, fn(p) { p.ingress_annotations(application) })

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

  let docs = case update {
    Some(config) ->
      list.append(docs, app_to_image_update_cymbal(ns, application, config))
    None -> docs
  }

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

fn app_to_image_update_cymbal(
  ns: String,
  application: App,
  config: UpdateConfig,
) -> List(cymbal.Yaml) {
  application.containers
  |> list.filter_map(fn(c) {
    case c.image.update {
      Some(_) -> Ok(c.image)
      None -> Error(Nil)
    }
  })
  |> list.flat_map(fn(image) {
    image_to_update_cymbal(ns, application.name, image, config)
  })
}

fn image_to_update_cymbal(
  ns: String,
  app_name: String,
  image: Image,
  config: UpdateConfig,
) -> List(cymbal.Yaml) {
  let assert Some(update) = image.update
  let slug = image_name_to_slug(image.name)
  let repo_name = slug <> "-repo"
  let policy_name = slug
  let automation_name = slug <> "-update"
  let update_path = config.path_prefix <> "/" <> app_name

  let repo =
    image_repository.ImageRepository(
      metadata: k8s.ObjectMeta(
        name: repo_name,
        namespace: Some(ns),
        labels: [],
        annotations: [],
      ),
      spec: image_repository.ImageRepositorySpec(
        image: image.name,
        interval: "5m",
        secret_ref: None,
      ),
    )

  let policy =
    image_policy.ImagePolicy(
      metadata: k8s.ObjectMeta(
        name: policy_name,
        namespace: Some(ns),
        labels: [],
        annotations: [],
      ),
      spec: image_policy.ImagePolicySpec(
        image_repository_ref: repo_name,
        filter_tags: Some(image_policy.FilterTags(pattern: update.pattern)),
        policy: image_policy.Alphabetical(order: "asc"),
      ),
    )

  let automation =
    image_update_automation.ImageUpdateAutomation(
      metadata: k8s.ObjectMeta(
        name: automation_name,
        namespace: Some(ns),
        labels: [],
        annotations: [],
      ),
      spec: image_update_automation.ImageUpdateAutomationSpec(
        interval: "5m",
        source_ref: image_update_automation.SourceRef(
          kind: "GitRepository",
          name: config.git_repo,
          namespace: Some(config.git_repo_namespace),
        ),
        git: image_update_automation.GitSpec(
          commit: image_update_automation.GitCommit(
            author: image_update_automation.GitAuthor(
              name: config.author_name,
              email: config.author_email,
            ),
            message_template: "chore: update " <> app_name <> " image",
          ),
          push: image_update_automation.GitPush(branch: config.branch),
        ),
        update: image_update_automation.UpdateSpec(path: update_path),
      ),
    )

  [
    image_repository.to_cymbal(repo),
    image_policy.to_cymbal(policy),
    image_update_automation.to_cymbal(automation),
  ]
}

fn image_name_to_slug(name: String) -> String {
  name
  |> string.replace("/", "-")
  |> string.replace(".", "-")
}

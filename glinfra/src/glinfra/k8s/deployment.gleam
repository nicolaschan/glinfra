import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type LabelSelector, type ObjectMeta}

pub type ContainerPort {
  ContainerPort(container_port: Int, protocol: Option(String))
}

pub type EnvVar {
  EnvVar(name: String, value: String)
}

pub type Container {
  Container(
    name: String,
    image: String,
    ports: List(ContainerPort),
    env: List(EnvVar),
  )
}

pub type PodTemplateSpec {
  PodTemplateSpec(metadata: ObjectMeta, containers: List(Container))
}

pub type DeploymentSpec {
  DeploymentSpec(
    replicas: Int,
    selector: LabelSelector,
    template: PodTemplateSpec,
  )
}

pub type Deployment {
  Deployment(metadata: ObjectMeta, spec: DeploymentSpec)
}

pub fn to_cymbal(d: Deployment) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("apps/v1")),
    #("kind", cymbal.string("Deployment")),
    #("metadata", k8s.object_meta_to_cymbal(d.metadata)),
    #("spec", deployment_spec_to_cymbal(d.spec)),
  ])
}

pub fn to_yaml(d: Deployment) -> String {
  cymbal.encode(to_cymbal(d))
}

fn deployment_spec_to_cymbal(s: DeploymentSpec) -> cymbal.Yaml {
  cymbal.block([
    #("replicas", cymbal.int(s.replicas)),
    #("selector", k8s.label_selector_to_cymbal(s.selector)),
    #("template", pod_template_to_cymbal(s.template)),
  ])
}

fn pod_template_to_cymbal(t: PodTemplateSpec) -> cymbal.Yaml {
  cymbal.block([
    #("metadata", k8s.object_meta_to_cymbal(t.metadata)),
    #(
      "spec",
      cymbal.block([
        #(
          "containers",
          cymbal.array(list.map(t.containers, container_to_cymbal)),
        ),
      ]),
    ),
  ])
}

fn container_to_cymbal(c: Container) -> cymbal.Yaml {
  let fields = [
    #("name", cymbal.string(c.name)),
    #("image", cymbal.string(c.image)),
  ]

  let fields = case c.ports {
    [] -> fields
    ports ->
      list.append(fields, [
        #("ports", cymbal.array(list.map(ports, container_port_to_cymbal))),
      ])
  }

  let fields = case c.env {
    [] -> fields
    env ->
      list.append(fields, [
        #("env", cymbal.array(list.map(env, env_var_to_cymbal))),
      ])
  }

  cymbal.block(fields)
}

fn container_port_to_cymbal(p: ContainerPort) -> cymbal.Yaml {
  let fields = [#("containerPort", cymbal.int(p.container_port))]
  case p.protocol {
    None -> cymbal.block(fields)
    Some(proto) ->
      cymbal.block(list.append(fields, [#("protocol", cymbal.string(proto))]))
  }
}

fn env_var_to_cymbal(e: EnvVar) -> cymbal.Yaml {
  cymbal.block([
    #("name", cymbal.string(e.name)),
    #("value", cymbal.string(e.value)),
  ])
}

pub fn new(
  name name: String,
  image image: String,
  replicas replicas: Int,
  port port: Int,
) -> Deployment {
  let labels = [#("app", name)]

  Deployment(
    metadata: k8s.ObjectMeta(
      name: name,
      namespace: None,
      labels: labels,
      annotations: [],
    ),
    spec: DeploymentSpec(
      replicas: replicas,
      selector: k8s.LabelSelector(match_labels: labels),
      template: PodTemplateSpec(
        metadata: k8s.ObjectMeta(
          name: name,
          namespace: None,
          labels: labels,
          annotations: [],
        ),
        containers: [
          Container(
            name: name,
            image: image,
            ports: [ContainerPort(container_port: port, protocol: Some("TCP"))],
            env: [],
          ),
        ],
      ),
    ),
  )
}

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

pub type VolumeMount {
  VolumeMount(name: String, mount_path: String)
}

pub type Volume {
  PvcVolume(name: String, claim_name: String)
}

pub type Strategy {
  Recreate
  RollingUpdate
}

pub type ResourceRequirements {
  ResourceRequirements(
    limits: List(#(String, String)),
    requests: List(#(String, String)),
  )
}

pub type Container {
  Container(
    name: String,
    image: String,
    ports: List(ContainerPort),
    env: List(EnvVar),
    volume_mounts: List(VolumeMount),
    resources: ResourceRequirements,
  )
}

pub type PodTemplateSpec {
  PodTemplateSpec(
    metadata: ObjectMeta,
    containers: List(Container),
    volumes: List(Volume),
    runtime_class_name: Option(String),
  )
}

pub type DeploymentSpec {
  DeploymentSpec(
    replicas: Int,
    selector: LabelSelector,
    strategy: Option(Strategy),
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
  let fields = [
    #("replicas", cymbal.int(s.replicas)),
    #("selector", k8s.label_selector_to_cymbal(s.selector)),
  ]

  let fields = case s.strategy {
    Some(strategy) ->
      list.append(fields, [#("strategy", strategy_to_cymbal(strategy))])
    None -> fields
  }

  let fields =
    list.append(fields, [#("template", pod_template_to_cymbal(s.template))])

  cymbal.block(fields)
}

fn strategy_to_cymbal(s: Strategy) -> cymbal.Yaml {
  case s {
    Recreate -> cymbal.block([#("type", cymbal.string("Recreate"))])
    RollingUpdate -> cymbal.block([#("type", cymbal.string("RollingUpdate"))])
  }
}

fn pod_template_to_cymbal(t: PodTemplateSpec) -> cymbal.Yaml {
  let spec_fields = [
    #("containers", cymbal.array(list.map(t.containers, container_to_cymbal))),
  ]

  let spec_fields = case t.runtime_class_name {
    Some(name) ->
      list.append(spec_fields, [
        #("runtimeClassName", cymbal.string(name)),
      ])
    None -> spec_fields
  }

  let spec_fields = case t.volumes {
    [] -> spec_fields
    vols ->
      list.append(spec_fields, [
        #("volumes", cymbal.array(list.map(vols, volume_to_cymbal))),
      ])
  }

  cymbal.block([
    #("metadata", k8s.object_meta_to_cymbal(t.metadata)),
    #("spec", cymbal.block(spec_fields)),
  ])
}

fn volume_to_cymbal(v: Volume) -> cymbal.Yaml {
  case v {
    PvcVolume(name, claim_name) ->
      cymbal.block([
        #("name", cymbal.string(name)),
        #(
          "persistentVolumeClaim",
          cymbal.block([#("claimName", cymbal.string(claim_name))]),
        ),
      ])
  }
}

fn container_to_cymbal(c: Container) -> cymbal.Yaml {
  let fields = [
    #("image", cymbal.string(c.image)),
    #("name", cymbal.string(c.name)),
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

  let fields = case c.resources.limits, c.resources.requests {
    [], [] -> fields
    limits, requests -> {
      let res_fields = case limits {
        [] -> []
        _ -> [#("limits", k8s.string_pairs_to_cymbal(limits))]
      }
      let res_fields = case requests {
        [] -> res_fields
        _ ->
          list.append(res_fields, [
            #("requests", k8s.string_pairs_to_cymbal(requests)),
          ])
      }
      list.append(fields, [#("resources", cymbal.block(res_fields))])
    }
  }

  cymbal.block(fields)
}

fn volume_mount_to_cymbal(m: VolumeMount) -> cymbal.Yaml {
  cymbal.block([
    #("mountPath", cymbal.string(m.mount_path)),
    #("name", cymbal.string(m.name)),
  ])
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
      strategy: None,
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
            volume_mounts: [],
            resources: ResourceRequirements(limits: [], requests: []),
          ),
        ],
        volumes: [],
        runtime_class_name: None,
      ),
    ),
  )
}

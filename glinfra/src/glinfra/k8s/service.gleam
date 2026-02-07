import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type ObjectMeta}

pub type ServicePort {
  ServicePort(
    name: Option(String),
    port: Int,
    target_port: Int,
    protocol: Option(String),
  )
}

pub type ServiceSpec {
  ServiceSpec(selector: List(#(String, String)), ports: List(ServicePort))
}

pub type Service {
  Service(metadata: ObjectMeta, spec: ServiceSpec)
}

pub fn to_cymbal(s: Service) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("v1")),
    #("kind", cymbal.string("Service")),
    #("metadata", k8s.object_meta_to_cymbal(s.metadata)),
    #("spec", service_spec_to_cymbal(s.spec)),
  ])
}

pub fn to_yaml(s: Service) -> String {
  cymbal.encode(to_cymbal(s))
}

fn service_spec_to_cymbal(s: ServiceSpec) -> cymbal.Yaml {
  cymbal.block([
    #("selector", k8s.string_pairs_to_cymbal(s.selector)),
    #("ports", cymbal.array(list.map(s.ports, service_port_to_cymbal))),
  ])
}

fn service_port_to_cymbal(p: ServicePort) -> cymbal.Yaml {
  let fields = case p.name {
    Some(name) -> [#("name", cymbal.string(name))]
    None -> []
  }

  let fields =
    list.append(fields, [
      #("port", cymbal.int(p.port)),
      #("targetPort", cymbal.int(p.target_port)),
    ])

  let fields = case p.protocol {
    Some(proto) -> list.append(fields, [#("protocol", cymbal.string(proto))])
    None -> fields
  }

  cymbal.block(fields)
}

pub fn new(name: String, port: Int) -> Service {
  Service(
    metadata: k8s.ObjectMeta(
      name: name,
      namespace: None,
      labels: [#("app", name)],
      annotations: [],
    ),
    spec: ServiceSpec(selector: [#("app", name)], ports: [
      ServicePort(
        name: None,
        port: port,
        target_port: port,
        protocol: Some("TCP"),
      ),
    ]),
  )
}

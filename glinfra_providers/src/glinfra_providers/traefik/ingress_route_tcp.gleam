import cymbal
import gleam/list
import glinfra/k8s.{type ObjectMeta}

pub type IngressRouteTCP {
  IngressRouteTCP(metadata: ObjectMeta, spec: IngressRouteTCPSpec)
}

pub type IngressRouteTCPSpec {
  IngressRouteTCPSpec(entry_points: List(String), routes: List(TCPRoute))
}

pub type TCPRoute {
  TCPRoute(match: String, services: List(TCPService))
}

pub type TCPService {
  TCPService(name: String, port: Int, weight: Int)
}

pub fn to_cymbal(r: IngressRouteTCP) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("traefik.io/v1alpha1")),
    #("kind", cymbal.string("IngressRouteTCP")),
    #("metadata", k8s.object_meta_to_cymbal(r.metadata)),
    #("spec", spec_to_cymbal(r.spec)),
  ])
}

pub fn to_yaml(r: IngressRouteTCP) -> String {
  cymbal.encode(to_cymbal(r))
}

fn spec_to_cymbal(s: IngressRouteTCPSpec) -> cymbal.Yaml {
  cymbal.block([
    #("entryPoints", cymbal.array(list.map(s.entry_points, cymbal.string))),
    #("routes", cymbal.array(list.map(s.routes, route_to_cymbal))),
  ])
}

fn route_to_cymbal(r: TCPRoute) -> cymbal.Yaml {
  cymbal.block([
    #("match", cymbal.string(r.match)),
    #("services", cymbal.array(list.map(r.services, service_to_cymbal))),
  ])
}

fn service_to_cymbal(s: TCPService) -> cymbal.Yaml {
  cymbal.block([
    #("name", cymbal.string(s.name)),
    #("port", cymbal.int(s.port)),
    #("weight", cymbal.int(s.weight)),
  ])
}

pub fn new(
  name: String,
  entry_points: List(String),
  service_name: String,
  service_port: Int,
) -> IngressRouteTCP {
  IngressRouteTCP(
    metadata: k8s.meta(name),
    spec: IngressRouteTCPSpec(entry_points: entry_points, routes: [
      TCPRoute(match: "HostSNI(`*`)", services: [
        TCPService(name: service_name, port: service_port, weight: 10),
      ]),
    ]),
  )
}

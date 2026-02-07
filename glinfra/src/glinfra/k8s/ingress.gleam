import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type ObjectMeta}

pub type IngressRule {
  IngressRule(host: String, paths: List(IngressPath))
}

pub type IngressPath {
  IngressPath(path: String, path_type: String, backend: IngressBackend)
}

pub type IngressBackend {
  IngressBackend(service_name: String, service_port: Int)
}

pub type IngressTls {
  IngressTls(hosts: List(String), secret_name: String)
}

pub type IngressSpec {
  IngressSpec(
    ingress_class_name: Option(String),
    rules: List(IngressRule),
    tls: List(IngressTls),
  )
}

pub type Ingress {
  Ingress(metadata: ObjectMeta, spec: IngressSpec)
}

pub fn to_cymbal(i: Ingress) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("networking.k8s.io/v1")),
    #("kind", cymbal.string("Ingress")),
    #("metadata", k8s.object_meta_to_cymbal(i.metadata)),
    #("spec", ingress_spec_to_cymbal(i.spec)),
  ])
}

pub fn to_yaml(i: Ingress) -> String {
  cymbal.encode(to_cymbal(i))
}

fn ingress_spec_to_cymbal(s: IngressSpec) -> cymbal.Yaml {
  let fields = case s.ingress_class_name {
    Some(class) -> [#("ingressClassName", cymbal.string(class))]
    None -> []
  }

  let fields =
    list.append(fields, [
      #("rules", cymbal.array(list.map(s.rules, ingress_rule_to_cymbal))),
    ])

  let fields = case s.tls {
    [] -> fields
    tls ->
      list.append(fields, [
        #("tls", cymbal.array(list.map(tls, ingress_tls_to_cymbal))),
      ])
  }

  cymbal.block(fields)
}

fn ingress_tls_to_cymbal(t: IngressTls) -> cymbal.Yaml {
  cymbal.block([
    #("hosts", cymbal.array(list.map(t.hosts, cymbal.string))),
    #("secretName", cymbal.string(t.secret_name)),
  ])
}

fn ingress_rule_to_cymbal(r: IngressRule) -> cymbal.Yaml {
  cymbal.block([
    #("host", cymbal.string(r.host)),
    #(
      "http",
      cymbal.block([
        #("paths", cymbal.array(list.map(r.paths, ingress_path_to_cymbal))),
      ]),
    ),
  ])
}

fn ingress_path_to_cymbal(p: IngressPath) -> cymbal.Yaml {
  cymbal.block([
    #("path", cymbal.string(p.path)),
    #("pathType", cymbal.string(p.path_type)),
    #(
      "backend",
      cymbal.block([
        #(
          "service",
          cymbal.block([
            #("name", cymbal.string(p.backend.service_name)),
            #(
              "port",
              cymbal.block([#("number", cymbal.int(p.backend.service_port))]),
            ),
          ]),
        ),
      ]),
    ),
  ])
}

pub fn new(
  name name: String,
  host host: String,
  service_name service_name: String,
  service_port service_port: Int,
) -> Ingress {
  Ingress(
    metadata: k8s.meta(name),
    spec: IngressSpec(ingress_class_name: None, tls: [], rules: [
      IngressRule(host: host, paths: [
        IngressPath(
          path: "/",
          path_type: "Prefix",
          backend: IngressBackend(
            service_name: service_name,
            service_port: service_port,
          ),
        ),
      ]),
    ]),
  )
}

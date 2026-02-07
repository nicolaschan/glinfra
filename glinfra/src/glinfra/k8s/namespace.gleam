import cymbal
import glinfra/k8s.{type ObjectMeta}

pub type Namespace {
  Namespace(metadata: ObjectMeta)
}

pub fn to_cymbal(ns: Namespace) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("v1")),
    #("kind", cymbal.string("Namespace")),
    #("metadata", k8s.object_meta_to_cymbal(ns.metadata)),
  ])
}

pub fn to_yaml(ns: Namespace) -> String {
  cymbal.encode(to_cymbal(ns))
}

pub fn new(name: String) -> Namespace {
  Namespace(metadata: k8s.meta(name))
}

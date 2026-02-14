import cymbal
import glinfra/k8s.{type ObjectMeta}

pub type HelmRepository {
  HelmRepository(metadata: ObjectMeta, spec: HelmRepositorySpec)
}

pub type HelmRepositorySpec {
  HelmRepositorySpec(interval: String, url: String)
}

pub fn to_cymbal(r: HelmRepository) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("source.toolkit.fluxcd.io/v1")),
    #("kind", cymbal.string("HelmRepository")),
    #("metadata", k8s.object_meta_to_cymbal(r.metadata)),
    #(
      "spec",
      cymbal.block([
        #("interval", cymbal.string(r.spec.interval)),
        #("url", cymbal.string(r.spec.url)),
      ]),
    ),
  ])
}

pub fn to_yaml(r: HelmRepository) -> String {
  cymbal.encode(to_cymbal(r))
}

pub fn new(name: String, url: String) -> HelmRepository {
  HelmRepository(
    metadata: k8s.meta(name),
    spec: HelmRepositorySpec(interval: "1m", url: url),
  )
}

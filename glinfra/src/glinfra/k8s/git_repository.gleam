import cymbal
import gleam/list
import gleam/option.{type Option, None}
import glinfra/k8s.{type ObjectMeta}

pub type GitRepositorySpec {
  GitRepositorySpec(
    url: String,
    interval: String,
    ref: GitRef,
    secret_ref: Option(String),
  )
}

pub type GitRef {
  GitRefBranch(branch: String)
  GitRefTag(tag: String)
}

pub type GitRepository {
  GitRepository(metadata: ObjectMeta, spec: GitRepositorySpec)
}

pub fn to_cymbal(r: GitRepository) -> cymbal.Yaml {
  let ref_fields = case r.spec.ref {
    GitRefBranch(branch) -> [#("branch", cymbal.string(branch))]
    GitRefTag(tag) -> [#("tag", cymbal.string(tag))]
  }

  let spec_fields = [
    #("url", cymbal.string(r.spec.url)),
    #("interval", cymbal.string(r.spec.interval)),
    #("ref", cymbal.block(ref_fields)),
  ]

  let spec_fields = case r.spec.secret_ref {
    option.Some(ref) ->
      list.append(spec_fields, [
        #("secretRef", cymbal.block([#("name", cymbal.string(ref))])),
      ])
    None -> spec_fields
  }

  cymbal.block([
    #("apiVersion", cymbal.string("source.toolkit.fluxcd.io/v1")),
    #("kind", cymbal.string("GitRepository")),
    #("metadata", k8s.object_meta_to_cymbal(r.metadata)),
    #("spec", cymbal.block(spec_fields)),
  ])
}

pub fn to_yaml(r: GitRepository) -> String {
  cymbal.encode(to_cymbal(r))
}

pub fn new(name: String, url: String, branch: String) -> GitRepository {
  GitRepository(
    metadata: k8s.meta(name),
    spec: GitRepositorySpec(
      url: url,
      interval: "1m",
      ref: GitRefBranch(branch: branch),
      secret_ref: None,
    ),
  )
}

import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type ObjectMeta}

pub type ImagePolicySpec {
  ImagePolicySpec(
    image_repository_ref: String,
    filter_tags: Option(FilterTags),
    policy: ImagePolicyRule,
  )
}

pub type FilterTags {
  FilterTags(pattern: String)
}

pub type ImagePolicyRule {
  SemVer(range: String)
  Alphabetical(order: String)
  Numerical(order: String)
}

pub type ImagePolicy {
  ImagePolicy(metadata: ObjectMeta, spec: ImagePolicySpec)
}

pub fn to_cymbal(p: ImagePolicy) -> cymbal.Yaml {
  let spec_fields = [
    #(
      "imageRepositoryRef",
      cymbal.block([
        #("name", cymbal.string(p.spec.image_repository_ref)),
      ]),
    ),
  ]

  let spec_fields = case p.spec.filter_tags {
    Some(FilterTags(pattern)) -> [
      #("filterTags", cymbal.block([#("pattern", cymbal.string(pattern))])),
      ..spec_fields
    ]
    None -> spec_fields
  }

  let spec_fields =
    list.append(spec_fields, [
      #("policy", policy_rule_to_cymbal(p.spec.policy)),
    ])

  cymbal.block([
    #("apiVersion", cymbal.string("image.toolkit.fluxcd.io/v1")),
    #("kind", cymbal.string("ImagePolicy")),
    #("metadata", k8s.object_meta_to_cymbal(p.metadata)),
    #("spec", cymbal.block(spec_fields)),
  ])
}

pub fn to_yaml(p: ImagePolicy) -> String {
  cymbal.encode(to_cymbal(p))
}

fn policy_rule_to_cymbal(rule: ImagePolicyRule) -> cymbal.Yaml {
  case rule {
    SemVer(range) ->
      cymbal.block([
        #("semver", cymbal.block([#("range", cymbal.string(range))])),
      ])
    Alphabetical(order) ->
      cymbal.block([
        #("alphabetical", cymbal.block([#("order", cymbal.string(order))])),
      ])
    Numerical(order) ->
      cymbal.block([
        #("numerical", cymbal.block([#("order", cymbal.string(order))])),
      ])
  }
}

pub fn new_semver(name: String, repo_ref: String, range: String) -> ImagePolicy {
  ImagePolicy(
    metadata: k8s.meta(name),
    spec: ImagePolicySpec(
      image_repository_ref: repo_ref,
      filter_tags: None,
      policy: SemVer(range: range),
    ),
  )
}

pub fn new_alphabetical(
  name: String,
  repo_ref: String,
  order: String,
) -> ImagePolicy {
  ImagePolicy(
    metadata: k8s.meta(name),
    spec: ImagePolicySpec(
      image_repository_ref: repo_ref,
      filter_tags: None,
      policy: Alphabetical(order: order),
    ),
  )
}

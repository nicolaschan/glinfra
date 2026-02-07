import cymbal
import gleam/list
import gleam/option.{type Option, None}
import glinfra/k8s.{type ObjectMeta}

pub type ImageRepositorySpec {
  ImageRepositorySpec(
    image: String,
    interval: String,
    secret_ref: Option(String),
  )
}

pub type ImageRepository {
  ImageRepository(metadata: ObjectMeta, spec: ImageRepositorySpec)
}

pub fn to_cymbal(r: ImageRepository) -> cymbal.Yaml {
  let spec_fields = [
    #("image", cymbal.string(r.spec.image)),
    #("interval", cymbal.string(r.spec.interval)),
  ]

  let spec_fields = case r.spec.secret_ref {
    option.Some(ref) ->
      list.append(spec_fields, [
        #("secretRef", cymbal.block([#("name", cymbal.string(ref))])),
      ])
    None -> spec_fields
  }

  cymbal.block([
    #("apiVersion", cymbal.string("image.toolkit.fluxcd.io/v1")),
    #("kind", cymbal.string("ImageRepository")),
    #("metadata", k8s.object_meta_to_cymbal(r.metadata)),
    #("spec", cymbal.block(spec_fields)),
  ])
}

pub fn to_yaml(r: ImageRepository) -> String {
  cymbal.encode(to_cymbal(r))
}

pub fn new(name: String, image: String) -> ImageRepository {
  ImageRepository(
    metadata: k8s.meta(name),
    spec: ImageRepositorySpec(image: image, interval: "1m", secret_ref: None),
  )
}

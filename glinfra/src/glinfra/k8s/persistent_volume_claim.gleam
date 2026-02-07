import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type ObjectMeta}

pub type PersistentVolumeClaim {
  PersistentVolumeClaim(metadata: ObjectMeta, spec: PvcSpec)
}

pub type PvcSpec {
  PvcSpec(
    access_modes: List(String),
    storage: String,
    storage_class_name: Option(String),
    volume_name: Option(String),
  )
}

pub fn to_cymbal(pvc: PersistentVolumeClaim) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("v1")),
    #("kind", cymbal.string("PersistentVolumeClaim")),
    #("metadata", k8s.object_meta_to_cymbal(pvc.metadata)),
    #("spec", spec_to_cymbal(pvc.spec)),
  ])
}

pub fn to_yaml(pvc: PersistentVolumeClaim) -> String {
  cymbal.encode(to_cymbal(pvc))
}

pub fn new(name: String, storage: String) -> PersistentVolumeClaim {
  PersistentVolumeClaim(
    metadata: k8s.meta(name),
    spec: PvcSpec(
      access_modes: ["ReadWriteOnce"],
      storage: storage,
      storage_class_name: None,
      volume_name: None,
    ),
  )
}

pub fn with_access_modes(
  pvc: PersistentVolumeClaim,
  modes: List(String),
) -> PersistentVolumeClaim {
  PersistentVolumeClaim(..pvc, spec: PvcSpec(..pvc.spec, access_modes: modes))
}

pub fn with_storage_class(
  pvc: PersistentVolumeClaim,
  class: String,
) -> PersistentVolumeClaim {
  PersistentVolumeClaim(
    ..pvc,
    spec: PvcSpec(..pvc.spec, storage_class_name: Some(class)),
  )
}

pub fn with_volume_name(
  pvc: PersistentVolumeClaim,
  name: String,
) -> PersistentVolumeClaim {
  PersistentVolumeClaim(
    ..pvc,
    spec: PvcSpec(..pvc.spec, volume_name: Some(name)),
  )
}

fn spec_to_cymbal(spec: PvcSpec) -> cymbal.Yaml {
  let fields = [
    #("accessModes", cymbal.array(list.map(spec.access_modes, cymbal.string))),
    #("resources", resources_to_cymbal(spec.storage)),
  ]

  let fields = case spec.storage_class_name {
    Some(class) ->
      list.append(fields, [#("storageClassName", cymbal.string(class))])
    None -> fields
  }

  let fields = case spec.volume_name {
    Some(name) -> list.append(fields, [#("volumeName", cymbal.string(name))])
    None -> fields
  }

  cymbal.block(fields)
}

fn resources_to_cymbal(storage: String) -> cymbal.Yaml {
  cymbal.block([
    #("requests", cymbal.block([#("storage", cymbal.string(storage))])),
  ])
}

import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}

// ---------------------------------------------------------------------------
// Shared Kubernetes types
// ---------------------------------------------------------------------------

/// Metadata attached to any Kubernetes object.
pub type ObjectMeta {
  ObjectMeta(
    name: String,
    namespace: Option(String),
    labels: List(#(String, String)),
    annotations: List(#(String, String)),
  )
}

/// Label selector used to match pods.
pub type LabelSelector {
  LabelSelector(match_labels: List(#(String, String)))
}

// ---------------------------------------------------------------------------
// Shared YAML helpers
// ---------------------------------------------------------------------------

pub fn object_meta_to_cymbal(m: ObjectMeta) -> cymbal.Yaml {
  let fields = [#("name", cymbal.string(m.name))]

  let fields = case m.namespace {
    Some(ns) -> list.append(fields, [#("namespace", cymbal.string(ns))])
    None -> fields
  }

  let fields = case m.labels {
    [] -> fields
    labels -> list.append(fields, [#("labels", string_pairs_to_cymbal(labels))])
  }

  let fields = case m.annotations {
    [] -> fields
    annotations ->
      list.append(fields, [
        #("annotations", string_pairs_to_cymbal(annotations)),
      ])
  }

  cymbal.block(fields)
}

pub fn string_pairs_to_cymbal(pairs: List(#(String, String))) -> cymbal.Yaml {
  cymbal.block(list.map(pairs, fn(pair) { #(pair.0, cymbal.string(pair.1)) }))
}

pub fn label_selector_to_cymbal(s: LabelSelector) -> cymbal.Yaml {
  cymbal.block([#("matchLabels", string_pairs_to_cymbal(s.match_labels))])
}

// ---------------------------------------------------------------------------
// Convenience constructors
// ---------------------------------------------------------------------------

pub fn meta(name: String) -> ObjectMeta {
  ObjectMeta(name: name, namespace: None, labels: [], annotations: [])
}

pub fn meta_ns(name: String, namespace: String) -> ObjectMeta {
  ObjectMeta(
    name: name,
    namespace: Some(namespace),
    labels: [],
    annotations: [],
  )
}

/// Encode any cymbal document to a YAML string.
pub fn to_yaml(doc: cymbal.Yaml) -> String {
  cymbal.encode(doc)
}

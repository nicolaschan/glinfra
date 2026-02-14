import cymbal
import gleam/list
import gleam/option.{type Option, None}
import glinfra/k8s.{type ObjectMeta}

pub type HelmRelease {
  HelmRelease(metadata: ObjectMeta, spec: HelmReleaseSpec)
}

pub type HelmReleaseSpec {
  HelmReleaseSpec(
    interval: String,
    chart: ChartSpec,
    values: Option(cymbal.Yaml),
  )
}

pub type ChartSpec {
  ChartSpec(
    chart: String,
    version: String,
    source_ref: SourceRef,
    interval: String,
  )
}

pub type SourceRef {
  SourceRef(kind: String, name: String, namespace: String)
}

pub fn to_cymbal(r: HelmRelease) -> cymbal.Yaml {
  let chart_fields = [
    #("chart", cymbal.string(r.spec.chart.chart)),
    #("version", cymbal.string(r.spec.chart.version)),
    #(
      "sourceRef",
      cymbal.block([
        #("kind", cymbal.string(r.spec.chart.source_ref.kind)),
        #("name", cymbal.string(r.spec.chart.source_ref.name)),
        #("namespace", cymbal.string(r.spec.chart.source_ref.namespace)),
      ]),
    ),
    #("interval", cymbal.string(r.spec.chart.interval)),
  ]

  let spec_fields = [
    #("interval", cymbal.string(r.spec.interval)),
    #("chart", cymbal.block([#("spec", cymbal.block(chart_fields))])),
  ]

  let spec_fields = case r.spec.values {
    option.Some(values) -> list.append(spec_fields, [#("values", values)])
    None -> spec_fields
  }

  cymbal.block([
    #("apiVersion", cymbal.string("helm.toolkit.fluxcd.io/v2")),
    #("kind", cymbal.string("HelmRelease")),
    #("metadata", k8s.object_meta_to_cymbal(r.metadata)),
    #("spec", cymbal.block(spec_fields)),
  ])
}

pub fn to_yaml(r: HelmRelease) -> String {
  cymbal.encode(to_cymbal(r))
}

pub fn new(
  name: String,
  chart: String,
  version: String,
  repo_name: String,
  repo_namespace: String,
) -> HelmRelease {
  HelmRelease(
    metadata: k8s.meta(name),
    spec: HelmReleaseSpec(
      interval: "5m",
      chart: ChartSpec(
        chart: chart,
        version: version,
        source_ref: SourceRef(
          kind: "HelmRepository",
          name: repo_name,
          namespace: repo_namespace,
        ),
        interval: "1m",
      ),
      values: None,
    ),
  )
}

pub fn with_values(r: HelmRelease, values: cymbal.Yaml) -> HelmRelease {
  HelmRelease(..r, spec: HelmReleaseSpec(..r.spec, values: option.Some(values)))
}

import cymbal
import gleam/option
import gleam/string
import glinfra/blueprint/app
import glinfra/k8s/helm_release
import glinfra/k8s/helm_repository.{type HelmRepository}

pub fn repo(url: String) -> HelmRepository {
  helm_repository.new(url_to_name(url), url)
}

pub fn release(
  repo: HelmRepository,
  name: String,
  chart: String,
  version: String,
  values: cymbal.Yaml,
) -> app.HelmApp {
  let release =
    helm_release.new(
      name,
      chart,
      version,
      repo.metadata.name,
      option.unwrap(repo.metadata.namespace, name),
    )
    |> helm_release.with_values(values)
  app.new_helm(name, release, repo)
}

fn url_to_name(url: String) -> String {
  url
  |> string.drop_start(8)
  // removed https://
  |> string.replace(".", "-")
  |> string.replace("/", "-")
}

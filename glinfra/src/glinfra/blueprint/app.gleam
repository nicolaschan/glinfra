import cymbal
import glinfra/blueprint/container.{type Container}
import glinfra/k8s/deployment
import glinfra/k8s/helm_release.{type HelmRelease}
import glinfra/k8s/helm_repository.{type HelmRepository}
import glinfra/k8s/ingress
import glinfra/k8s/service

pub type App {
  App(
    name: String,
    port: List(Port),
    containers: List(Container),
    plugins: List(AppPlugin),
  )
  HelmApp(
    name: String,
    helm_release: HelmRelease,
    helm_repository: HelmRepository,
    plugins: List(AppPlugin),
  )
}

pub fn new(name: String) -> App {
  App(name, [], [], [])
}

pub fn new_helm(
  name: String,
  helm_release: HelmRelease,
  helm_repository: HelmRepository,
) -> App {
  HelmApp(name, helm_release, helm_repository, [])
}

pub fn expose_http1(app: App, number: Int, host: String) -> App {
  let port = Port(number, False, [Ingress(host)])
  app |> expose(port)
}

pub fn expose_http2(app: App, number: Int, host: String) -> App {
  let port = Port(number, True, [Ingress(host)])
  app |> expose(port)
}

pub fn expose_tcp(app: App, number: Int) -> App {
  let port = Port(number, False, [])
  app |> expose(port)
}

pub fn expose(app: App, port: Port) -> App {
  let assert App(name, ports, containers, plugins) = app
  App(name, [port, ..ports], containers, plugins)
}

pub fn add_container(app: App, container: Container) -> App {
  let assert App(name, ports, containers, plugins) = app
  App(name, ports, [container, ..containers], plugins)
}

pub fn image(app: App, image_string: String) -> App {
  app |> add_container(container.new(image_string))
}

pub type Port {
  Port(number: Int, h2c: Bool, ingress: List(Ingress))
}

pub type Ingress {
  Ingress(host: String)
}

pub type AppPlugin {
  DeploymentPlugin(
    modify: fn(App, deployment.Deployment) -> deployment.Deployment,
  )
  IngressPlugin(modify: fn(App, ingress.Ingress) -> ingress.Ingress)
  ServicePlugin(modify: fn(App, service.Service) -> service.Service)
  ExtraResources(generate: fn(String, App) -> List(cymbal.Yaml))
}

pub fn add_plugin(app: App, plugin: AppPlugin) -> App {
  case app {
    App(name, ports, containers, plugins) ->
      App(name, ports, containers, [plugin, ..plugins])
    HelmApp(name, release, repo, plugins) ->
      HelmApp(name, release, repo, [plugin, ..plugins])
  }
}

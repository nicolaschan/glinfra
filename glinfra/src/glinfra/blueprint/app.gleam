import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/blueprint/container.{type Container}
import glinfra/blueprint/image.{type Image}
import glinfra/blueprint/storage.{type StorageRef}
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
    strategy: Option(deployment.Strategy),
  )
}

pub type HelmApp {
  HelmApp(
    name: String,
    helm_release: HelmRelease,
    helm_repository: HelmRepository,
    plugins: List(AppPlugin),
  )
}

pub type StackApp {
  ContainerApp(App)
  HelmChartApp(HelmApp)
}

pub fn new(name: String) -> App {
  App(name, [], [], [], None)
}

pub fn new_helm(
  name: String,
  helm_release: HelmRelease,
  helm_repository: HelmRepository,
) -> HelmApp {
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
  App(..app, port: [port, ..app.port])
}

pub fn add_container(app: App, container: Container) -> App {
  App(..app, containers: [container, ..app.containers])
}

pub fn image(app: App, image_string: String) -> App {
  app |> add_container(container.new(image_string))
}

pub fn add_image(app: App, img: Image) -> App {
  app |> add_container(container.image(img))
}

pub fn with_args(app: App, args: List(String)) -> App {
  let containers =
    list.map(app.containers, fn(c) { container.with_args(c, args) })
  App(..app, containers: containers)
}

pub type Port {
  Port(number: Int, h2c: Bool, ingress: List(Ingress))
}

pub type Ingress {
  Ingress(host: String)
}

pub type AppPlugin {
  DeploymentPlugin(
    modify: fn(StackApp, deployment.Deployment) -> deployment.Deployment,
  )
  IngressPlugin(modify: fn(StackApp, ingress.Ingress) -> ingress.Ingress)
  ServicePlugin(modify: fn(StackApp, service.Service) -> service.Service)
  ExtraResources(generate: fn(String, StackApp) -> List(cymbal.Yaml))
}

pub fn add_storage(app: App, mount_path: String, storage_ref: StorageRef) -> App {
  let containers =
    list.map(app.containers, fn(c) {
      container.add_storage(c, mount_path, storage_ref)
    })
  App(..app, containers: containers)
}

pub fn add_env(app: App, name: String, value: String) -> App {
  let containers =
    list.map(app.containers, fn(c) { container.add_env(c, name, value) })
  App(..app, containers: containers)
}

pub fn add_secret_volume(app: App, ref: container.SecretVolumeRef) -> App {
  let containers =
    list.map(app.containers, fn(c) { container.add_secret_volume(c, ref) })
  App(..app, containers: containers)
}

pub fn with_lifecycle(app: App, lifecycle: deployment.Lifecycle) -> App {
  let containers =
    list.map(app.containers, fn(c) { container.with_lifecycle(c, lifecycle) })
  App(..app, containers: containers)
}

pub fn with_strategy(app: App, strategy: deployment.Strategy) -> App {
  App(..app, strategy: Some(strategy))
}

pub fn add_plugin(app: App, plugin: AppPlugin) -> App {
  App(..app, plugins: [plugin, ..app.plugins])
}

pub fn add_helm_plugin(app: HelmApp, plugin: AppPlugin) -> HelmApp {
  HelmApp(..app, plugins: [plugin, ..app.plugins])
}

pub fn stack_app_name(app: StackApp) -> String {
  case app {
    ContainerApp(a) -> a.name
    HelmChartApp(a) -> a.name
  }
}

pub fn stack_app_plugins(app: StackApp) -> List(AppPlugin) {
  case app {
    ContainerApp(a) -> a.plugins
    HelmChartApp(a) -> a.plugins
  }
}

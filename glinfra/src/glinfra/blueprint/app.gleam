import cymbal
import glinfra/blueprint/container.{type Container}
import glinfra/k8s/deployment
import glinfra/k8s/ingress
import glinfra/k8s/service

pub type App {
  App(
    name: String,
    port: List(Port),
    containers: List(Container),
    plugins: List(AppPlugin),
  )
}

pub fn new(name: String) -> App {
  App(name, [], [], [])
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
  App(..app, plugins: [plugin, ..app.plugins])
}

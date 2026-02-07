import glinfra/blueprint/container.{type Container}

pub type App {
  App(name: String, port: List(Port), containers: List(Container))
}

pub fn new(name: String) -> App {
  App(name, [], [])
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

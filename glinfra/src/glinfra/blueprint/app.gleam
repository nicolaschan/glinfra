import glinfra/blueprint/image.{type Image}

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

pub fn expose(app: App, port: Port) -> App {
  App(..app, port: [port, ..app.port])
}

pub fn add_container(app: App, image: Image, args: List(String)) -> App {
  let container = Container(image, args)
  App(..app, containers: [container, ..app.containers])
}

pub type Port {
  Port(number: Int, h2c: Bool, ingress: List(Ingress))
}

pub type Ingress {
  Ingress(host: String)
}

pub type Container {
  Container(image: Image, args: List(String))
}

import glinfra/blueprint/app.{type App}

pub type Stack {
  Stack(name: String, apps: List(App))
}

pub fn new(name: String) -> Stack {
  Stack(name, [])
}

pub fn singleton(app: App) -> Stack {
  Stack(app.name, [app])
}

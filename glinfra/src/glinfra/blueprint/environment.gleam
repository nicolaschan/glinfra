import cymbal

pub type Environment {
  Environment(name: String, providers: List(Provider))
}

pub type Resource {
  Resource(name: String, render: fn(Environment) -> List(cymbal.Yaml))
}

pub type Provider {
  Provider(resources: List(Resource))
}

pub fn new(name: String) -> Environment {
  Environment(name: name, providers: [])
}

pub fn add_provider(env: Environment, provider: Provider) -> Environment {
  Environment(..env, providers: [provider, ..env.providers])
}

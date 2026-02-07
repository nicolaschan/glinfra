import cymbal

pub type Environment {
  Environment(name: String, providers: List(Provider))
}

pub type Provider {
  Provider(resources: List(#(String, fn(Environment) -> List(cymbal.Yaml))))
}

pub fn new(name: String) -> Environment {
  Environment(name: name, providers: [])
}

pub fn add_provider(env: Environment, provider: Provider) -> Environment {
  Environment(..env, providers: [provider, ..env.providers])
}

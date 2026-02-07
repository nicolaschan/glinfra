import cymbal
import gleam/option.{type Option, None, Some}
import glinfra/blueprint/app.{type App}

pub type Environment {
  Environment(
    name: String,
    update: Option(UpdateConfig),
    providers: List(Provider),
  )
}

pub type Provider {
  Provider(
    service_annotations: fn(App) -> List(#(String, String)),
    ingress_annotations: fn(App) -> List(#(String, String)),
    resources: List(#(String, fn(Environment) -> List(cymbal.Yaml))),
  )
}

pub type UpdateConfig {
  UpdateConfig(
    git_repo: String,
    git_repo_namespace: String,
    branch: String,
    author_name: String,
    author_email: String,
    path_prefix: String,
  )
}

pub fn new(name: String) -> Environment {
  Environment(name: name, update: None, providers: [])
}

pub fn with_update(env: Environment, config: UpdateConfig) -> Environment {
  Environment(..env, update: Some(config))
}

pub fn add_provider(env: Environment, provider: Provider) -> Environment {
  Environment(..env, providers: [provider, ..env.providers])
}

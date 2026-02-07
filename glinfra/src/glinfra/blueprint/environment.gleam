import gleam/option.{type Option, None, Some}
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/stack.{type Stack}

pub type Environment {
  Environment(
    name: String,
    stacks: List(Stack),
    update: Option(UpdateConfig),
    providers: List(AnnotationProvider),
  )
}

pub type AnnotationProvider {
  AnnotationProvider(
    service: fn(App) -> List(#(String, String)),
    ingress: fn(App) -> List(#(String, String)),
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
  Environment(name: name, stacks: [], update: None, providers: [])
}

pub fn add_stack(env: Environment, stack: Stack) -> Environment {
  Environment(..env, stacks: [stack, ..env.stacks])
}

pub fn with_update(env: Environment, config: UpdateConfig) -> Environment {
  Environment(..env, update: Some(config))
}

pub fn add_provider(
  env: Environment,
  provider: AnnotationProvider,
) -> Environment {
  Environment(..env, providers: [provider, ..env.providers])
}

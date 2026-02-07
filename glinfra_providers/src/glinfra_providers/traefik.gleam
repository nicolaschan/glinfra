import cymbal
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/environment.{type Environment, Provider}
import glinfra/compiler/stack.{StackPlugin}
import glinfra_providers/traefik/middleware.{type Middleware}

pub type TraefikConfig {
  TraefikConfig(
    entrypoints: List(String),
    global_middlewares: List(Middleware),
    extra_middlewares: List(Middleware),
  )
}

/// Convert a Traefik Middleware into an IngressMiddleware reference
/// that can be attached to a specific app's ingress.
pub fn ingress_middleware(mw: Middleware) -> app.IngressMiddleware {
  let ns = case mw.metadata.namespace {
    Some(namespace) -> namespace
    None -> "default"
  }
  app.IngressMiddleware(namespace: ns, name: mw.metadata.name)
}

pub fn stack_plugin(config: TraefikConfig) -> stack.StackPlugin {
  StackPlugin(
    service_annotations: service_annotations,
    ingress_annotations: ingress_annotations(config, _),
    extra_resources: fn(_, _) { [] },
  )
}

pub fn add(env: Environment, config: TraefikConfig) -> Environment {
  case resources(config) {
    [] -> env
    res -> environment.add_provider(env, Provider(resources: res))
  }
}

fn resources(
  config: TraefikConfig,
) -> List(#(String, fn(Environment) -> List(cymbal.Yaml))) {
  let all_middlewares =
    list.append(config.global_middlewares, config.extra_middlewares)
  case all_middlewares {
    [] -> []
    mws -> [
      #("traefik-middlewares", fn(_env) { list.map(mws, middleware.to_cymbal) }),
    ]
  }
}

fn service_annotations(application: App) -> List(#(String, String)) {
  case list.any(application.port, fn(p) { p.h2c }) {
    True -> [
      #("traefik.ingress.kubernetes.io/service.serversscheme", "h2c"),
    ]
    False -> []
  }
}

fn ingress_annotations(
  config: TraefikConfig,
  application: App,
) -> List(#(String, String)) {
  let annotations = case config.entrypoints {
    [] -> []
    eps -> [
      #(
        "traefik.ingress.kubernetes.io/router.entrypoints",
        string.join(eps, ","),
      ),
    ]
  }

  // Collect per-app middlewares from ingress definitions
  let per_app_refs =
    list.flat_map(application.port, fn(p) {
      list.flat_map(p.ingress, fn(ing) {
        list.map(ing.middlewares, ingress_middleware_ref)
      })
    })

  let all_refs =
    list.append(
      list.map(config.global_middlewares, middleware_ref),
      per_app_refs,
    )

  let annotations = case all_refs {
    [] -> annotations
    refs ->
      list.append(annotations, [
        #(
          "traefik.ingress.kubernetes.io/router.middlewares",
          string.join(refs, ","),
        ),
      ])
  }

  annotations
}

/// Derives the Traefik middleware annotation reference from a Middleware object.
/// Format: <namespace>-<name>@kubernetescrd
fn middleware_ref(mw: Middleware) -> String {
  let ns = case mw.metadata.namespace {
    Some(namespace) -> namespace
    None -> "default"
  }
  ns <> "-" <> mw.metadata.name <> "@kubernetescrd"
}

/// Derives the Traefik middleware annotation reference from an IngressMiddleware.
/// Format: <namespace>-<name>@kubernetescrd
fn ingress_middleware_ref(mw: app.IngressMiddleware) -> String {
  mw.namespace <> "-" <> mw.name <> "@kubernetescrd"
}

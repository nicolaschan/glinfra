import cymbal
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/environment.{type Environment, type Provider, Provider}
import glinfra_providers/traefik/middleware.{type Middleware}

pub type TraefikConfig {
  TraefikConfig(entrypoints: List(String), middlewares: List(Middleware))
}

pub fn provider(config: TraefikConfig) -> Provider {
  Provider(
    service_annotations: service_annotations,
    ingress_annotations: ingress_annotations(config, _),
    resources: resources(config),
  )
}

fn resources(
  config: TraefikConfig,
) -> List(#(String, fn(Environment) -> List(cymbal.Yaml))) {
  case config.middlewares {
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
  _application: App,
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

  let annotations = case config.middlewares {
    [] -> annotations
    mws ->
      list.append(annotations, [
        #(
          "traefik.ingress.kubernetes.io/router.middlewares",
          string.join(list.map(mws, middleware_ref), ","),
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

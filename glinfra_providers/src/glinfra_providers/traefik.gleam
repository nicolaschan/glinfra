import gleam/list
import gleam/string
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/environment.{
  type AnnotationProvider, AnnotationProvider,
}

pub type TraefikConfig {
  TraefikConfig(entrypoints: List(String), middlewares: List(String))
}

pub fn provider(config: TraefikConfig) -> AnnotationProvider {
  AnnotationProvider(service: service_annotations, ingress: ingress_annotations(
    config,
    _,
  ))
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
          string.join(mws, ","),
        ),
      ])
  }

  annotations
}

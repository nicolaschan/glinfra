import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glinfra/blueprint/app
import glinfra/blueprint/environment.{
  type Environment, type Resource, Provider, Resource,
}
import glinfra/k8s
import glinfra/k8s/ingress
import glinfra/k8s/service
import glinfra_providers/traefik/ingress_route_tcp
import glinfra_providers/traefik/middleware.{type Middleware}

pub type TraefikConfig {
  TraefikConfig(
    entrypoints: List(String),
    global_middlewares: List(Middleware),
    extra_middlewares: List(Middleware),
  )
}

/// Convert a Traefik Middleware into an IngressPlugin that appends
/// the middleware reference to the ingress's router.middlewares annotation.
pub fn ingress_middleware(mw: Middleware) -> app.AppPlugin {
  let ref = middleware_ref(mw)
  app.IngressPlugin(modify: fn(_app, ing) {
    let middlewares_key = "traefik.ingress.kubernetes.io/router.middlewares"
    let existing =
      list.find(ing.metadata.annotations, fn(a) { a.0 == middlewares_key })
    let new_value = case existing {
      Ok(#(_, value)) -> value <> "," <> ref
      Error(_) -> ref
    }
    let annotations =
      list.filter(ing.metadata.annotations, fn(a) { a.0 != middlewares_key })
    let annotations = list.append(annotations, [#(middlewares_key, new_value)])
    ingress.Ingress(
      ..ing,
      metadata: k8s.ObjectMeta(..ing.metadata, annotations: annotations),
    )
  })
}

pub fn plugins(config: TraefikConfig) -> List(app.AppPlugin) {
  [service_plugin(), ingress_plugin(config)]
}

pub fn add(env: Environment, config: TraefikConfig) -> Environment {
  case resources(config) {
    [] -> env
    res -> environment.add_provider(env, Provider(resources: res))
  }
}

fn resources(config: TraefikConfig) -> List(Resource) {
  let all_middlewares =
    list.append(config.global_middlewares, config.extra_middlewares)
  case all_middlewares {
    [] -> []
    mws -> [
      Resource(name: "traefik-middlewares", render: fn(_env) {
        list.map(mws, middleware.to_cymbal)
      }),
    ]
  }
}

fn service_plugin() -> app.AppPlugin {
  app.ServicePlugin(modify: fn(application, svc) {
    case application {
      app.ContainerApp(app.App(_name, port, _containers, _plugins, _strategy)) ->
        case list.any(port, fn(p) { p.h2c }) {
          True ->
            service.Service(
              ..svc,
              metadata: k8s.ObjectMeta(
                ..svc.metadata,
                annotations: list.append(svc.metadata.annotations, [
                  #(
                    "traefik.ingress.kubernetes.io/service.serversscheme",
                    "h2c",
                  ),
                ]),
              ),
            )
          False -> svc
        }
      app.HelmChartApp(_) -> svc
    }
  })
}

fn ingress_plugin(config: TraefikConfig) -> app.AppPlugin {
  let entrypoints_annotation = case config.entrypoints {
    [] -> []
    eps -> [
      #(
        "traefik.ingress.kubernetes.io/router.entrypoints",
        string.join(eps, ","),
      ),
    ]
  }

  let middlewares_annotation = case
    list.map(config.global_middlewares, middleware_ref)
  {
    [] -> []
    refs -> [
      #(
        "traefik.ingress.kubernetes.io/router.middlewares",
        string.join(refs, ","),
      ),
    ]
  }

  let annotations = list.append(entrypoints_annotation, middlewares_annotation)

  app.IngressPlugin(modify: fn(_app, ing) {
    ingress.Ingress(
      ..ing,
      metadata: k8s.ObjectMeta(
        ..ing.metadata,
        annotations: list.append(ing.metadata.annotations, annotations),
      ),
    )
  })
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

/// Returns an ExtraResources plugin that generates an IngressRouteTCP resource
/// for exposing a service over raw TCP via Traefik.
pub fn expose_tcp(
  entrypoint: String,
  service_name: String,
  port: Int,
) -> app.AppPlugin {
  app.ExtraResources(generate: fn(ns, _application) {
    let route =
      ingress_route_tcp.new(
        ns <> "-ingressroutetcp",
        [entrypoint],
        service_name,
        port,
      )
    let route =
      ingress_route_tcp.IngressRouteTCP(
        metadata: k8s.ObjectMeta(..route.metadata, namespace: Some(ns)),
        spec: route.spec,
      )
    [ingress_route_tcp.to_cymbal(route)]
  })
}

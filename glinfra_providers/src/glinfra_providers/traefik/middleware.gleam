import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type ObjectMeta}

/// A Traefik Middleware CRD resource (traefik.io/v1alpha1).
pub type Middleware {
  Middleware(metadata: ObjectMeta, spec: MiddlewareSpec)
}

/// Middleware spec variants matching Traefik's middleware types.
pub type MiddlewareSpec {
  Headers(
    custom_request_headers: List(#(String, String)),
    custom_response_headers: List(#(String, String)),
  )
  RedirectScheme(scheme: String, permanent: Bool)
  StripPrefix(prefixes: List(String))
  RateLimit(average: Int, burst: Int)
  BasicAuth(secret: String, realm: Option(String))
}

pub fn to_cymbal(m: Middleware) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("traefik.io/v1alpha1")),
    #("kind", cymbal.string("Middleware")),
    #("metadata", k8s.object_meta_to_cymbal(m.metadata)),
    #("spec", spec_to_cymbal(m.spec)),
  ])
}

pub fn to_yaml(m: Middleware) -> String {
  cymbal.encode(to_cymbal(m))
}

fn spec_to_cymbal(spec: MiddlewareSpec) -> cymbal.Yaml {
  case spec {
    Headers(request_headers, response_headers) ->
      cymbal.block([
        #("headers", headers_to_cymbal(request_headers, response_headers)),
      ])
    RedirectScheme(scheme, permanent) ->
      cymbal.block([
        #("redirectScheme", redirect_scheme_to_cymbal(scheme, permanent)),
      ])
    StripPrefix(prefixes) ->
      cymbal.block([#("stripPrefix", strip_prefix_to_cymbal(prefixes))])
    RateLimit(average, burst) ->
      cymbal.block([#("rateLimit", rate_limit_to_cymbal(average, burst))])
    BasicAuth(secret, realm) ->
      cymbal.block([#("basicAuth", basic_auth_to_cymbal(secret, realm))])
  }
}

fn headers_to_cymbal(
  request_headers: List(#(String, String)),
  response_headers: List(#(String, String)),
) -> cymbal.Yaml {
  let fields = case request_headers {
    [] -> []
    headers -> [
      #("customRequestHeaders", k8s.string_pairs_to_cymbal(headers)),
    ]
  }
  let fields = case response_headers {
    [] -> fields
    headers ->
      list.append(fields, [
        #("customResponseHeaders", k8s.string_pairs_to_cymbal(headers)),
      ])
  }
  cymbal.block(fields)
}

fn redirect_scheme_to_cymbal(scheme: String, permanent: Bool) -> cymbal.Yaml {
  cymbal.block([
    #("scheme", cymbal.string(scheme)),
    #("permanent", cymbal.bool(permanent)),
  ])
}

fn strip_prefix_to_cymbal(prefixes: List(String)) -> cymbal.Yaml {
  cymbal.block([
    #("prefixes", cymbal.array(list.map(prefixes, cymbal.string))),
  ])
}

fn rate_limit_to_cymbal(average: Int, burst: Int) -> cymbal.Yaml {
  cymbal.block([
    #("average", cymbal.int(average)),
    #("burst", cymbal.int(burst)),
  ])
}

fn basic_auth_to_cymbal(secret: String, realm: Option(String)) -> cymbal.Yaml {
  let fields = [#("secret", cymbal.string(secret))]
  let fields = case realm {
    Some(r) -> list.append(fields, [#("realm", cymbal.string(r))])
    None -> fields
  }
  cymbal.block(fields)
}

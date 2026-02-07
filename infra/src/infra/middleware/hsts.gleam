import glinfra/k8s
import glinfra_providers/traefik/middleware.{
  type Middleware, Headers, Middleware,
}

pub fn middleware() -> Middleware {
  Middleware(
    metadata: k8s.meta_ns("hsts-middleware", "default"),
    spec: Headers(custom_request_headers: [], custom_response_headers: [
      #("Strict-Transport-Security", "max-age=31536000"),
    ]),
  )
}

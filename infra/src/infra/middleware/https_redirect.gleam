import glinfra/k8s
import glinfra_providers/traefik/middleware.{
  type Middleware, Middleware, RedirectScheme,
}

pub fn middleware() -> Middleware {
  Middleware(
    metadata: k8s.meta_ns("https-redirect-middleware", "default"),
    spec: RedirectScheme(scheme: "https", permanent: True),
  )
}

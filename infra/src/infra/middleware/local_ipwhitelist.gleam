import glinfra/k8s
import glinfra_providers/traefik/middleware.{
  type Middleware, IpWhiteList, Middleware,
}

pub fn middleware() -> Middleware {
  Middleware(
    metadata: k8s.meta_ns("local-ipwhitelist", "default"),
    spec: IpWhiteList(source_range: [
      "172.30.0.0/16",
      "172.26.0.0/16",
    ]),
  )
}

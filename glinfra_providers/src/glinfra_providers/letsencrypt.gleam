import glinfra/blueprint/app.{type App}
import glinfra/blueprint/environment.{type Provider, Provider}

pub fn provider() -> Provider {
  Provider(
    service_annotations: fn(_) { [] },
    ingress_annotations: ingress_annotations,
    resources: [],
  )
}

fn ingress_annotations(_application: App) -> List(#(String, String)) {
  [
    #("cert-manager.io/cluster-issuer", "letsencrypt-prod"),
    #("cert-manager.io/private-key-algorithm", "ECDSA"),
  ]
}

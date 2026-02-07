import glinfra/blueprint/app.{type App}
import glinfra/blueprint/environment.{
  type AnnotationProvider, AnnotationProvider,
}

pub fn provider() -> AnnotationProvider {
  AnnotationProvider(service: fn(_) { [] }, ingress: ingress_annotations)
}

fn ingress_annotations(_application: App) -> List(#(String, String)) {
  [
    #("cert-manager.io/cluster-issuer", "letsencrypt-prod"),
    #("cert-manager.io/private-key-algorithm", "ECDSA"),
  ]
}

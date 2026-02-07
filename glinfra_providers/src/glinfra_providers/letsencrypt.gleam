import glinfra/blueprint/app.{type App}
import glinfra/compiler/stack.{StackPlugin}

pub fn stack_plugin() -> stack.StackPlugin {
  StackPlugin(
    service_annotations: fn(_) { [] },
    ingress_annotations: ingress_annotations,
    extra_resources: fn(_, _) { [] },
  )
}

fn ingress_annotations(_application: App) -> List(#(String, String)) {
  [
    #("cert-manager.io/cluster-issuer", "letsencrypt-prod"),
    #("cert-manager.io/private-key-algorithm", "ECDSA"),
  ]
}

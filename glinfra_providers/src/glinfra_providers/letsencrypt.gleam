import gleam/list
import glinfra/blueprint/app
import glinfra/blueprint/environment
import glinfra/compiler/stack
import glinfra/k8s
import glinfra/k8s/ingress

pub fn stack_plugin(
  issuers_resource: environment.Resource,
) -> stack.StackPlugin {
  stack.stack_plugin([ingress_plugin()], [issuers_resource])
}

fn ingress_plugin() -> app.AppPlugin {
  let annotations = [
    #("cert-manager.io/cluster-issuer", "letsencrypt-prod"),
    #("cert-manager.io/private-key-algorithm", "ECDSA"),
  ]

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

import cymbal
import glinfra/blueprint/helm
import glinfra/blueprint/stack.{type Stack}

pub fn stack() -> Stack {
  let helm_app =
    helm.repo("https://charts.jetstack.io")
    |> helm.release(
      "cert-manager",
      "cert-manager",
      "1.19.x",
      cert_manager_values(),
    )

  stack.new("cert-manager")
  |> stack.add_helm_app(helm_app)
}

fn cert_manager_values() -> cymbal.Yaml {
  cymbal.block([
    #("installCRDs", cymbal.bool(True)),
    #(
      "extraArgs",
      cymbal.array([cymbal.string("--enable-certificate-owner-ref=true")]),
    ),
  ])
}

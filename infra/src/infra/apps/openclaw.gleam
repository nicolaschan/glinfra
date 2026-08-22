import glinfra/blueprint/app
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage
import glinfra/k8s/deployment
import glinfra_providers/traefik
import infra/middleware/local_ipwhitelist

pub fn stack() -> Stack {
  let openclaw_storage = storage.new("openclaw-pvc", "16G")

  let openclaw =
    app.new("openclaw")
    |> app.expose_http1(18_789, "openclaw.app.zeromap.net")
    |> app.image("ghcr.io/openclaw/openclaw:latest")
    |> app.add_plugin(
      traefik.ingress_middleware(local_ipwhitelist.middleware()),
    )
    |> app.mount_pvc("/home/node/.openclaw", storage.ref(openclaw_storage))
    |> app.with_image_pull_policy(deployment.Always)

  stack.new("openclaw")
  |> stack.add_storage(openclaw_storage)
  |> stack.add_app(openclaw)
}

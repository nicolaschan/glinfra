import glinfra/blueprint/app
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage
import glinfra/k8s/deployment

pub fn stack() -> Stack {
  let openclaw_storage = storage.new("openclaw-pvc", "16G")

  let openclaw =
    app.new("openclaw")
    |> app.expose_http1(18_789, "openclaw.app.zeromap.net")
    |> app.image("ghcr.io/openclaw/openclaw:latest")
    |> app.add_storage("/home/node/.openclaw", storage.ref(openclaw_storage))
    |> app.with_image_pull_policy(deployment.Always)

  stack.new("openclaw")
  |> stack.add_storage(openclaw_storage)
  |> stack.add_app(openclaw)
}

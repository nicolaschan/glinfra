import glinfra/blueprint/app
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage
import glinfra/k8s/deployment
import glinfra_providers/traefik
import infra/middleware/local_ipwhitelist

pub fn stack() -> Stack {
  let paseo_home = storage.new("paseo-home", "16G")
  let paseo_workspace = storage.new("paseo-workspace", "16G")

  let paseo =
    app.new("paseo")
    |> app.expose_http1(6767, "paseo.app.zeromap.net")
    |> app.image("ghcr.io/getpaseo/paseo:latest")
    |> app.add_plugin(
      traefik.ingress_middleware(local_ipwhitelist.middleware()),
    )
    |> app.add_storage("/home/paseo", storage.ref(paseo_home))
    |> app.add_storage("/workspace", storage.ref(paseo_workspace))
    |> app.add_env_from_secret_name("paseo-secret")
    |> app.with_image_pull_policy(deployment.Always)

  stack.new("paseo")
  |> stack.add_storage(paseo_home)
  |> stack.add_app(paseo)
}

import glinfra/blueprint/app
import glinfra/blueprint/container
import glinfra/blueprint/stack.{type Stack}
import glinfra/k8s/deployment

pub fn stack() -> Stack {
  let cloudflare_ddns =
    app.new("cloudflare-ddns")
    |> app.with_strategy(deployment.Recreate)
    |> app.add_container(
      container.new("timothyjmiller/cloudflare-ddns:latest")
      |> container.add_env_from_secret(container.SecretEnvRef(
        "cloudflare-ddns-config",
      )),
    )

  stack.new("cloudflare-ddns")
  |> stack.add_app(cloudflare_ddns)
}

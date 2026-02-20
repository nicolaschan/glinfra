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
      |> container.add_env("PUID", "1000")
      |> container.add_env("PGID", "1000")
      |> container.add_secret_volume(container.secret_volume(
        "cloudflare-ddns-config",
        "/config",
      ))
      |> container.post_start_exec([
        "/bin/sh", "-c", "cp /config/config.json /config.json",
      ]),
    )

  stack.new("cloudflare-ddns")
  |> stack.add_app(cloudflare_ddns)
}

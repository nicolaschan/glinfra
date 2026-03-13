import glinfra/blueprint/app
import glinfra/blueprint/stack.{type Stack}
import glinfra/k8s/deployment

pub fn stack() -> Stack {
  app.new("cloudflare-ddns")
  |> app.with_strategy(deployment.Recreate)
  |> app.image("timothyjmiller/cloudflare-ddns:latest")
  |> app.add_env_from_secret_name("cloudflare-ddns-config")
  |> stack.singleton
}

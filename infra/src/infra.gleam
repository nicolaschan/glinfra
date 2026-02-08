import gleam/list
import glinfra/blueprint/environment
import glinfra/compile
import glinfra/compiler/stack
import glinfra_providers/flux_image_update.{FluxImageUpdateConfig}
import glinfra_providers/kustomize
import glinfra_providers/letsencrypt
import glinfra_providers/traefik.{TraefikConfig}
import infra/apps/baybridge
import infra/apps/market
import infra/apps/mines
import infra/apps/ollama
import infra/apps/x3dtictactoe
import infra/middleware/hsts
import infra/middleware/https_redirect
import infra/middleware/local_ipwhitelist

pub fn main() -> Nil {
  let traefik_config =
    TraefikConfig(
      entrypoints: ["web", "websecure"],
      global_middlewares: [
        hsts.middleware(),
        https_redirect.middleware(),
      ],
      extra_middlewares: [
        local_ipwhitelist.middleware(),
      ],
    )

  let flux_config =
    FluxImageUpdateConfig(
      git_repo: "nicolaschan-infra",
      git_repo_namespace: "default",
      branch: "master",
      author_name: "fluxcdbot",
      author_email: "fluxcdbot@nicolaschan.com",
      path_prefix: "./apps/monad",
    )

  let sc =
    letsencrypt.plugins()
    |> list.append(traefik.plugins(traefik_config))
    |> list.append(flux_image_update.plugins(flux_config))

  environment.new("monad")
  |> traefik.add(traefik_config)
  |> kustomize.add()
  |> stack.add(baybridge.stack(), sc)
  |> stack.add(x3dtictactoe.stack(), sc)
  |> stack.add(market.stack(), sc)
  |> stack.add(mines.stack(), sc)
  |> stack.add(ollama.stack(), sc)
  |> compile.manifest("manifests")
}

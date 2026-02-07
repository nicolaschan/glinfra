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
import infra/apps/x3dtictactoe
import infra/middleware/hsts
import infra/middleware/https_redirect

pub fn main() -> Nil {
  let traefik_config =
    TraefikConfig(entrypoints: ["web", "websecure"], middlewares: [
      hsts.middleware(),
      https_redirect.middleware(),
    ])

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
    stack.compiler([
      letsencrypt.stack_plugin(),
      traefik.stack_plugin(traefik_config),
      flux_image_update.stack_plugin(flux_config),
    ])

  environment.new("monad")
  |> traefik.add(traefik_config)
  |> kustomize.add()
  |> stack.add(baybridge.stack(), sc)
  |> stack.add(x3dtictactoe.stack(), sc)
  |> stack.add(market.stack(), sc)
  |> stack.add(mines.stack(), sc)
  |> compile.manifest("manifests")
}

import glinfra/blueprint/environment.{UpdateConfig}
import glinfra/compile
import glinfra_providers/letsencrypt
import glinfra_providers/traefik.{TraefikConfig}
import infra/apps/baybridge
import infra/apps/x3dtictactoe
import infra/middleware/hsts
import infra/middleware/https_redirect

pub fn main() -> Nil {
  let update_config =
    UpdateConfig(
      git_repo: "nicolaschan-infra",
      git_repo_namespace: "default",
      branch: "master",
      author_name: "fluxcdbot",
      author_email: "fluxcdbot@nicolaschan.com",
      path_prefix: "./apps/monad",
    )

  let traefik_provider =
    traefik.provider(
      TraefikConfig(entrypoints: ["web", "websecure"], middlewares: [
        hsts.middleware(),
        https_redirect.middleware(),
      ]),
    )

  environment.new("monad")
  |> environment.with_update(update_config)
  |> environment.add_provider(traefik_provider)
  |> environment.add_provider(letsencrypt.provider())
  |> environment.add_stack(baybridge.stack())
  |> environment.add_stack(x3dtictactoe.stack())
  |> compile.manifest("manifests")
}

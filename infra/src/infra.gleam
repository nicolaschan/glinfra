import gleam/list
import gleam/option.{None, Some}
import glinfra/blueprint/environment
import glinfra/compile.{VersionsConfig}
import glinfra/compiler/stack
import glinfra_providers/cert_manager
import glinfra_providers/flux_image_update.{FluxImageUpdateConfig}
import glinfra_providers/letsencrypt
import glinfra_providers/traefik.{TraefikConfig}
import infra/apps/baybridge
import infra/apps/bell
import infra/apps/cloudflare_ddns
import infra/apps/market
import infra/apps/minecraft
import infra/apps/mines
import infra/apps/ollama
import infra/apps/openclaw
import infra/apps/sunset_relay
import infra/apps/x3dtictactoe
import infra/middleware/hsts
import infra/middleware/https_redirect
import infra/middleware/local_ipwhitelist
import infra/providers/cert_manager as my_cert_manager

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
      path_prefix: "./manifests/monad",
    )

  let cert_manager_config = my_cert_manager.config()
  let issuers_resource = cert_manager.issuers_resource(cert_manager_config)

  let base_stacks =
    stack.stacks()
    |> stack.add_stack_plugin(letsencrypt.stack_plugin(issuers_resource))
    |> stack.add_stack_plugin(traefik.stack_plugin(traefik_config))
    |> stack.add_stack_plugin(flux_image_update.stack_plugin(flux_config))

  // Monad stacks as a list (needed for both building Stacks and collecting entries)
  let monad_app_stacks = [
    baybridge.stack(),
    x3dtictactoe.stack(),
    market.stack(),
    mines.stack(),
    ollama.stack(),
    minecraft.stack(),
    cloudflare_ddns.stack(),
    sunset_relay.stack(),
    openclaw.stack(),
  ]

  let monad_stacks =
    list.fold(monad_app_stacks, base_stacks, fn(s, app_stack) {
      stack.add(s, app_stack)
    })

  // Collect version entries from all monad stacks
  let monad_version_entries =
    list.flat_map(monad_app_stacks, flux_image_update.collect_version_entries)

  let monad_versions = case monad_version_entries {
    [] -> None
    entries ->
      Some(VersionsConfig(configmap_name: "image-versions", entries: entries))
  }

  let vps_stacks =
    base_stacks
    |> stack.add(bell.stack())

  environment.new("monad")
  |> cert_manager.add(my_cert_manager.config())
  |> traefik.add(traefik_config)
  |> stack.add_all(monad_stacks)
  |> compile.manifest("manifests/monad", "clusters/monad", monad_versions)

  environment.new("vps")
  |> cert_manager.add(my_cert_manager.config())
  |> traefik.add(traefik_config)
  |> stack.add_all(vps_stacks)
  |> compile.manifest("manifests/vps", "clusters/vps", None)
}

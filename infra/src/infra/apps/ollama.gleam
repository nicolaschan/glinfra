import glinfra/blueprint/app
import glinfra/blueprint/container
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage
import glinfra_providers/traefik
import infra/middleware/local_ipwhitelist

pub fn stack() -> Stack {
  let openwebui_storage = storage.new("openwebui-data", "1Gi")

  let openwebui =
    app.new("openwebui")
    |> app.expose_http1(8080, "openwebui.app.zeromap.net")
    |> app.add_ingress_middleware(
      "openwebui.app.zeromap.net",
      traefik.ingress_middleware(local_ipwhitelist.middleware()),
    )
    |> app.add_container(
      container.new("ghcr.io/open-webui/open-webui:main-slim")
      |> container.add_storage(
        "/app/backend/data",
        storage.ref(openwebui_storage),
      ),
    )

  stack.new("ollama")
  |> stack.add_storage(openwebui_storage)
  |> stack.add_app(openwebui)
}

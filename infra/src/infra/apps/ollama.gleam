import glinfra/blueprint/app
import glinfra/blueprint/container
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage
import glinfra_providers/nvidia
import glinfra_providers/traefik
import infra/middleware/local_ipwhitelist

pub fn stack() -> Stack {
  let openwebui_storage = storage.new("openwebui-pvc", "16G")
  let ollama_storage = storage.new("ollama-pvc", "16G")

  let ollama =
    app.new("ollama")
    |> app.expose_tcp(11_434)
    |> app.add_plugin(nvidia.plugin())
    |> app.add_container(
      container.new("ollama/ollama:0.12.10")
      |> container.add_storage("/root/.ollama", storage.ref(ollama_storage)),
    )

  let openwebui =
    app.new("openwebui")
    |> app.expose_http1(8080, "openwebui.app.zeromap.net")
    |> app.add_plugin(
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
  |> stack.add_storage(ollama_storage)
  |> stack.add_app(openwebui)
  |> stack.add_app(ollama)
}

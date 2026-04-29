import glinfra/blueprint/app
import glinfra/blueprint/image
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage

pub fn stack() -> Stack {
  let relay_storage = storage.new("relay-data", "1G")

  let relay_image =
    image.new("ghcr.io/nicolaschan/sunset-relay", "latest")
    |> image.with_update_pattern("^master-[0-9]+$")

  let relay_app =
    app.new("sunset-relay")
    |> app.expose_http2(8443, "relay.sunset.chat")
    |> app.expose_http1(8444, "id.relay.sunset.chat")
    |> app.add_image(relay_image)
    |> app.add_storage("/data", storage.ref(relay_storage))

  stack.new("sunset-relay")
  |> stack.add_storage(relay_storage)
  |> stack.add_app(relay_app)
}

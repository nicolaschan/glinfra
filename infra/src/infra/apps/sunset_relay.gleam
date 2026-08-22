import glinfra/blueprint/app
import glinfra/blueprint/image
import glinfra/blueprint/stack.{type Stack}

pub fn stack() -> Stack {
  let relay_image =
    image.new("ghcr.io/nicolaschan/sunset-relay", "latest")
    |> image.with_update_pattern("^master-[0-9]+$")

  let relay_app =
    app.new("sunset-relay")
    |> app.expose_http1(8443, "relay.sunset.chat")
    |> app.expose_http1(8444, "id.relay.sunset.chat")
    |> app.add_image(relay_image)

  stack.new("sunset-relay")
  |> stack.add_app(relay_app)
}

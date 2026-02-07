import glinfra/blueprint/app
import glinfra/blueprint/image
import glinfra/blueprint/stack.{type Stack}

pub fn stack() -> Stack {
  app.new("x3dtictactoe")
  |> app.expose_http1(9002, "3d.nicolaschan.com")
  |> app.add_container_image(image.new(
    "ghcr.io/nicolaschan/3dtictactoe",
    "v1.0.0",
  ))
  |> stack.singleton
}

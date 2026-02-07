import glinfra/blueprint/app
import glinfra/blueprint/stack.{type Stack}

pub fn stack() -> Stack {
  app.new("mines")
  |> app.expose_http1(8080, "mines.nicolaschan.com")
  |> app.image("ghcr.io/nicolaschan/mines:v1.0.5")
  |> stack.singleton
}

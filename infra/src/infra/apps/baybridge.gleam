import glinfra/blueprint/app
import glinfra/blueprint/image
import glinfra/blueprint/stack.{type Stack}

const version_file_path = "src/infra/apps/baybridge-version.yaml"

const args = [
  "serve",
  "--peer",
  "https://baybridge.neelay.net",
]

pub fn stack() -> Stack {
  let baybridge_image =
    image.from_version_file(version_file_path)
    |> image.with_update_pattern("^master-[0-9]+$")

  app.new("baybridge")
  |> app.expose_http2(3000, "baybridge.nicolaschan.com")
  |> app.add_image(baybridge_image)
  |> app.with_args(args)
  |> stack.singleton
}

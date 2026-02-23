import glinfra/blueprint/app
import glinfra/blueprint/image
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage

const version_file_path = "src/infra/apps/sunset-relay-version.yaml"

const args = ["--identity", "/data/identity.key"]

pub fn stack() -> Stack {
  let relay_storage = storage.new("relay-data", "1G")

  let relay_image =
    image.from_version_file(version_file_path)
    |> image.with_update_pattern("^master-[0-9]+$")

  let relay_app =
    app.new("sunset-relay")
    |> app.expose_http1(4001, "relay.sunset.chat")
    |> app.add_image(relay_image)
    |> app.with_args(args)
    |> app.add_storage("/data", storage.ref(relay_storage))

  stack.new("sunset-relay")
  |> stack.add_storage(relay_storage)
  |> stack.add_app(relay_app)
}

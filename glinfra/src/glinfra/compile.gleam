import cymbal
import gleam/io
import gleam/list
import gleam/string
import glinfra/blueprint/environment.{type Environment, Resource}
import simplifile

pub fn manifest(env: Environment, output_dir: String) {
  env
  |> env_to_cymbal
  |> write_manifests(output_dir)
}

fn write_manifests(
  manifests: List(#(String, List(cymbal.Yaml))),
  output_dir: String,
) {
  let _ = simplifile.create_directory_all(output_dir)

  let manifests = merge_manifests(manifests)

  list.each(manifests, fn(entry) {
    let #(name, yaml) = entry
    let yaml = list.map(yaml, cymbal.encode) |> string.join("")
    let path = output_dir <> "/" <> name <> ".yaml"
    io.println(yaml)
    case simplifile.write(to: path, contents: yaml) {
      Ok(Nil) -> io.print_error("Wrote " <> path)
      Error(_) -> io.print_error("Error: failed to write " <> path)
    }
  })
}

fn merge_manifests(
  manifests: List(#(String, List(cymbal.Yaml))),
) -> List(#(String, List(cymbal.Yaml))) {
  list.fold(manifests, [], fn(acc, entry) {
    let #(name, yamls) = entry
    case list.key_find(acc, name) {
      Ok(existing) -> list.key_set(acc, name, list.append(existing, yamls))
      Error(_) -> list.append(acc, [entry])
    }
  })
}

fn env_to_cymbal(env: Environment) -> List(#(String, List(cymbal.Yaml))) {
  list.flat_map(env.providers, fn(p) {
    list.map(p.resources, fn(entry) {
      let Resource(name, render) = entry
      #(name, render(env))
    })
  })
}

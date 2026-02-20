import cymbal
import gleam/list
import glinfra/blueprint/environment.{type Environment, Provider, Resource}

pub fn add(env: Environment) -> Environment {
  environment.add_provider(env, provider())
}

fn provider() -> environment.Provider {
  Provider(resources: [Resource(name: "kustomization", render: kustomization)])
}

fn kustomization(env: Environment) -> List(cymbal.Yaml) {
  let all_resources =
    list.flat_map(env.providers, fn(p) {
      list.map(p.resources, fn(entry) { entry.name <> ".yaml" })
    })
    |> list.filter(fn(name) { name != "kustomization.yaml" })

  [
    cymbal.block([
      #("apiVersion", cymbal.string("kustomize.config.k8s.io/v1beta1")),
      #("kind", cymbal.string("Kustomization")),
      #("resources", cymbal.array(list.map(all_resources, cymbal.string))),
    ]),
  ]
}

import cymbal
import gleam/list
import glinfra/blueprint/environment.{type Environment, type Provider, Provider}

pub fn provider() -> Provider {
  Provider(
    service_annotations: fn(_) { [] },
    ingress_annotations: fn(_) { [] },
    resources: [#("kustomization", kustomization)],
  )
}

fn kustomization(env: Environment) -> List(cymbal.Yaml) {
  let stack_names = list.map(env.stacks, fn(s) { s.name <> ".yaml" })

  let provider_names =
    list.flat_map(env.providers, fn(p) {
      list.map(p.resources, fn(entry) { entry.0 <> ".yaml" })
    })
    |> list.filter(fn(name) { name != "kustomization.yaml" })

  let all_resources = list.append(stack_names, provider_names)

  [
    cymbal.block([
      #("apiVersion", cymbal.string("kustomize.config.k8s.io/v1beta1")),
      #("kind", cymbal.string("Kustomization")),
      #("resources", cymbal.array(list.map(all_resources, cymbal.string))),
    ]),
  ]
}

import cymbal
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import glinfra/blueprint/environment.{type Environment}
import simplifile

/// A rendered resource with its name, direct dependency names, and YAML content
pub type RenderedResource {
  RenderedResource(
    name: String,
    dependency_names: List(String),
    yamls: List(cymbal.Yaml),
  )
}

/// A group of resources at the same topological level.
/// All resources in a group can be deployed in parallel.
pub type ResourceGroup {
  ResourceGroup(level: Int, resources: List(RenderedResource))
}

/// Compile an environment's manifests as flat YAML files under output_dir.
/// Each resource becomes a single file: output_dir/<name>.yaml.
/// Resources are topologically sorted into groups, and one FluxCD
/// Kustomization CRD is generated per group under cluster_dir.
/// Each group gets a _group-<name>/ directory with a kustomization.yaml
/// that references the flat resource files.
///
/// - output_dir: filesystem path where resource YAML files are written
///   (relative to the working directory, e.g. "manifests/vps")
/// - manifests_repo_path: repo-root-relative path used in the FluxCD
///   Kustomization spec.path field (e.g. "infra/manifests/vps")
/// - cluster_dir: filesystem path where FluxCD Kustomization CRDs are written
///   (e.g. "../clusters/vps" to reach the repo-root clusters/ dir)
pub fn manifest(
  env: Environment,
  output_dir: String,
  manifests_repo_path: String,
  cluster_dir: String,
) -> Nil {
  let resources =
    env
    |> env_to_rendered
    |> merge_resources

  // Filter out the kustomization resource (no longer needed)
  let resources = list.filter(resources, fn(r) { r.name != "kustomization" })

  // Write each resource as a flat YAML file
  write_resource_files(resources, output_dir)

  // Group resources by topological level
  let groups = topological_group(resources)

  // Write FluxCD Kustomization CRDs under the cluster dir (one per group)
  write_flux_kustomizations(groups, manifests_repo_path, cluster_dir, env.name)

  Nil
}

/// Write each resource as a flat YAML file: output_dir/<name>.yaml
fn write_resource_files(
  resources: List(RenderedResource),
  output_dir: String,
) -> Nil {
  let _ = simplifile.create_directory_all(output_dir)

  list.each(resources, fn(resource) {
    let yaml =
      list.map(resource.yamls, cymbal.encode)
      |> string.join("")
    let path = output_dir <> "/" <> resource.name <> ".yaml"
    io.println(yaml)
    case simplifile.write(to: path, contents: yaml) {
      Ok(Nil) -> io.print_error("Wrote " <> path)
      Error(_) -> io.print_error("Error: failed to write " <> path)
    }
  })
}

/// Perform topological sort and group resources by level.
/// Level 0 = no dependencies; level N = depends on something at level N-1.
/// Resources at the same level can be deployed in parallel.
fn topological_group(resources: List(RenderedResource)) -> List(ResourceGroup) {
  let all_names = list.map(resources, fn(r) { r.name })

  // Compute levels: a resource's level is 1 + max level of its dependencies.
  // Dependencies not in our resource set are ignored.
  let levels = compute_levels(resources, all_names)

  // Group by level, sorted ascending
  let max_level =
    list.fold(levels, 0, fn(acc, pair) {
      let #(_, level) = pair
      case level > acc {
        True -> level
        False -> acc
      }
    })

  // int.range is exclusive of `to`, so use max_level + 1 to include it
  int.range(from: 0, to: max_level + 1, with: [], run: fn(acc, level) {
    list.append(acc, [level])
  })
  |> list.filter_map(fn(level) {
    let group_resources =
      list.filter(resources, fn(r) {
        case list.find(levels, fn(pair) { pair.0 == r.name }) {
          Ok(#(_, l)) -> l == level
          Error(_) -> False
        }
      })
    case group_resources {
      [] -> Error(Nil)
      _ -> Ok(ResourceGroup(level: level, resources: group_resources))
    }
  })
}

/// Compute the topological level for each resource.
/// Returns a list of (name, level) pairs.
fn compute_levels(
  resources: List(RenderedResource),
  all_names: List(String),
) -> List(#(String, Int)) {
  // Simple iterative algorithm: start all at 0, then update until stable.
  let initial = list.map(resources, fn(r) { #(r.name, 0) })

  do_compute_levels(resources, all_names, initial, 0)
}

fn do_compute_levels(
  resources: List(RenderedResource),
  all_names: List(String),
  levels: List(#(String, Int)),
  iteration: Int,
) -> List(#(String, Int)) {
  // Safety bound: can't have more iterations than resources
  case iteration > list.length(resources) {
    True -> levels
    False -> {
      let new_levels =
        list.map(resources, fn(r) {
          // Only consider dependencies that are in our resource set
          let dep_levels =
            list.filter_map(r.dependency_names, fn(dep_name) {
              case list.contains(all_names, dep_name) {
                True ->
                  case list.find(levels, fn(pair) { pair.0 == dep_name }) {
                    Ok(#(_, l)) -> Ok(l)
                    Error(_) -> Error(Nil)
                  }
                False -> Error(Nil)
              }
            })
          let max_dep =
            list.fold(dep_levels, -1, fn(acc, l) {
              case l > acc {
                True -> l
                False -> acc
              }
            })
          #(r.name, max_dep + 1)
        })
      case new_levels == levels {
        True -> levels
        False ->
          do_compute_levels(resources, all_names, new_levels, iteration + 1)
      }
    }
  }
}

/// Write FluxCD Kustomization CRDs under cluster_dir, one per group.
/// Each group's Kustomization includes all resources at that level,
/// and dependsOn references the previous level's group.
fn write_flux_kustomizations(
  groups: List(ResourceGroup),
  manifests_repo_path: String,
  cluster_dir: String,
  env_name: String,
) -> Nil {
  let _ = simplifile.create_directory_all(cluster_dir)

  list.each(groups, fn(group) {
    let group_name = case group.level {
      0 -> env_name <> "-base"
      n -> env_name <> "-stage-" <> int.to_string(n)
    }
    let filename = group_name <> ".yaml"

    let resource_names = list.map(group.resources, fn(r) { r.name })

    // dependsOn: the previous level's group (if not level 0)
    let depends_on_block = case group.level {
      0 -> []
      _ -> {
        let prev_group_name = case group.level - 1 {
          0 -> env_name <> "-base"
          n -> env_name <> "-stage-" <> int.to_string(n)
        }
        [
          #(
            "dependsOn",
            cymbal.array([
              cymbal.block([
                #("name", cymbal.string(prev_group_name)),
              ]),
            ]),
          ),
        ]
      }
    }

    // Every stage gets a _group-* directory with a kustomization.yaml
    // that references the flat resource YAML files
    let flux_path = {
      let group_kustomization_dir =
        manifests_repo_path <> "/_group-" <> group_name
      let group_kustomization_fs_dir = repo_path_to_fs(group_kustomization_dir)
      let _ = simplifile.create_directory_all(group_kustomization_fs_dir)

      let kustomization_yaml =
        cymbal.encode(
          cymbal.block([
            #("apiVersion", cymbal.string("kustomize.config.k8s.io/v1beta1")),
            #("kind", cymbal.string("Kustomization")),
            #(
              "resources",
              cymbal.array(
                list.map(resource_names, fn(name) {
                  cymbal.string("../" <> name <> ".yaml")
                }),
              ),
            ),
          ]),
        )
      let kustomization_path =
        group_kustomization_fs_dir <> "/kustomization.yaml"
      case
        simplifile.write(to: kustomization_path, contents: kustomization_yaml)
      {
        Ok(Nil) -> io.print_error("Wrote " <> kustomization_path)
        Error(_) ->
          io.print_error("Error: failed to write " <> kustomization_path)
      }

      "./" <> group_kustomization_dir
    }

    let spec_fields =
      list.append(
        [
          #("interval", cymbal.string("1m0s")),
          #("path", cymbal.string(flux_path)),
          #("prune", cymbal.bool(True)),
          #(
            "sourceRef",
            cymbal.block([
              #("kind", cymbal.string("GitRepository")),
              #("name", cymbal.string("flux-system")),
            ]),
          ),
        ],
        depends_on_block,
      )

    let yaml =
      cymbal.encode(
        cymbal.block([
          #("apiVersion", cymbal.string("kustomize.toolkit.fluxcd.io/v1")),
          #("kind", cymbal.string("Kustomization")),
          #(
            "metadata",
            cymbal.block([
              #("name", cymbal.string(group_name)),
              #("namespace", cymbal.string("flux-system")),
            ]),
          ),
          #("spec", cymbal.block(spec_fields)),
        ]),
      )

    let path = cluster_dir <> "/" <> filename
    case simplifile.write(to: path, contents: yaml) {
      Ok(Nil) -> io.print_error("Wrote " <> path)
      Error(_) -> io.print_error("Error: failed to write " <> path)
    }
  })
}

/// Convert a repo-root-relative path to a filesystem path (from the infra/ cwd).
/// e.g. "infra/manifests/vps/_group-foo" -> "manifests/vps/_group-foo"
fn repo_path_to_fs(repo_path: String) -> String {
  case string.starts_with(repo_path, "infra/") {
    True -> string.drop_start(repo_path, 6)
    False -> repo_path
  }
}

fn merge_resources(resources: List(RenderedResource)) -> List(RenderedResource) {
  list.fold(resources, [], fn(acc: List(RenderedResource), resource) {
    case list.find(acc, fn(r) { r.name == resource.name }) {
      Ok(existing) -> {
        let merged =
          RenderedResource(
            name: resource.name,
            dependency_names: list.append(
              existing.dependency_names,
              resource.dependency_names,
            )
              |> list.unique,
            yamls: list.append(existing.yamls, resource.yamls),
          )
        list.map(acc, fn(r) {
          case r.name == resource.name {
            True -> merged
            False -> r
          }
        })
      }
      Error(_) -> list.append(acc, [resource])
    }
  })
}

fn env_to_rendered(env: Environment) -> List(RenderedResource) {
  let resources = list.flat_map(env.providers, fn(p) { p.resources })
  resolve_dependencies(resources)
  |> list.map(fn(entry: environment.Resource) {
    let dependency_names =
      list.map(entry.dependencies, fn(d: environment.Resource) { d.name })
      |> list.unique
    RenderedResource(
      name: entry.name,
      dependency_names: dependency_names,
      yamls: entry.render(env),
    )
  })
}

/// Recursively resolve all dependency Resources, prepending them
/// before the resources that depend on them.
/// Deduplicates by name (first occurrence wins).
fn resolve_dependencies(
  resources: List(environment.Resource),
) -> List(environment.Resource) {
  let all =
    list.flat_map(resources, fn(r) {
      list.append(resolve_dependencies(r.dependencies), [r])
    })
  dedup_resources(all)
}

fn dedup_resources(
  resources: List(environment.Resource),
) -> List(environment.Resource) {
  list.fold(resources, [], fn(acc, r: environment.Resource) {
    case
      list.any(acc, fn(existing: environment.Resource) {
        existing.name == r.name
      })
    {
      True -> acc
      False -> list.append(acc, [r])
    }
  })
}

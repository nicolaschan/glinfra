# ConfigMap + PostBuild Variable Substitution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple image version management from the Gleam compile pipeline by using FluxCD postBuild variable substitution with a generated ConfigMap, so image tag updates no longer require re-running Gleam.

**Architecture:** The Gleam code generator will emit `${VAR_NAME}` placeholders in Deployment image fields instead of hardcoded image refs. A versions ConfigMap (generated as raw YAML with `$imagepolicy` comments) holds the actual image references. FluxCD Kustomization CRDs reference this ConfigMap via `postBuild.substituteFrom`, injecting values at deploy time. FluxCD ImageUpdateAutomation updates the ConfigMap in git when new images are published.

**Tech Stack:** Gleam, cymbal (YAML builder), FluxCD (Kustomization, ImageUpdateAutomation, ImagePolicy), Kubernetes ConfigMap

---

## Key Design Decisions

1. **One variable per full image ref** -- e.g. `BAYBRIDGE_IMAGE: "ghcr.io/nicolaschan/baybridge:master-20296814492"`
2. **Gleam-generated versions ConfigMap** -- the code knows which apps use image automation; it generates the ConfigMap with `$imagepolicy` comments
3. **Raw string generation for ConfigMap** -- cymbal has no comment support, so the versions ConfigMap is generated as a raw string, not via cymbal. It's written as a separate file alongside the other manifests.
4. **Variable naming convention** -- `<UPPER_SNAKE_IMAGE_NAME>_IMAGE` derived from the image name (e.g. `ghcr.io/nicolaschan/baybridge` -> `GHCR_IO_NICOLASCHAN_BAYBRIDGE_IMAGE`)
5. **Churn prevention** -- When regenerating `versions.yaml`, the Gleam code reads the existing file first and preserves image refs that FluxCD ImageUpdateAutomation may have updated. The Gleam code only provides seed/fallback values for new entries. This prevents `gleam run` from reverting automation updates.

## File Structure

### Modified Files

| File | Responsibility |
|---|---|
| `glinfra/src/glinfra/blueprint/image.gleam` | Add `variable_name()` function to derive env var name from image; add `to_ref()` helper |
| `glinfra/src/glinfra/compiler/stack.gleam:300` | Change `c.image.name <> ":" <> c.image.tag` to emit `${VAR}` when image has update automation |
| `glinfra/src/glinfra/compile.gleam` | Add `write_versions_configmap()` function; add `postBuild.substituteFrom` to Flux Kustomization CRDs; accept versions configmap config |
| `glinfra_providers/src/glinfra_providers/flux_image_update.gleam` | Change `update.path` to use `path_prefix` directly (not `path_prefix/app_name`); add `collect_version_entries` function |
| `infra/src/infra.gleam` | Update `flux_config.path_prefix` to point at versions ConfigMap location; collect version entries; pass versions config to `compile.manifest` |
| `infra/src/infra/apps/baybridge.gleam` | Remove `from_version_file` -- use `image.new()` with update pattern instead |
| `infra/src/infra/apps/sunset_relay.gleam` | Same as baybridge |

### New Files

| File | Responsibility |
|---|---|
| `glinfra/src/glinfra/versions_configmap.gleam` | Generates the versions ConfigMap as raw YAML string with `$imagepolicy` inline comments |

### Files to Delete

| File | Reason |
|---|---|
| `infra/src/infra/apps/baybridge-version.yaml` | No longer needed -- version info moves to the generated ConfigMap |
| `infra/src/infra/apps/sunset-relay-version.yaml` | Same |

---

## Task 1: Add `variable_name` and `to_ref` functions to Image module

**Files:**
- Modify: `glinfra/src/glinfra/blueprint/image.gleam`

This derives an environment variable name from an image's name, used for both the ConfigMap key and the `${VAR}` placeholder in manifests.

- [ ] **Step 1: Add the `variable_name` function**

In `glinfra/src/glinfra/blueprint/image.gleam`, add:

```gleam
/// Derive a variable name from an image name for postBuild substitution.
/// e.g. "ghcr.io/nicolaschan/baybridge" -> "GHCR_IO_NICOLASCHAN_BAYBRIDGE_IMAGE"
pub fn variable_name(img: Image) -> String {
  img.name
  |> string.replace("/", "_")
  |> string.replace(".", "_")
  |> string.replace("-", "_")
  |> string.uppercase
  |> string.append("_IMAGE")
}
```

- [ ] **Step 2: Add `to_ref` helper function**

Also add a convenience function that returns the full image ref string:

```gleam
/// Return the full image reference string "name:tag"
pub fn to_ref(img: Image) -> String {
  img.name <> ":" <> img.tag
}
```

- [ ] **Step 3: Verify it compiles**

Run: `gleam build` (from `glinfra/` directory)
Expected: Compiles with no errors

- [ ] **Step 4: Commit**

```bash
git add glinfra/src/glinfra/blueprint/image.gleam
git commit -m "feat: add variable_name and to_ref helpers to Image module"
```

---

## Task 2: Create versions ConfigMap generator

**Files:**
- Create: `glinfra/src/glinfra/versions_configmap.gleam`

This module generates a ConfigMap YAML file as a raw string (not via cymbal) because cymbal doesn't support inline comments. The `$imagepolicy` comments are critical for FluxCD ImageUpdateAutomation to know which lines to update.

- [ ] **Step 1: Create the versions_configmap module**

Create `glinfra/src/glinfra/versions_configmap.gleam`:

```gleam
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import glinfra/blueprint/image.{type Image}
import simplifile

/// An entry in the versions ConfigMap: one image with its variable name,
/// current ref, and the $imagepolicy marker.
pub type VersionEntry {
  VersionEntry(
    /// The variable name (e.g. "GHCR_IO_NICOLASCHAN_BAYBRIDGE_IMAGE")
    variable: String,
    /// The full image ref (e.g. "ghcr.io/nicolaschan/baybridge:master-123")
    image_ref: String,
    /// The $imagepolicy value (e.g. "baybridge:ghcr-io-nicolaschan-baybridge")
    image_policy: String,
  )
}

/// Build a VersionEntry from an Image and its namespace.
pub fn entry_from_image(img: Image, namespace: String) -> VersionEntry {
  let slug = image_name_to_slug(img.name)
  VersionEntry(
    variable: image.variable_name(img),
    image_ref: image.to_ref(img),
    image_policy: namespace <> ":" <> slug,
  )
}

/// Generate the full ConfigMap YAML as a raw string with $imagepolicy comments.
/// The ConfigMap is placed in the flux-system namespace so it can be referenced
/// by Kustomization CRDs.
pub fn generate(name: String, entries: List(VersionEntry)) -> String {
  let data_lines =
    list.map(entries, fn(entry) {
      "  "
      <> entry.variable
      <> ": \""
      <> entry.image_ref
      <> "\""
      <> " # {\"$imagepolicy\": \""
      <> entry.image_policy
      <> "\"}"
    })
    |> string.join("\n")

  "---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: "
  <> name
  <> "\n  namespace: flux-system\ndata:\n"
  <> data_lines
  <> "\n"
}

/// Read an existing versions ConfigMap YAML file and extract variable->image_ref pairs.
/// Returns an empty list if the file doesn't exist or can't be parsed.
/// This is used to preserve image refs that FluxCD ImageUpdateAutomation has updated,
/// preventing `gleam run` from reverting automation updates.
pub fn read_existing(path: String) -> List(#(String, String)) {
  case simplifile.read(path) {
    Ok(contents) -> parse_data_lines(contents)
    Error(_) -> []
  }
}

/// Parse ConfigMap data lines to extract variable name -> image ref pairs.
/// Each data line looks like:
///   VAR_NAME: "image:tag" # {"$imagepolicy": "..."}
fn parse_data_lines(contents: String) -> List(#(String, String)) {
  contents
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    let trimmed = string.trim(line)
    // Look for lines matching pattern: KEY: "value" ...
    case string.split_once(trimmed, ": \"") {
      Ok(#(key, rest)) -> {
        // Extract the value before the closing quote
        case string.split_once(rest, "\"") {
          Ok(#(value, _)) -> Ok(#(string.trim(key), value))
          Error(_) -> Error(Nil)
        }
      }
      Error(_) -> Error(Nil)
    }
  })
}

/// Merge seed entries with existing values from a previously generated file.
/// For each entry, if an existing value is found for the same variable name,
/// use the existing image_ref (preserving automation updates). Otherwise use
/// the seed value from the Gleam code.
pub fn merge_with_existing(
  entries: List(VersionEntry),
  existing: List(#(String, String)),
) -> List(VersionEntry) {
  list.map(entries, fn(entry) {
    case list.find(existing, fn(pair) { pair.0 == entry.variable }) {
      Ok(#(_, existing_ref)) ->
        VersionEntry(..entry, image_ref: existing_ref)
      Error(_) -> entry
    }
  })
}

fn image_name_to_slug(name: String) -> String {
  name
  |> string.replace("/", "-")
  |> string.replace(".", "-")
}
```

- [ ] **Step 2: Verify it compiles**

Run: `gleam build` (from `glinfra/` directory)
Expected: Compiles with no errors

- [ ] **Step 3: Commit**

```bash
git add glinfra/src/glinfra/versions_configmap.gleam
git commit -m "feat: add versions ConfigMap generator with imagepolicy comments"
```

---

## Task 3: Collect auto-updated images from stacks

**Files:**
- Modify: `glinfra_providers/src/glinfra_providers/flux_image_update.gleam`

We need a way to collect all images that have update automation, so the versions ConfigMap can be populated. We also need to change the `update.path` to point at the directory containing the versions ConfigMap (not per-app subdirectories).

- [ ] **Step 1: Add `collect_version_entries` function**

Add to `flux_image_update.gleam`. **Important:** The existing `stack` import refers to `glinfra/compiler/stack` (which has `Stacks`, `StackPlugin`). The `Stack` type we need is from `glinfra/blueprint/stack`. Add a new aliased import:

```gleam
import glinfra/blueprint/stack as blueprint_stack
import glinfra/versions_configmap.{type VersionEntry}

/// Collect VersionEntry records from a stack's apps.
/// Returns entries for images that have update automation.
pub fn collect_version_entries(s: blueprint_stack.Stack) -> List(VersionEntry) {
  list.flat_map(s.apps, fn(application) {
    let ns = s.name
    case application {
      app.ContainerApp(app.App(_name, _port, containers, _plugins, _strategy)) ->
        containers
        |> list.filter_map(fn(c: container.Container) {
          case c.image.update {
            Some(_) -> Ok(versions_configmap.entry_from_image(c.image, ns))
            None -> Error(Nil)
          }
        })
      app.HelmChartApp(_) -> []
    }
  })
}
```

- [ ] **Step 2: Simplify `update.path` -- use `path_prefix` directly**

In `image_to_update_cymbal`, change line 68:

```gleam
// Before:
let update_path = config.path_prefix <> "/" <> app_name

// After:
let update_path = config.path_prefix
```

All ImageUpdateAutomation resources should point at the same directory -- the one containing the versions ConfigMap. FluxCD ImageUpdateAutomation scans all YAML files in the `update.path` directory for `$imagepolicy` markers.

- [ ] **Step 3: Verify it compiles**

Run: `gleam build` (from `glinfra_providers/` directory)
Expected: Compiles with no errors

- [ ] **Step 4: Commit**

```bash
git add glinfra_providers/src/glinfra_providers/flux_image_update.gleam
git commit -m "feat: collect version entries from stacks and unify update path"
```

---

## Task 4: Emit `${VAR}` placeholders in Deployment image fields

**Files:**
- Modify: `glinfra/src/glinfra/compiler/stack.gleam:300`

When a container's image has update automation (`image.update` is `Some`), the Deployment should use `${VAR_NAME}` instead of the hardcoded `name:tag`.

- [ ] **Step 1: Change image ref construction in `app_to_deployment`**

In `glinfra/src/glinfra/compiler/stack.gleam`, change line 300:

```gleam
// Before:
let image_ref = c.image.name <> ":" <> c.image.tag

// After:
import glinfra/blueprint/image
// (add this import at the top of the file)

let image_ref = case c.image.update {
  Some(_) -> "${" <> image.variable_name(c.image) <> "}"
  None -> c.image.name <> ":" <> c.image.tag
}
```

The `Some` / `None` imports from `gleam/option` are already available in this file.

- [ ] **Step 2: Verify it compiles**

Run: `gleam build` (from `glinfra/` directory)
Expected: Compiles with no errors

- [ ] **Step 3: Commit**

```bash
git add glinfra/src/glinfra/compiler/stack.gleam
git commit -m "feat: emit variable placeholders for auto-updated images in Deployments"
```

---

## Task 5: Add `postBuild.substituteFrom` and versions ConfigMap writing to compile

**Files:**
- Modify: `glinfra/src/glinfra/compile.gleam`

The compile module needs to:
1. Accept optional versions config
2. Write the versions ConfigMap YAML file
3. Add `postBuild.substituteFrom` to all Flux Kustomization CRDs
4. Include `versions.yaml` in the base group's kustomization resources

- [ ] **Step 1: Add `VersionsConfig` type and update `manifest` function signature**

```gleam
import gleam/option.{type Option}
import glinfra/versions_configmap.{type VersionEntry}

/// Configuration for version substitution via ConfigMap
pub type VersionsConfig {
  VersionsConfig(
    /// Name of the ConfigMap (e.g. "image-versions")
    configmap_name: String,
    /// List of version entries to include
    entries: List(VersionEntry),
  )
}
```

Update `manifest` signature:

```gleam
pub fn manifest(
  env: Environment,
  manifests_path: String,
  cluster_path: String,
  versions: Option(VersionsConfig),
) -> Nil {
```

- [ ] **Step 2: Write the versions ConfigMap file in `manifest` (with churn prevention)**

After `write_resource_files(...)`, add. **Important:** Read the existing file first and merge to preserve automation-updated image refs:

```gleam
case versions {
  option.Some(vc) -> {
    let configmap_path =
      repo_path_to_fs(manifests_path) <> "/versions.yaml"
    // Read existing file to preserve automation-updated image refs
    let existing = versions_configmap.read_existing(configmap_path)
    let merged_entries =
      versions_configmap.merge_with_existing(vc.entries, existing)
    let configmap_yaml =
      versions_configmap.generate(vc.configmap_name, merged_entries)
    case simplifile.write(to: configmap_path, contents: configmap_yaml) {
      Ok(Nil) -> io.print_error("Wrote " <> configmap_path)
      Error(_) ->
        io.print_error("Error: failed to write " <> configmap_path)
    }
  }
  option.None -> Nil
}
```

- [ ] **Step 3: Thread `versions` through to `write_flux_kustomizations`**

Update the `write_flux_kustomizations` call:

```gleam
write_flux_kustomizations(
  groups,
  manifests_path,
  repo_path_to_fs(cluster_path),
  env.name,
  versions,
)
```

Update `write_flux_kustomizations` signature:

```gleam
fn write_flux_kustomizations(
  groups: List(ResourceGroup),
  manifests_repo_path: String,
  cluster_dir: String,
  env_name: String,
  versions: Option(VersionsConfig),
) -> Nil {
```

- [ ] **Step 4: Add `postBuild.substituteFrom` to Flux Kustomization spec**

In `write_flux_kustomizations`, after the existing `spec_fields` construction (lines 256-271 of current `compile.gleam` -- the `list.append` that combines interval/path/prune/sourceRef with `depends_on_block`), append the postBuild block:

```gleam
let post_build_block = case versions {
  option.Some(vc) -> [
    #(
      "postBuild",
      cymbal.block([
        #(
          "substituteFrom",
          cymbal.array([
            cymbal.block([
              #("kind", cymbal.string("ConfigMap")),
              #("name", cymbal.string(vc.configmap_name)),
            ]),
          ]),
        ),
      ]),
    ),
  ]
  option.None -> []
}

let spec_fields = list.append(spec_fields, post_build_block)
```

- [ ] **Step 5: Add `versions.yaml` to base group kustomization resources**

In `write_flux_kustomizations`, inside the `list.each(groups, fn(group) { ... })` callback, find the `kustomization_yaml` construction (lines 229-242 of current `compile.gleam`). The existing `resources` field at line 234-240 builds a `cymbal.array` from `resource_names`. Modify this to also include `../versions.yaml` when versions config is present and it's the base group (level 0):

```gleam
let extra_resources = case versions, group.level {
  option.Some(_), 0 -> [cymbal.string("../versions.yaml")]
  _, _ -> []
}

// Replace the existing "resources" entry in the cymbal.block with:
#(
  "resources",
  cymbal.array(
    list.append(
      list.map(resource_names, fn(name) {
        cymbal.string("../" <> name <> ".yaml")
      }),
      extra_resources,
    ),
  ),
),
```

- [ ] **Step 6: Verify it compiles**

Run: `gleam build` (from `glinfra/` directory)
Expected: Compiles with no errors

- [ ] **Step 7: Commit**

```bash
git add glinfra/src/glinfra/compile.gleam
git commit -m "feat: generate versions ConfigMap and add postBuild substituteFrom to Flux Kustomizations"
```

---

## Task 6: Update infra app definitions and main entry point

**Files:**
- Modify: `infra/src/infra.gleam`
- Modify: `infra/src/infra/apps/baybridge.gleam`
- Modify: `infra/src/infra/apps/sunset_relay.gleam`
- Delete: `infra/src/infra/apps/baybridge-version.yaml`
- Delete: `infra/src/infra/apps/sunset-relay-version.yaml`

- [ ] **Step 1: Update baybridge.gleam**

Remove `from_version_file`, use `image.new` with update pattern:

```gleam
import glinfra/blueprint/app
import glinfra/blueprint/image
import glinfra/blueprint/stack.{type Stack}

const args = [
  "serve",
  "--peer",
  "https://baybridge.neelay.net",
]

pub fn stack() -> Stack {
  let baybridge_image =
    image.new("ghcr.io/nicolaschan/baybridge", "master-20296814492")
    |> image.with_update_pattern("^master-[0-9]+$")

  app.new("baybridge")
  |> app.expose_http2(3000, "baybridge.nicolaschan.com")
  |> app.add_image(baybridge_image)
  |> app.with_args(args)
  |> stack.singleton
}
```

The tag here (`"master-20296814492"`) seeds the ConfigMap initially. Once running, FluxCD updates the ConfigMap directly.

- [ ] **Step 2: Update sunset_relay.gleam**

Same pattern -- remove `from_version_file`:

```gleam
import glinfra/blueprint/app
import glinfra/blueprint/image
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage

const args = ["--identity", "/data/identity.key"]

pub fn stack() -> Stack {
  let relay_storage = storage.new("relay-data", "1G")

  let relay_image =
    image.new("ghcr.io/nicolaschan/sunset-relay", "latest")
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
```

- [ ] **Step 3: Update infra.gleam**

Major changes:
- Collect stacks as a list (for both building and entry collection)
- Collect version entries from all monad stacks
- Pass versions config to `compile.manifest`

```gleam
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/blueprint/environment
import glinfra/compile.{VersionsConfig}
import glinfra/compiler/stack
import glinfra_providers/cert_manager
import glinfra_providers/flux_image_update.{FluxImageUpdateConfig}
import glinfra_providers/letsencrypt
import glinfra_providers/traefik.{TraefikConfig}
import infra/apps/baybridge
import infra/apps/bell
import infra/apps/cloudflare_ddns
import infra/apps/market
import infra/apps/minecraft
import infra/apps/mines
import infra/apps/ollama
import infra/apps/sunset_relay
import infra/apps/x3dtictactoe
import infra/middleware/hsts
import infra/middleware/https_redirect
import infra/middleware/local_ipwhitelist
import infra/providers/cert_manager as my_cert_manager

pub fn main() -> Nil {
  let traefik_config =
    TraefikConfig(
      entrypoints: ["web", "websecure"],
      global_middlewares: [
        hsts.middleware(),
        https_redirect.middleware(),
      ],
      extra_middlewares: [
        local_ipwhitelist.middleware(),
      ],
    )

  let flux_config =
    FluxImageUpdateConfig(
      git_repo: "nicolaschan-infra",
      git_repo_namespace: "default",
      branch: "master",
      author_name: "fluxcdbot",
      author_email: "fluxcdbot@nicolaschan.com",
      path_prefix: "./manifests/monad",
    )

  let cert_manager_config = my_cert_manager.config()
  let issuers_resource = cert_manager.issuers_resource(cert_manager_config)

  let base_stacks =
    stack.stacks()
    |> stack.add_stack_plugin(letsencrypt.stack_plugin(issuers_resource))
    |> stack.add_stack_plugin(traefik.stack_plugin(traefik_config))
    |> stack.add_stack_plugin(flux_image_update.stack_plugin(flux_config))

  // Monad stacks as a list (needed for both building and entry collection)
  let monad_app_stacks = [
    baybridge.stack(),
    x3dtictactoe.stack(),
    market.stack(),
    mines.stack(),
    ollama.stack(),
    minecraft.stack(),
    cloudflare_ddns.stack(),
    sunset_relay.stack(),
  ]

  let monad_stacks =
    list.fold(monad_app_stacks, base_stacks, fn(s, app_stack) {
      stack.add(s, app_stack)
    })

  // Collect version entries from all monad stacks
  let monad_version_entries =
    list.flat_map(monad_app_stacks, flux_image_update.collect_version_entries)

  let monad_versions = case monad_version_entries {
    [] -> None
    entries -> Some(VersionsConfig(
      configmap_name: "image-versions",
      entries: entries,
    ))
  }

  let vps_stacks =
    base_stacks
    |> stack.add(bell.stack())

  environment.new("monad")
  |> cert_manager.add(my_cert_manager.config())
  |> traefik.add(traefik_config)
  |> stack.add_all(monad_stacks)
  |> compile.manifest("manifests/monad", "clusters/monad", monad_versions)

  environment.new("vps")
  |> cert_manager.add(my_cert_manager.config())
  |> traefik.add(traefik_config)
  |> stack.add_all(vps_stacks)
  |> compile.manifest("manifests/vps", "clusters/vps", None)
}
```

- [ ] **Step 4: Delete the version files**

```bash
rm infra/src/infra/apps/baybridge-version.yaml
rm infra/src/infra/apps/sunset-relay-version.yaml
```

- [ ] **Step 5: Verify it compiles and run**

Run: `gleam run` (from `infra/` directory)
Expected: Compiles and generates manifests successfully

- [ ] **Step 6: Verify generated output**

Check that:
1. `manifests/monad/versions.yaml` exists with ConfigMap + `$imagepolicy` comments
2. `manifests/monad/baybridge.yaml` has `${GHCR_IO_NICOLASCHAN_BAYBRIDGE_IMAGE}` in the Deployment image field
3. `manifests/monad/sunset-relay.yaml` has `${GHCR_IO_NICOLASCHAN_SUNSET_RELAY_IMAGE}` in the Deployment image field
4. `clusters/monad/monad-*.yaml` contain `postBuild.substituteFrom` referencing `image-versions`
5. `manifests/monad/_group-monad-base/kustomization.yaml` includes `../versions.yaml`
6. ImageUpdateAutomation in `baybridge.yaml` and `sunset-relay.yaml` have `update.path: "./manifests/monad"`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: switch to ConfigMap postBuild substitution for image versions

Image tags are now managed via a versions ConfigMap with FluxCD
postBuild variable substitution. Deployments use \${VAR} placeholders
instead of hardcoded image refs. ImageUpdateAutomation updates the
ConfigMap in git, eliminating the need to re-run Gleam on tag changes."
```

---

## Task 7: Cleanup -- remove unused `from_version_file`

**Files:**
- Modify: `glinfra/src/glinfra/blueprint/image.gleam`
- Possibly modify: `glinfra/gleam.toml` (remove `yay` dep)

- [ ] **Step 1: Check if `from_version_file` is still used**

```bash
rg "from_version_file" --type gleam
```

If nothing uses it, proceed with removal.

- [ ] **Step 2: Remove `from_version_file` from image.gleam**

Remove the function and the `simplifile` + `yay` imports if they become unused.

- [ ] **Step 3: Check if `yay` dependency can be removed**

```bash
rg "yay" glinfra/src/ --type gleam
```

If not used anywhere else in `glinfra/src/`, remove `yay` from `glinfra/gleam.toml` dependencies.

- [ ] **Step 4: Verify it compiles**

Run: `gleam build` (from `glinfra/` directory) and `gleam run` (from `infra/` directory)
Expected: Both succeed

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove unused from_version_file and yay dependency"
```

---

## Expected Final Output

### `manifests/monad/versions.yaml` (new, Gleam-generated)

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: image-versions
  namespace: flux-system
data:
  GHCR_IO_NICOLASCHAN_BAYBRIDGE_IMAGE: "ghcr.io/nicolaschan/baybridge:master-20296814492" # {"$imagepolicy": "baybridge:ghcr-io-nicolaschan-baybridge"}
  GHCR_IO_NICOLASCHAN_SUNSET_RELAY_IMAGE: "ghcr.io/nicolaschan/sunset-relay:latest" # {"$imagepolicy": "sunset-relay:ghcr-io-nicolaschan-sunset-relay"}
```

### `manifests/monad/baybridge.yaml` (Deployment excerpt)

```yaml
containers:
- image: "${GHCR_IO_NICOLASCHAN_BAYBRIDGE_IMAGE}"
```

### `clusters/monad/monad-stage-2.yaml` (excerpt)

```yaml
spec:
  postBuild:
    substituteFrom:
    - kind: ConfigMap
      name: image-versions
```

### ImageUpdateAutomation (in baybridge.yaml)

```yaml
update:
  path: "./manifests/monad"
```

## Lifecycle After Implementation

1. **New image pushed** -> FluxCD ImagePolicy detects new tag
2. **ImageUpdateAutomation** commits update to `manifests/monad/versions.yaml` in git
3. **FluxCD GitRepository** detects the commit
4. **FluxCD Kustomization** reconciles, reads the ConfigMap, substitutes `${VAR}` -> actual image ref via `postBuild`
5. **No Gleam re-run needed** -- only the ConfigMap data changes

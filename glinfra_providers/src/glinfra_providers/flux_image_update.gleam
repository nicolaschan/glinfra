import cymbal
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/image.{type Image}
import glinfra/k8s
import glinfra/k8s/image_policy
import glinfra/k8s/image_repository
import glinfra/k8s/image_update_automation

pub type FluxImageUpdateConfig {
  FluxImageUpdateConfig(
    git_repo: String,
    git_repo_namespace: String,
    branch: String,
    author_name: String,
    author_email: String,
    path_prefix: String,
  )
}

pub fn plugins(config: FluxImageUpdateConfig) -> List(app.AppPlugin) {
  [
    app.ExtraResources(generate: fn(ns, application) {
      app_to_image_update_cymbal(ns, application, config)
    }),
  ]
}

fn app_to_image_update_cymbal(
  ns: String,
  application: App,
  config: FluxImageUpdateConfig,
) -> List(cymbal.Yaml) {
  application.containers
  |> list.filter_map(fn(c) {
    case c.image.update {
      Some(_) -> Ok(c.image)
      None -> Error(Nil)
    }
  })
  |> list.flat_map(fn(img) {
    image_to_update_cymbal(ns, application.name, img, config)
  })
}

fn image_to_update_cymbal(
  ns: String,
  app_name: String,
  img: Image,
  config: FluxImageUpdateConfig,
) -> List(cymbal.Yaml) {
  let assert Some(update) = img.update
  let slug = image_name_to_slug(img.name)
  let repo_name = slug <> "-repo"
  let policy_name = slug
  let automation_name = slug <> "-update"
  let update_path = config.path_prefix <> "/" <> app_name

  let repo =
    image_repository.ImageRepository(
      metadata: k8s.ObjectMeta(
        name: repo_name,
        namespace: Some(ns),
        labels: [],
        annotations: [],
      ),
      spec: image_repository.ImageRepositorySpec(
        image: img.name,
        interval: "5m",
        secret_ref: None,
      ),
    )

  let policy =
    image_policy.ImagePolicy(
      metadata: k8s.ObjectMeta(
        name: policy_name,
        namespace: Some(ns),
        labels: [],
        annotations: [],
      ),
      spec: image_policy.ImagePolicySpec(
        image_repository_ref: repo_name,
        filter_tags: Some(image_policy.FilterTags(pattern: update.pattern)),
        policy: image_policy.Alphabetical(order: "asc"),
      ),
    )

  let automation =
    image_update_automation.ImageUpdateAutomation(
      metadata: k8s.ObjectMeta(
        name: automation_name,
        namespace: Some(ns),
        labels: [],
        annotations: [],
      ),
      spec: image_update_automation.ImageUpdateAutomationSpec(
        interval: "5m",
        source_ref: image_update_automation.SourceRef(
          kind: "GitRepository",
          name: config.git_repo,
          namespace: Some(config.git_repo_namespace),
        ),
        git: image_update_automation.GitSpec(
          commit: image_update_automation.GitCommit(
            author: image_update_automation.GitAuthor(
              name: config.author_name,
              email: config.author_email,
            ),
            message_template: "chore: update " <> app_name <> " image",
          ),
          push: image_update_automation.GitPush(branch: config.branch),
        ),
        update: image_update_automation.UpdateSpec(path: update_path),
      ),
    )

  [
    image_repository.to_cymbal(repo),
    image_policy.to_cymbal(policy),
    image_update_automation.to_cymbal(automation),
  ]
}

fn image_name_to_slug(name: String) -> String {
  name
  |> string.replace("/", "-")
  |> string.replace(".", "-")
}

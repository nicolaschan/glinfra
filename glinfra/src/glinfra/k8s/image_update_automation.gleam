import cymbal
import gleam/list
import gleam/option.{type Option, None, Some}
import glinfra/k8s.{type ObjectMeta}

pub type ImageUpdateAutomationSpec {
  ImageUpdateAutomationSpec(
    interval: String,
    source_ref: SourceRef,
    git: GitSpec,
    update: UpdateSpec,
  )
}

pub type SourceRef {
  SourceRef(kind: String, name: String, namespace: Option(String))
}

pub type GitSpec {
  GitSpec(commit: GitCommit, push: GitPush)
}

pub type GitCommit {
  GitCommit(author: GitAuthor, message_template: String)
}

pub type GitAuthor {
  GitAuthor(name: String, email: String)
}

pub type GitPush {
  GitPush(branch: String)
}

pub type UpdateSpec {
  UpdateSpec(path: String)
}

pub type ImageUpdateAutomation {
  ImageUpdateAutomation(metadata: ObjectMeta, spec: ImageUpdateAutomationSpec)
}

pub fn to_cymbal(a: ImageUpdateAutomation) -> cymbal.Yaml {
  let source_ref_fields = [
    #("kind", cymbal.string(a.spec.source_ref.kind)),
    #("name", cymbal.string(a.spec.source_ref.name)),
  ]

  let source_ref_fields = case a.spec.source_ref.namespace {
    Some(ns) ->
      list.append(source_ref_fields, [
        #("namespace", cymbal.string(ns)),
      ])
    None -> source_ref_fields
  }

  cymbal.block([
    #("apiVersion", cymbal.string("image.toolkit.fluxcd.io/v1")),
    #("kind", cymbal.string("ImageUpdateAutomation")),
    #("metadata", k8s.object_meta_to_cymbal(a.metadata)),
    #(
      "spec",
      cymbal.block([
        #("git", git_spec_to_cymbal(a.spec.git)),
        #("interval", cymbal.string(a.spec.interval)),
        #("sourceRef", cymbal.block(source_ref_fields)),
        #(
          "update",
          cymbal.block([#("path", cymbal.string(a.spec.update.path))]),
        ),
      ]),
    ),
  ])
}

pub fn to_yaml(a: ImageUpdateAutomation) -> String {
  cymbal.encode(to_cymbal(a))
}

fn git_spec_to_cymbal(g: GitSpec) -> cymbal.Yaml {
  cymbal.block([
    #(
      "commit",
      cymbal.block([
        #(
          "author",
          cymbal.block([
            #("email", cymbal.string(g.commit.author.email)),
            #("name", cymbal.string(g.commit.author.name)),
          ]),
        ),
        #("messageTemplate", cymbal.string(g.commit.message_template)),
      ]),
    ),
    #("push", cymbal.block([#("branch", cymbal.string(g.push.branch))])),
  ])
}

pub fn new(
  name name: String,
  git_repo git_repo: String,
  git_repo_namespace git_repo_namespace: String,
  branch branch: String,
  update_path update_path: String,
) -> ImageUpdateAutomation {
  ImageUpdateAutomation(
    metadata: k8s.meta(name),
    spec: ImageUpdateAutomationSpec(
      interval: "5m",
      source_ref: SourceRef(
        kind: "GitRepository",
        name: git_repo,
        namespace: Some(git_repo_namespace),
      ),
      git: GitSpec(
        commit: GitCommit(
          author: GitAuthor(
            name: "fluxcdbot",
            email: "fluxcdbot@nicolaschan.com",
          ),
          message_template: "",
        ),
        push: GitPush(branch: branch),
      ),
      update: UpdateSpec(path: update_path),
    ),
  )
}

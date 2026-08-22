import cymbal
import gleam/list
import gleam/string
import gleeunit/should.{equal, fail}
import glinfra/blueprint/app
import glinfra/blueprint/environment
import glinfra/blueprint/job
import glinfra/blueprint/stack
import glinfra/blueprint/storage
import glinfra/blueprint/volume
import glinfra/compiler/stack as compiler

pub fn host_path_volume_in_deployment_test() {
  let data = storage.new("data", "1G")
  let spindle =
    app.new("spindle")
    |> app.image("ghcr.io/nicolaschan/spindle:latest")
    |> app.mount_pvc("/data", storage.ref(data))
    |> app.mount_secret("/run/secrets/spindle", "spindle-secret")
    |> app.mount_host_path("/var/run/docker.sock", "/var/run/docker.sock")

  let yaml =
    stack.new("tangled")
    |> stack.add_storage(data)
    |> stack.add_app(spindle)
    |> rendered

  let expected = [
    "hostPath:",
    "path: \"/var/run/docker.sock\"",
    "readOnly: true",
    "name: docker-volume",
    "mountPath: \"/var/run/docker.sock\"",
    "persistentVolumeClaim:",
    "claimName: data",
    "name: data-volume",
    "mountPath: \"/data\"",
    "secret:",
    "secretName: spindle-secret",
    "name: spindle-secret-volume",
    "mountPath: \"/run/secrets/spindle\"",
  ]
  assert list.all(expected, fn(line) { has_line(yaml, line) })
}

pub fn pvc_mount_forces_recreate_strategy_test() {
  let data = storage.new("data", "1G")
  let yaml =
    stack.new("s1")
    |> stack.add_storage(data)
    |> stack.add_app(
      app.new("a")
      |> app.image("img")
      |> app.mount_pvc("/data", storage.ref(data)),
    )
    |> rendered

  case has_line(yaml, "type: Recreate") {
    True -> Nil
    False -> fail()
  }
}

pub fn non_pvc_mounts_do_not_force_strategy_test() {
  let yaml =
    stack.new("s2")
    |> stack.add_app(
      app.new("a")
      |> app.image("img")
      |> app.mount_host_path("/var/run/docker.sock", "/var/run/docker.sock"),
    )
    |> rendered

  case has_line(yaml, "strategy:") {
    True -> fail()
    False -> Nil
  }
}

pub fn host_path_volume_in_cronjob_test() {
  let lockfile = storage.new("lockfile", "5G")
  let backup =
    job.new("backup", "alpine/git", "* * * * *", ["/bin/sh"])
    |> job.mount_pvc("/mnt/lockfile", storage.ref(lockfile))
    |> job.mount_host_path("/var/run/docker.sock", "/var/run/docker.sock")
    |> job.mount_secret("/root/.ssh", "backup-secret")

  let yaml =
    stack.new("j1")
    |> stack.add_storage(lockfile)
    |> stack.add_job(backup)
    |> rendered

  let expected = [
    "hostPath:",
    "path: \"/var/run/docker.sock\"",
    "name: docker-volume",
    "mountPath: \"/var/run/docker.sock\"",
    "persistentVolumeClaim:",
    "claimName: lockfile",
    "name: lockfile-volume",
    "mountPath: \"/mnt/lockfile\"",
    "secret:",
    "secretName: backup-secret",
    "defaultMode: 256",
    "name: backup-secret-volume",
    "mountPath: \"/root/.ssh\"",
  ]
  assert list.all(expected, fn(line) { has_line(yaml, line) })
}

pub fn volume_name_is_derived_from_source_test() {
  equal(
    "docker-volume",
    volume.volume_name(volume.host_path("/m", "/var/run/docker.sock")),
  )
  equal(
    "sock-volume",
    volume.volume_name(volume.host_path("/m", "/var/run/sock")),
  )
  equal(
    "knot-secret-volume",
    volume.volume_name(volume.secret("/m", "knot-secret")),
  )
  equal("data-volume", volume.volume_name(volume.pvc("/m", "data", False)))
}

pub fn writable_toggles_read_only_test() {
  case volume.read_only(volume.secret("/m", "s")) {
    True -> Nil
    False -> fail()
  }
  case volume.read_only(volume.secret("/m", "s") |> volume.writable) {
    True -> fail()
    False -> Nil
  }
}

fn rendered(s: stack.Stack) -> String {
  let env = environment.new("test")
  compiler.stack_to_resource(s)
  |> fn(r) { r.render(env) }
  |> list.map(cymbal.encode)
  |> string.join("\n")
}

fn lines(s: String) -> List(String) {
  s
  |> string.split("\n")
  |> list.map(string.trim)
  |> list.map(fn(line) {
    case line {
      "- " <> rest -> rest
      _ -> line
    }
  })
}

fn has_line(yaml: String, expected: String) -> Bool {
  list.contains(lines(yaml), expected)
}

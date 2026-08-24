import gleam/list
import glinfra/blueprint/app
import glinfra/blueprint/job
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage
import glinfra/k8s/deployment

const bell_env = [
  #("WEBSERVER_PORT", "8080"),
  #("SERVER_NAME", "bell"),
  #(
    "STATS_REDIRECT",
    "https://stats.bell.plus/public/dashboard/49e7b501-3e1c-47f3-945e-83e727c359ba",
  ),
  #("ENABLE_WS_HITS", "false"),
  #("USE_H2", "true"),
]

pub fn stack() -> Stack {
  let schedule_storage = storage.new("schedules", "1G")

  let update_schedules =
    job.new("update-schedules", "alpine/git", "*/5 * * * *", [
      "/bin/sh",
      "-c",
      "rm -rf /schedules/lost+found; git clone https://github.com/nicolaschan/schedules.git /schedules || (cd /schedules; git pull origin master)",
    ])
    |> job.mount_pvc("/schedules", storage.ref(schedule_storage))

  let bell_app =
    app.new("bell")
    |> app.expose_http2(8080, "bell.plus")
    |> app.image("ghcr.io/nicolaschan/bell:v4.12.3")
    |> app.mount_pvc("/bell/schedules", storage.readonly_ref(schedule_storage))
    |> app.add_envs(bell_env)
    |> app.with_image_pull_policy(deployment.Always)
    |> with_disabled_postgres()

  stack.new("bell")
  |> stack.add_storage(schedule_storage)
  |> stack.add_app(bell_app)
  |> stack.add_job(update_schedules)
}

fn with_disabled_postgres(app: app.App) -> app.App {
  [
    "POSTGRES_ENABLED",
    "POSTGRES_HOST",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DATABASE",
    "POSTGRES_PORT",
  ]
  |> list.fold(app, fn(app, var) { app.add_env(app, var, "false") })
}

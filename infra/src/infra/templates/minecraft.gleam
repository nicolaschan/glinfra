import cymbal
import gleam/list
import glinfra/blueprint/app
import glinfra/blueprint/job
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage
import glinfra/k8s/helm_release
import glinfra/k8s/helm_repository
import glinfra_providers/traefik

pub type ServerConfig {
  ServerConfig(
    server_type: String,
    version: String,
    game_mode: String,
    difficulty: String,
    memory: String,
    rcon_password: String,
    view_distance: Int,
    pvp: Bool,
    enable_command_block: Bool,
  )
}

pub type Backup {
  Backup(
    name: String,
    schedule: String,
    sftp_repo: String,
    extra_flags: List(String),
  )
}

pub type Minecraft {
  Minecraft(
    name: String,
    config: ServerConfig,
    tcp_entrypoint: String,
    backups: List(Backup),
  )
}

const helm_repo_name = "itzg"

const helm_repo_url = "https://itzg.github.io/minecraft-server-charts/"

const helm_chart = "minecraft"

const helm_chart_version = "3.4.x"

const backup_image = "ghcr.io/nicolaschan/minecraft-backup:latest"

const tcp_port = 25_565

pub fn new(name: String, config: ServerConfig) -> Minecraft {
  Minecraft(name: name, config: config, tcp_entrypoint: "", backups: [])
}

pub fn expose_tcp(mc: Minecraft, entrypoint: String) -> Minecraft {
  Minecraft(..mc, tcp_entrypoint: entrypoint)
}

pub fn add_backup(mc: Minecraft, backup: Backup) -> Minecraft {
  Minecraft(..mc, backups: list.append(mc.backups, [backup]))
}

pub fn to_stack(mc: Minecraft) -> Stack {
  let name = mc.name
  let config = mc.config
  let backup_secret = name <> "-backup-secret"
  let lockfile_pvc_claim = name <> "-backup-lockfile-pvc"
  let server_pvc_claim = name <> "-minecraft-datadir"
  let rcon_service = name <> "-minecraft-rcon"
  let rcon_connection = rcon_service <> ":25575:" <> config.rcon_password
  let service_name = name <> "-minecraft"

  let lockfile_storage =
    storage.new(lockfile_pvc_claim, "5G")
    |> storage.with_default_storage_class()

  let lockfile_ref = storage.ref(lockfile_storage)

  let repo = helm_repository.new(helm_repo_name, helm_repo_url)
  let release =
    helm_release.new(name, helm_chart, helm_chart_version, helm_repo_name, name)
    |> helm_release.with_values(server_values(config))

  let minecraft_app =
    app.new_helm(name, release, repo)
    |> app.add_helm_plugin(traefik.expose_tcp(
      mc.tcp_entrypoint,
      service_name,
      tcp_port,
    ))

  let s =
    stack.new(name)
    |> stack.add_storage(lockfile_storage)
    |> stack.add_helm_app(minecraft_app)

  list.fold(mc.backups, s, fn(s, backup) {
    stack.add_job(
      s,
      backup_job(
        name,
        backup,
        rcon_connection,
        backup_secret,
        server_pvc_claim,
        lockfile_ref,
      ),
    )
  })
}

fn backup_job(
  server_name: String,
  backup: Backup,
  rcon_connection: String,
  backup_secret: String,
  server_pvc_claim: String,
  lockfile: storage.StorageRef,
) -> job.Job {
  let base_command = [
    "/code/backup.sh",
    "-c",
    "-p",
    backup.name,
    "-i",
    "/mnt/server",
    "-r",
    backup.sftp_repo,
    "-s",
    rcon_connection,
    "-w",
    "rcon",
    "-t",
    "/mnt/lockfile/lockfile",
    "-H",
    server_name <> "-backup-cronjob",
  ]
  let command = list.append(base_command, backup.extra_flags)

  job.new(
    server_name <> "-backup-" <> backup.name <> "-cronjob",
    backup_image,
    backup.schedule,
    command,
  )
  |> job.mount_pvc("/mnt/server", storage.external(server_pvc_claim))
  |> job.mount_pvc("/mnt/lockfile", lockfile)
  |> job.mount_secret("/root/.ssh", backup_secret)
  |> job.add_env(job.secret_env(
    "RESTIC_PASSWORD",
    backup_secret,
    "restic_password",
  ))
}

fn server_values(config: ServerConfig) -> cymbal.Yaml {
  cymbal.block([
    #(
      "minecraftServer",
      cymbal.block([
        #("type", cymbal.string(config.server_type)),
        #("version", cymbal.string(config.version)),
        #("gameMode", cymbal.string(config.game_mode)),
        #("eula", cymbal.bool(True)),
        #("difficulty", cymbal.string(config.difficulty)),
        #("viewDistance", cymbal.int(config.view_distance)),
        #("pvp", cymbal.bool(config.pvp)),
        #("enableCommandBlock", cymbal.bool(config.enable_command_block)),
        #("memory", cymbal.string(config.memory)),
        #("jvmOpts", cymbal.string("-Dlog4j2.formatMsgNoLookups=true")),
        #(
          "rcon",
          cymbal.block([
            #("enabled", cymbal.bool(True)),
            #("password", cymbal.string(config.rcon_password)),
          ]),
        ),
      ]),
    ),
    #(
      "persistence",
      cymbal.block([
        #("dataDir", cymbal.block([#("enabled", cymbal.bool(True))])),
      ]),
    ),
  ])
}

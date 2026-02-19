import glinfra/blueprint/stack.{type Stack}
import infra/templates/minecraft

const nicolas_backup = minecraft.Backup(
  name: "nicolas",
  schedule: "12 * * * *",
  sftp_repo: "sftp://git@monad.zeromap.net/minecraft-restic",
  extra_flags: [],
)

const randall_backup = minecraft.Backup(
  name: "randall",
  schedule: "39 2 * * *",
  sftp_repo: "sftp://nchan@frontyard.glaceon.org:62222/minecraft-restic",
  extra_flags: [],
)

const francis_backup = minecraft.Backup(
  name: "francis",
  schedule: "21 3 * * *",
  sftp_repo: "sftp://nc99@fnixon-externalsvc.endpoint.glaceon.org:55/harddrive2/backups/minecraft-restic",
  extra_flags: ["-d", "sequential", "-m", "-1"],
)

pub fn stack() -> Stack {
  minecraft.new(
    "minecraft",
    minecraft.ServerConfig(
      server_type: "VANILLA",
      version: "1.21.11",
      game_mode: "survival",
      difficulty: "hard",
      memory: "6G",
      rcon_password: "cdghkdtcouh8476e6qh22h",
      view_distance: 16,
      pvp: True,
      enable_command_block: False,
    ),
  )
  |> minecraft.expose_tcp("minecraft-tcp")
  |> minecraft.add_backup(nicolas_backup)
  |> minecraft.add_backup(randall_backup)
  |> minecraft.add_backup(francis_backup)
  |> minecraft.to_stack()
}

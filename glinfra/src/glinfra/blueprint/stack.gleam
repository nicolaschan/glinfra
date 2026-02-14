import gleam/list
import glinfra/blueprint/app.{type App}
import glinfra/blueprint/job.{type Job}
import glinfra/blueprint/storage.{type Storage}

pub type Stack {
  Stack(name: String, apps: List(App), storage: List(Storage), jobs: List(Job))
}

pub fn new(name: String) -> Stack {
  Stack(name, [], [], [])
}

pub fn singleton(app: App) -> Stack {
  new(app.name) |> add_app(app)
}

pub fn add_app(stack: Stack, app: App) -> Stack {
  Stack(..stack, apps: [app, ..stack.apps])
}

pub fn add_storage(stack: Stack, s: Storage) -> Stack {
  Stack(..stack, storage: [s, ..stack.storage])
}

pub fn add_job(stack: Stack, j: Job) -> Stack {
  Stack(..stack, jobs: list.append(stack.jobs, [j]))
}

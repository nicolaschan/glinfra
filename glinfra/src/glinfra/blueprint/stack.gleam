import gleam/list
import glinfra/blueprint/app.{type App, type HelmApp, type StackApp}
import glinfra/blueprint/job.{type Job}
import glinfra/blueprint/storage.{type Storage}

pub type Stack {
  Stack(
    name: String,
    apps: List(StackApp),
    storage: List(Storage),
    jobs: List(Job),
  )
}

pub fn new(name: String) -> Stack {
  Stack(name, [], [], [])
}

pub fn singleton(a: App) -> Stack {
  new(a.name) |> add_app(a)
}

pub fn add_app(stack: Stack, a: App) -> Stack {
  Stack(..stack, apps: [app.ContainerApp(a), ..stack.apps])
}

pub fn add_helm_app(stack: Stack, a: HelmApp) -> Stack {
  Stack(..stack, apps: [app.HelmChartApp(a), ..stack.apps])
}

pub fn add_storage(stack: Stack, s: Storage) -> Stack {
  Stack(..stack, storage: [s, ..stack.storage])
}

pub fn new_storage(
  stack: Stack,
  storage_name: String,
  size: String,
) -> #(Stack, Storage) {
  let storage = storage.new(storage_name, size)
  #(stack |> add_storage(storage), storage)
}

pub fn add_job(stack: Stack, j: Job) -> Stack {
  Stack(..stack, jobs: list.append(stack.jobs, [j]))
}

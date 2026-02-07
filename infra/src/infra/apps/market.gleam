import glinfra/blueprint/app.{type App}
import glinfra/blueprint/container
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage

pub fn stack() -> Stack {
  let mongo_storage = storage.new("mongo-pvc", "1G")

  stack.new("market")
  |> stack.add_storage(mongo_storage)
  |> stack.add_app(market_app())
  |> stack.add_app(mongo_app(storage.ref(mongo_storage)))
}

fn market_app() -> App {
  app.new("market")
  |> app.expose_http1(8080, "market.nc99.org")
  |> app.image("ghcr.io/nicolaschan/market:latest")
}

fn mongo_app(mongo_ref: storage.StorageRef) -> App {
  app.new("mongo")
  |> app.expose_tcp(27_017)
  |> app.add_container(
    container.new("mongo:6")
    |> container.add_storage("/data/db", mongo_ref),
  )
}

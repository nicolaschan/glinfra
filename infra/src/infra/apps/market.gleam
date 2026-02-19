import glinfra/blueprint/app
import glinfra/blueprint/stack.{type Stack}
import glinfra/blueprint/storage

pub fn stack() -> Stack {
  let mongo_storage = storage.new("mongo-pvc", "1G")

  let market_app =
    app.new("market")
    |> app.expose_http1(8080, "market.nc99.org")
    |> app.image("ghcr.io/nicolaschan/market:latest")
  let mongo_app =
    app.new("mongo")
    |> app.expose_tcp(27_017)
    |> app.image("mongo:6")
    |> app.add_storage("/data/db", storage.ref(mongo_storage))

  stack.new("market")
  |> stack.add_storage(mongo_storage)
  |> stack.add_app(market_app)
  |> stack.add_app(mongo_app)
}

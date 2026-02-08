import gleam/list
import gleam/option.{Some}
import glinfra/blueprint/app
import glinfra/k8s/deployment

pub fn plugin() -> app.AppPlugin {
  app.DeploymentPlugin(modify: fn(_application, dep) {
    let spec = dep.spec
    let template = spec.template

    let containers =
      list.map(template.containers, fn(c) {
        let gpu_resource = #("nvidia.com/gpu-all", "1")
        deployment.Container(
          ..c,
          resources: deployment.ResourceRequirements(
            limits: [gpu_resource, ..c.resources.limits],
            requests: [gpu_resource, ..c.resources.requests],
          ),
        )
      })

    deployment.Deployment(
      ..dep,
      spec: deployment.DeploymentSpec(
        ..spec,
        strategy: Some(deployment.Recreate),
        template: deployment.PodTemplateSpec(
          ..template,
          containers: containers,
          runtime_class_name: Some("nvidia"),
        ),
      ),
    )
  })
}

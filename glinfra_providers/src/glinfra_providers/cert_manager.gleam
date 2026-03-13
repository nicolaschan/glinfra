import cymbal
import gleam/list
import glinfra/blueprint/environment.{type Environment, Provider, Resource}
import glinfra/blueprint/stack.{type Stack}
import glinfra/compiler/stack as stack_compiler
import glinfra/k8s/certificate.{type Certificate}
import glinfra/k8s/cluster_issuer.{type ClusterIssuer}

pub type CertManagerConfig {
  CertManagerConfig(
    stack: Stack,
    issuers: List(ClusterIssuer),
    certificates: List(Certificate),
  )
}

pub fn config(stack: Stack) -> CertManagerConfig {
  CertManagerConfig(stack:, issuers: [], certificates: [])
}

pub fn add_issuer(
  c: CertManagerConfig,
  issuer: ClusterIssuer,
) -> CertManagerConfig {
  CertManagerConfig(..c, issuers: list.append(c.issuers, [issuer]))
}

pub fn add_certificate(
  c: CertManagerConfig,
  cert: Certificate,
) -> CertManagerConfig {
  CertManagerConfig(..c, certificates: list.append(c.certificates, [cert]))
}

/// Returns the cert-manager-issuers Resource (with cert-manager as a dependency).
/// This can be used by other plugins (e.g. letsencrypt) to declare a dependency
/// on the issuers being available.
pub fn issuers_resource(c: CertManagerConfig) -> environment.Resource {
  let cert_manager_resource = stack_compiler.stack_to_resource(c.stack)
  Resource(
    name: "cert-manager-issuers",
    dependencies: [cert_manager_resource],
    render: fn(_env) { to_cymbal(c) },
  )
}

pub fn add(env: Environment, c: CertManagerConfig) -> Environment {
  case c.issuers, c.certificates {
    [], [] -> env
    _, _ -> {
      let resource = issuers_resource(c)
      environment.add_provider(env, Provider(resources: [resource]))
    }
  }
}

fn to_cymbal(c: CertManagerConfig) -> List(cymbal.Yaml) {
  let issuer_docs = list.map(c.issuers, cluster_issuer.to_cymbal)
  let cert_docs = list.map(c.certificates, certificate.to_cymbal)
  list.append(issuer_docs, cert_docs)
}

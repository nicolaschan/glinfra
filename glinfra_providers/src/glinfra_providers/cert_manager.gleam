import cymbal
import gleam/list
import glinfra/blueprint/environment.{type Environment, Provider}
import glinfra/k8s/certificate.{type Certificate}
import glinfra/k8s/cluster_issuer.{type ClusterIssuer}

pub type CertManagerConfig {
  CertManagerConfig(
    issuers: List(ClusterIssuer),
    certificates: List(Certificate),
  )
}

pub fn config() -> CertManagerConfig {
  CertManagerConfig(issuers: [], certificates: [])
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

pub fn add(env: Environment, c: CertManagerConfig) -> Environment {
  let resources = case c.issuers, c.certificates {
    [], [] -> []
    _, _ -> [#("cert-manager-issuers", fn(_env) { to_cymbal(c) })]
  }
  case resources {
    [] -> env
    res -> environment.add_provider(env, Provider(resources: res))
  }
}

fn to_cymbal(c: CertManagerConfig) -> List(cymbal.Yaml) {
  let issuer_docs = list.map(c.issuers, cluster_issuer.to_cymbal)
  let cert_docs = list.map(c.certificates, certificate.to_cymbal)
  list.append(issuer_docs, cert_docs)
}

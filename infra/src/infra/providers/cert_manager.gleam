import glinfra/k8s/certificate
import glinfra/k8s/cluster_issuer
import glinfra_providers/cert_manager

pub fn config() -> cert_manager.CertManagerConfig {
  cert_manager.config()
  |> cert_manager.add_issuer(cluster_issuer.new_acme(
    "letsencrypt-staging",
    "default",
    "letsencrypt@nicolaschan.com",
    "https://acme-staging-v02.api.letsencrypt.org/directory",
    "letsencrypt-staging-account-key",
  ))
  |> cert_manager.add_issuer(cluster_issuer.new_acme(
    "letsencrypt-prod",
    "cert-manager",
    "letsencrypt@nicolaschan.com",
    "https://acme-v02.api.letsencrypt.org/directory",
    "letsencrypt-prod-account-key",
  ))
  |> cert_manager.add_issuer(cluster_issuer.new_self_signed(
    "selfsigned-issuer",
    "default",
  ))
  |> cert_manager.add_issuer(cluster_issuer.new_ca(
    "selfsigned-ca-issuer",
    "default",
    "root-secret",
  ))
  |> cert_manager.add_certificate(certificate.new(
    "selfsigned-ca",
    "default",
    "intranet.lol Pi Cluster",
    "root-secret",
    "selfsigned-issuer",
  ))
}

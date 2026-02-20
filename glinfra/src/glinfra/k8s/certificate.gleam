import cymbal
import glinfra/k8s.{type ObjectMeta}

pub type Certificate {
  Certificate(metadata: ObjectMeta, spec: CertificateSpec)
}

pub type CertificateSpec {
  CertificateSpec(
    is_ca: Bool,
    common_name: String,
    secret_name: String,
    private_key: PrivateKey,
    issuer_ref: IssuerRef,
  )
}

pub type PrivateKey {
  PrivateKey(algorithm: String, size: Int)
}

pub type IssuerRef {
  IssuerRef(name: String, kind: String, group: String)
}

pub fn to_cymbal(r: Certificate) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("cert-manager.io/v1")),
    #("kind", cymbal.string("Certificate")),
    #("metadata", k8s.object_meta_to_cymbal(r.metadata)),
    #(
      "spec",
      cymbal.block([
        #("isCA", cymbal.bool(r.spec.is_ca)),
        #("commonName", cymbal.string(r.spec.common_name)),
        #("secretName", cymbal.string(r.spec.secret_name)),
        #(
          "privateKey",
          cymbal.block([
            #("algorithm", cymbal.string(r.spec.private_key.algorithm)),
            #("size", cymbal.int(r.spec.private_key.size)),
          ]),
        ),
        #(
          "issuerRef",
          cymbal.block([
            #("name", cymbal.string(r.spec.issuer_ref.name)),
            #("kind", cymbal.string(r.spec.issuer_ref.kind)),
            #("group", cymbal.string(r.spec.issuer_ref.group)),
          ]),
        ),
      ]),
    ),
  ])
}

pub fn new(
  name: String,
  namespace: String,
  common_name: String,
  secret_name: String,
  issuer_name: String,
) -> Certificate {
  Certificate(
    metadata: k8s.meta_ns(name, namespace),
    spec: CertificateSpec(
      is_ca: True,
      common_name: common_name,
      secret_name: secret_name,
      private_key: PrivateKey(algorithm: "ECDSA", size: 256),
      issuer_ref: IssuerRef(
        name: issuer_name,
        kind: "ClusterIssuer",
        group: "cert-manager.io",
      ),
    ),
  )
}

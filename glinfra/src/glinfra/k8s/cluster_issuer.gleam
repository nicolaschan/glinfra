import cymbal
import gleam/list
import glinfra/k8s.{type ObjectMeta}

pub type ClusterIssuer {
  ClusterIssuer(metadata: ObjectMeta, spec: ClusterIssuerSpec)
}

pub type ClusterIssuerSpec {
  AcmeIssuer(acme: AcmeSpec)
  SelfSignedIssuer
  CaIssuer(secret_name: String)
}

pub type AcmeSpec {
  AcmeSpec(
    email: String,
    profile: String,
    server: String,
    private_key_secret_ref: String,
    solvers: List(AcmeSolver),
  )
}

pub type AcmeSolver {
  Http01IngressSolver(service_type: String)
}

pub fn to_cymbal(r: ClusterIssuer) -> cymbal.Yaml {
  cymbal.block([
    #("apiVersion", cymbal.string("cert-manager.io/v1")),
    #("kind", cymbal.string("ClusterIssuer")),
    #("metadata", k8s.object_meta_to_cymbal(r.metadata)),
    #("spec", spec_to_cymbal(r.spec)),
  ])
}

fn spec_to_cymbal(spec: ClusterIssuerSpec) -> cymbal.Yaml {
  case spec {
    AcmeIssuer(acme) -> cymbal.block([#("acme", acme_to_cymbal(acme))])
    SelfSignedIssuer -> cymbal.block([#("selfSigned", cymbal.block([]))])
    CaIssuer(secret_name) ->
      cymbal.block([
        #("ca", cymbal.block([#("secretName", cymbal.string(secret_name))])),
      ])
  }
}

fn acme_to_cymbal(acme: AcmeSpec) -> cymbal.Yaml {
  let solvers = list.map(acme.solvers, solver_to_cymbal)

  cymbal.block([
    #("email", cymbal.string(acme.email)),
    #("profile", cymbal.string(acme.profile)),
    #("server", cymbal.string(acme.server)),
    #(
      "privateKeySecretRef",
      cymbal.block([#("name", cymbal.string(acme.private_key_secret_ref))]),
    ),
    #("solvers", cymbal.array(solvers)),
  ])
}

fn solver_to_cymbal(solver: AcmeSolver) -> cymbal.Yaml {
  case solver {
    Http01IngressSolver(service_type) ->
      cymbal.block([
        #(
          "http01",
          cymbal.block([
            #(
              "ingress",
              cymbal.block([
                #("serviceType", cymbal.string(service_type)),
              ]),
            ),
          ]),
        ),
      ])
  }
}

pub fn new_acme(
  name: String,
  namespace: String,
  email: String,
  server: String,
  private_key_secret_name: String,
) -> ClusterIssuer {
  ClusterIssuer(
    metadata: k8s.meta_ns(name, namespace),
    spec: AcmeIssuer(
      AcmeSpec(
        email: email,
        profile: "shortlived",
        server: server,
        private_key_secret_ref: private_key_secret_name,
        solvers: [Http01IngressSolver("ClusterIP")],
      ),
    ),
  )
}

pub fn new_self_signed(name: String, namespace: String) -> ClusterIssuer {
  ClusterIssuer(metadata: k8s.meta_ns(name, namespace), spec: SelfSignedIssuer)
}

pub fn new_ca(
  name: String,
  namespace: String,
  secret_name: String,
) -> ClusterIssuer {
  ClusterIssuer(
    metadata: k8s.meta_ns(name, namespace),
    spec: CaIssuer(secret_name),
  )
}

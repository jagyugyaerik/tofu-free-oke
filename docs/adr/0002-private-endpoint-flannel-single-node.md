# Private K8s API endpoint, flannel CNI, single A1 node

The OKE cluster uses a private Kubernetes API endpoint (reached by humans through the managed OCI Bastion service), the flannel overlay CNI, and a single `VM.Standard.A1.Flex` worker at 2 OCPU / 12 GB. Endpoint visibility and CNI are both fixed at cluster creation in OKE — changing either later requires destroying and recreating the cluster, so they are recorded here.

## Considered Options

- **Public endpoint** — simpler (no Bastion), pipeline-irrelevant since provisioning hits the public OCI management API regardless; rejected to keep the cluster isolated.
- **VCN-native CNI** — pods get real VCN IPs but max pods/node is bound by VNIC/secondary-IP count; too constraining on a 2-OCPU node.
- **Two 1-OCPU nodes for worker HA** — rejected because Oracle halved the Always-Free A1 allotment to 2 OCPU / 12 GB total on 2026-06-15, making two nodes painfully small (~6 GB each). One fat node maximizes usable headroom; the control plane is managed/HA regardless.

## Consequences

- No worker-level HA; node-pool can be scaled later (reversible), but the endpoint/CNI choices cannot without recreation.
- Provisioning via the pipeline never needs the private endpoint (it uses the OCI management API); only human kubectl does, via Bastion.

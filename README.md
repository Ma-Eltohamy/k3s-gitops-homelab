# k3s-homelab-gitops

Declarative configuration for a single-node **k3s** homelab: every workload defined here,
applied from here. Currently mid-migration from hand-applied manifests to **Argo CD**.

![k3s](https://img.shields.io/badge/k3s-FFC61C?logo=k3s&logoColor=black)
![Kubernetes](https://img.shields.io/badge/kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Traefik](https://img.shields.io/badge/ingress-Traefik-24A1C1?logo=traefikproxy&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo%20CD-planned-EF7B4D?logo=argo&logoColor=white)
![GitOps](https://img.shields.io/badge/GitOps-0D1117?logo=git&logoColor=white)

---

## Overview

A personal cluster run as a proving ground for production practice: everything is version
controlled, every non-obvious choice is written down in [`docs/decisions.md`](docs/decisions.md),
and changes reach the cluster through this repository rather than by hand.

It is deliberately **single-node**. The interesting constraints here are not scale; they are
adopting a running cluster into GitOps without downtime, keeping secrets out of Git, and
staying honest about what is actually deployed versus merely aspirational.

## Platform

| Layer | Choice |
| --- | --- |
| **Distribution** | k3s, single node control-plane and workloads on the same machine |
| **Ingress** | Traefik, as bundled with k3s and managed by its helm-controller |
| **Load balancing** | the bundled ServiceLB, rather than MetalLB |
| **Storage** | the default `local-path` provisioner; no persistent volumes in use yet |
| **Delivery** | `kubectl apply` today, Argo CD next |

## Repository layout

```
kubernetes/
  apps/              # workloads
    glance/          #   dashboard -- configmaps, deployment, ingress, sealed secret
  infrastructure/    # cluster-level components
    traefik/
bootstrap/           # Argo CD install and the app-of-apps root Application
docs/
  decisions.md       # why things are the way they are
```

Each app directory is flat and its files are named for the resource kind they contain
(`deployment.yaml`, `ingress.yaml`, `configmap-*.yaml`). That is a deliberate choice; see
[`docs/decisions.md`](docs/decisions.md) for the reasoning, which has to do with how
`kubectl` and Argo CD both handle nested directories.

## Applying

Manifests are applied from this repository, never authored elsewhere and copied in:

```sh
kubectl apply -f kubernetes/apps/glance/
```

Preview before committing to a change:

```sh
kubectl diff -f kubernetes/apps/glance/
```

> ⚠️ **Disclaimer.** These commands change a live cluster. They act on whatever context
> `kubectl` is currently pointed at; nothing here switches, creates, or validates a context
> on your behalf, and selecting the right cluster stays the operator's responsibility.
> Confirm with `kubectl config current-context` before applying.
>
> These manifests describe *this* cluster: single-node k3s, bundled Traefik, `local-path`
> storage. Applied elsewhere they may collide with existing resources of the same name.
> Read them, adapt them, apply them at your own risk.

Once Argo CD is in place, applying by hand stops being the mechanism and becomes the
break-glass path.

## Secrets

Plaintext `Secret` manifests are never committed. Encryption is
[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets): a value is encrypted
against the controller's **public** key, and only the controller, holding the private half
inside the cluster, can decrypt it. The resulting `SealedSecret` is safe in a public
repository, and Argo CD syncs it as an ordinary custom resource with no decryption plugin
in the sync path. Reasoning and the rejected alternative are in
[`docs/decisions.md`](docs/decisions.md).

Sealing a value:

```sh
kubectl create secret generic <name> \
  --namespace <ns> \
  --from-literal=<key>=<value> \
  --dry-run=client -o yaml \
| kubeseal --format yaml \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  > kubernetes/apps/<app>/sealed-secret.yaml
```

The `--dry-run=client` matters: it builds the manifest locally and pipes it straight into
`kubeseal` without the plaintext ever reaching the cluster or the disk.

> 🔑 **"The key is backed up, so I'm covered."** Only until the first renewal. The controller
> renews its sealing key every 30 days and *appends* it to the active set, and `kubeseal` always
> seals against the newest one. A backup therefore covers what existed the day it was taken, and
> anything sealed afterwards cannot be recovered from it. Re-take it on a schedule, or the gap is
> data loss waiting for a rebuild to reveal it.

### The controller is installed by hand

Argo CD cannot manage the controller, because it has to be running before Argo CD can unseal
anything. So it sits in the same layer as the k3s-bundled Traefik: installed once, outside
GitOps, and recorded here rather than tracked as a manifest.

Currently `v0.38.4`, in `kube-system`:

```sh
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.38.4/controller.yaml
```

On a rebuild, install the controller **first**, then restore the key backup over the key
Secret it creates, then sync. In that order, existing `SealedSecret` manifests keep working.

## Status

| Component | State |
| --- | --- |
| k3s | running |
| Traefik ingress | running |
| Glance dashboard | running -- manifests migrated into this repo |
| Sealed Secrets | controller running -- `glance-secrets` sealed and applied |
| Argo CD | not installed -- next milestone |

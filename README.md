# k3s-homelab-gitops

Declarative configuration for a single-node **k3s** homelab: every workload defined here,
applied from here.

![k3s](https://img.shields.io/badge/k3s-FFC61C?logo=k3s&logoColor=black)
![Kubernetes](https://img.shields.io/badge/kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Traefik](https://img.shields.io/badge/ingress-Traefik-24A1C1?logo=traefikproxy&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo%20CD-planned-EF7B4D?logo=argo&logoColor=white)
![GitOps](https://img.shields.io/badge/GitOps-0D1117?logo=git&logoColor=white)

---

## Overview

A personal cluster run as a proving ground for production practice: everything is version
controlled, every non-obvious choice is written down in [`docs/decisions.md`](docs/decisions.md) (Most probably),
and changes reach the cluster through this repository rather than by hand.

## Platform

| Layer | Choice |
| --- | --- |
| **Distribution** | k3s, single node control-plane and workloads on the same machine |
| **Ingress** | Traefik, as bundled with k3s and managed by its helm-controller |
| **Load balancing** | the bundled ServiceLB, rather than MetalLB |
| **Storage** | the default `local-path` provisioner; no persistent volumes in use yet |

## Repository layout

```
bootstrap/ 
  app-of-apps.yaml
  bootstrap.sh
  steps/
    0*-*.sh
kubernetes/
  apps/              # workloads
    glance/ 
  infrastructure/ 
    traefik/
  argocd-applications/
docs/
  decisions.md   
```

## Status

| Component | State |
| --- | --- |
| k3s | running |
| bash (bootstraping) | valid |
| Traefik ingress | running |
| Glance dashboard | running |
| Sealed Secrets | controller running |
| Argo CD | running |

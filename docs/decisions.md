# Decision log

Newest first. Each entry states what was chosen, then works through the questions that decided
it: the short answer first, then the reasoning behind it. Where a wrong answer was genuinely
tempting at the time, the assumption behind it is recorded in a blockquote. Assumptions here are
ones actually held during the work, not strawmen.

---

## 2026-08-16: Sealed Secrets over SOPS + age

**Chose:** Sealed Secrets. Values encrypted with `kubeseal` against the controller's public
key, committed as `SealedSecret` manifests.

### Can Argo CD just apply a SOPS file directly?

No. The values are still encrypted, and nothing along the way decrypts them.

> **Assumed:** SOPS output is valid YAML and still `kind: Secret`, so Argo CD can apply it like
> anything else.

Valid YAML is not the same as a valid Secret. A Secret's `data` field is contractually base64,
and `ENC[...]` is not, so the API server rejects the object. The apply path has no decrypt step
in it, and SOPS does not know it was handed a Secret in the first place. Move the value to
`stringData` and the schema check passes instead: the object is accepted and the workload gets
ciphertext as its token with nothing reporting an error. The silent one is the dangerous one.

The missing layer is decryption, not base64. `sops -d` restores the original base64 value as a
side effect of restoring the file. So something has to run it between Git and the cluster, and
with Argo CD that something is a config management plugin in the repo-server.

A `SealedSecret` sidesteps the question entirely. It is its own CRD, so it is never judged
against the Secret schema, and an in-cluster controller produces the real Secret from it. Argo
CD just syncs a manifest.

### Which side owns the private key?

The key ends up in the cluster either way. What changes is who generates it.

> **Assumed:** the age key lives on my laptop, so the cluster never holds it.

With SOPS the decrypting happens in the repo-server (the Argo CD component that renders
manifests). It is a pod, so handing it the age private key means mounting that key into the
cluster as a Secret. There is nowhere else for it to live.

- **SOPS + age:** I generate the keypair on my laptop and lend the cluster a copy of the
  private half.
- **Sealed Secrets:** the controller generates the keypair in-cluster and I take a copy out.

So my job flips from handing a key out to remembering to fetch a backup of one I never created.
That reversal is the real cost of this choice, and it is why the key backup is load-bearing
rather than a precaution.

### Is backing the key up once enough?

No. This is the assumption that survived longest.

> **Assumed:** export the key after install, store it safely, problem closed.

Sealing keys renew every 30 days and are *appended* to the active set rather than replacing it,
and `kubeseal` always seals against the newest one. A backup covers only what existed when it
was taken. The 2026-08-10 export is complete today and stops being complete at the first
renewal, with nothing announcing it.

### What else bit

- Adopting a hand-made Secret is not automatic, because the controller refuses to overwrite a
  Secret it does not own. Two ways out: annotate the existing Secret with
  `sealedsecrets.bitnami.com/managed: "true"` and let the controller take it over in place, or
  delete it and let the controller recreate it from the `SealedSecret`. Took the second on
  2026-08-17, so the annotation was never applied. The live Secret now carries an
  `ownerReferences` entry pointing at the `SealedSecret`.
  Deleting is the destructive option: it removes the only in-cluster copy of the plaintext, so
  it is safe only if the sealed value is known good. Annotating fails safe.
- `kubectl get secret -o yaml` prints plaintext out of the
  `kubectl.kubernetes.io/last-applied-configuration` annotation, and that annotation rides into
  the sealed output if left in place. Strip annotations before piping to `kubeseal`. This bit
  the original hand-applied `glance-secrets`; the recreated one has no annotations at all,
  because the controller wrote the object instead of `kubectl apply`.

---

## 2026-08-10: The Namespace is Argo CD's to create, not the app directory's

**Chose:** no `namespace.yaml` in `kubernetes/apps/glance/`. The namespace becomes Argo CD's
responsibility via `syncOptions: [CreateNamespace=true]` on the Application when that lands.

### Why not keep the namespace next to the app that uses it?

Because `kubectl apply -f <dir>/` reads files alphabetically, and `namespace.yaml` sorts after
`deployment.yaml`.

On an empty cluster the Deployment is rejected for a namespace that does not exist yet, and
only a second apply succeeds. That is the same class of quiet apply-path trap the flat-directory
entry below was written to avoid, and prefixes like `00-` were already rejected there.

Keeping the directory to namespaced resources only also means every file in it belongs to the
same Argo CD Application, with the namespace handled one layer up where it belongs.

### What does this cost?

One manual step on a fresh cluster: `kubectl create ns glance` before the first apply.

Acceptable, because that path is exercised roughly never, and the milestone that removes it is
the next one.

**Rejected:** a cluster-level `kubernetes/namespaces.yaml` applied ahead of the app directories.
Correctly ordered and explicit, but it adds a second apply step the README has to describe, and
it is dead weight the moment Argo CD takes over namespace creation anyway.

---

## 2026-08-10: Amendment: a pinned tag only fixes `imagePullPolicy` on a *new* object

**Amends** the 2026-08-03 entry below, which is correct about the mechanism but incomplete
about migrating an object that already exists.

### What was still broken after the DNS fix

Fixing MagicDNS brought the registry back within reach. It did not take the workload off it.

Every new pod still had to pull from `docker.io` before it could start, because the stored
`imagePullPolicy` was still `Always`. Pinning the tag in the manifest was supposed to end exactly
that, and it had changed nothing. The coupling the 08-03 entry set out to remove was still
there, now hidden behind a working DNS instead of a broken one.

Checking the live object showed it plainly: `image=glanceapp/glance:v0.8.5` alongside
`pullPolicy=Always`. The manifest said the right thing and the cluster had not moved. Nothing
had reported a problem, because from the API's point of view the apply had succeeded.

### Why did the pin not take effect?

Because the policy was already stored in the object, and nothing in the new manifest overwrote
it.

> **Assumed:** pinning the tag changes the default, so the running Deployment picks up
> `IfNotPresent` on the next apply.

`imagePullPolicy` is defaulted at admission, only when the field is unset, and the result is
written into the object once. This Deployment was created with `glanceapp/glance` untagged, so
`Always` was stored in its spec at creation. A manifest that pins the tag but says nothing about
`imagePullPolicy` therefore changes only the image: there is no field in the incoming manifest
to overwrite the stored `Always`, and it survives.

The defaulting rule from the entry below is still correct. It just describes what happens to a
new object, and this object was not new.

### How it was fixed

Deleted the Deployment and recreated it.

A fresh object re-runs defaulting, so the pinned tag produced `IfNotPresent` with no explicit
field in the manifest. Repo and cluster now agree.

### When is recreating safe?

Only when the image can actually be pulled.

Deleting the Deployment destroys the running pod, and a rolling update is what keeps the old pod
serving while a new one fails. A recreate has no such cover. With DNS still broken it would have
taken the dashboard down instead of failing harmlessly. Fix the pull path first, then recreate.

**Rejected:** setting `imagePullPolicy: IfNotPresent` explicitly in the manifest. It works and
needs no recreate, but it states a value that is already the default for a pinned tag, and a
field that restates a default invites the reader to wonder what is special here. Recreating
once was the cheaper fix and leaves the manifest saying only what it needs to.

---

## 2026-08-03: Image tags are pinned, never floating

**Chose:** an explicit tag on every image, `glanceapp/glance:v0.8.5` rather than
`glanceapp/glance`.

> This decision came out of the MagicDNS incident, but it is not a fix for it. DNS was already
> repaired by the time the tag was pinned. The amendment above is what happened when the pin was
> applied to the Deployment that was already running.

### What happened

Tailscale MagicDNS failed, so the node could not resolve names at all, `docker.io` included.

Glance kept serving throughout, because a running container never re-pulls. The breakage only
appeared on `kubectl rollout restart`: the new pod could not start. `:latest` had defaulted
`imagePullPolicy` to `Always`, so every new pod insists on reaching the registry first, even
though that exact image was already cached on the node.

So a DNS fault I had not connected to Glance at all had quietly taken away my ability to restart
it.

### Why pin the tag, if DNS was already fixed?

To stop the two failures being tied together.

Fixing DNS fixed DNS. It did nothing about the fact that this workload cannot restart without
the registry, which means the next name-resolution problem, registry outage, or offline node
takes the restart path down again. A pinned tag defaults to `IfNotPresent`, so the cached image
starts and the registry stops being on the critical path for an image already pulled once.

Two independent problems that fail independently, instead of one where a DNS fault silently
becomes a workload problem.

The ordinary reason applies too: with `:latest` the running version can change on any pull, so
"what is deployed" is not answerable from this repo and there is no known-good tag to roll back
to.

**Rejected:**

- Leaving the tag off and setting `imagePullPolicy: IfNotPresent` explicitly. It removes the
  startup dependency but keeps the version ambiguous, and that ambiguity is exactly what makes
  an incident hard to reason about afterwards.
- Pinning by digest. Stronger, and it would pin the exact bits, but it turns every routine
  update into copying a hash around. Revisit if provenance ever matters more than update
  ergonomics.

---

## 2026-08-02: App directories stay flat; manifests named by kind

**Chose:** one flat directory per app under `kubernetes/<category>/<app>/`, with each file named
for the resource kind it contains: `deployment.yaml`, `ingress.yaml`, `configmap-config.yaml`,
`configmap-assets.yaml`. No per-kind subdirectories.

### Why not group manifests into subdirectories?

Because the tools that read the directory do not recurse by default, and both fail quietly.

- `kubectl apply -f <dir>/` **does not recurse**. With a `configmaps/` subdirectory it applies
  the top-level files, skips the nested ones, and exits 0. A config change looks deployed and
  silently is not.
- Argo CD repeats the same default: a `directory`-type Application has `directory.recurse:
  false`, so it would report `Synced` while ignoring everything below the first level.

Avoiding a footgun that fails *quietly* is worth more than tidier nesting. Flat also keeps the
plain `kubectl apply -f kubernetes/apps/glance/` in the README correct, with no `-R` or
`recurse: true` to remember at two different layers.

### Why name files by kind?

The directory already establishes the app, so repeating the app name in the filename carries no
information. The kind is the thing you actually scan for.

**Rejected:**

- Per-kind subdirectories (`configmaps/`, `secrets/`). Real value only once an app has enough
  manifests that a flat listing is hard to scan, which Glance is nowhere near. Revisit per app
  if one ever grows past roughly a dozen files, and set `recurse` in the same commit if so.
- Numeric apply-order prefixes (`00-`, `10-`). Argo CD sync waves will handle ordering, and
  filename ordering would then be a second, conflicting source of truth.

---

## 2026-08-02: Repo named `k3s-homelab-gitops`

**Chose:** `k3s-homelab-gitops`, hyphenated, as both the directory and the repo name.

### Why hyphens rather than spaces?

A space in the path forces quoting in every `cd`, `kubectl apply -f`, and script line.

GitHub also rewrites spaces to hyphens on repo creation, so a spaced local directory would
guarantee that the local and remote names diverge.

### Why name the platform in it?

It puts the platform and the practice in one name, which is what the repo is for.

**Rejected:**

- `homelab-gitops` alone. Drops the platform, though it ages better if k3s is ever swapped for
  Talos or k3s HA.
- Nesting under a separate `k3s/` parent directory. A parent holding one child adds path depth
  carrying no information, and makes the git root ambiguous on clone.

---

<!-- ## OPEN: MetalLB evaluated, ServiceLB kept
     A leftover MetalLB config on the node shows MetalLB was tried. Record why it was
     dropped in favour of the bundled klipper ServiceLB before the reasoning is lost.
-->

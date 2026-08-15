# headplane chart

Headplane with headscale as a sidecar, in integrated mode.

## Where the configuration lives

From 0.1.10 the headscale configuration is **declarative**. The `headscale-config`
ConfigMap is the single source of truth and is mounted read-only:

| Path | Volume | Written by |
| --- | --- | --- |
| `/etc/headscale-config/config.yaml` | ConfigMap `headscale-config`, read-only | Helm values only |
| `/etc/headscale/` | PVC (`headscale.persistence.pvc.name`) | headscale: database, `noise_private.key`, DERP key, unix socket |
| `/etc/headscale/extra_records.json` | same PVC, writable | Headplane, from the DNS page |

headscale is pointed at the ConfigMap through `HEADSCALE_CONFIG`, so nothing in
the cluster can edit its configuration and drift away from git.

Because the file is read-only, Headplane detects it and renders the DNS
settings as read-only rather than accepting edits it could not persist. Extra
DNS records stay editable: they live in their own file on the writable volume,
which headscale watches and applies without a restart.

### Which changes restart the pod

The StatefulSet's `checksum/configmap-headscale` annotation deliberately hashes
the configuration **without** the sections headscale reloads on its own, so:

| Changing | Effect |
| --- | --- |
| `dns.magicDns`, `dns.nameservers`, `dns.overrideLocalDns` | applied live, no restart |
| `oidc.allowedDomains`, `oidc.allowedUsers` | applied live, no restart |
| anything else, including `dns.baseDomain` | pod restarts |

`dns.baseDomain` restarts because it is baked into every node's FQDN, and
headscale refuses to change it at runtime.

Live reload needs a headscale build with `config_watch` support. Without it the
`dns` and `oidc.allowed_*` changes reach the file but are not picked up until
the next restart.

> Adding a key that headscale **cannot** reload? Put it outside the
> `includeReloadable` guards in `_helpers.tpl`, or changing it will silently do
> nothing.

## Upgrading from 0.1.9 or earlier

Before 0.1.10 an init container copied the ConfigMap to `/etc/headscale/config.yaml`
on first run only, and Headplane wrote to it directly. That copy is where your
running configuration actually lives, and it has almost certainly drifted from
your values: anything changed through the Headplane UI — split DNS entries,
search domains, OIDC allow-lists — was never written back to git.

**Reconcile before upgrading, or those changes are dropped.** The old file is
left in place rather than deleted, so a rollback to 0.1.9 picks it up again.

```bash
# Read the live configuration (the headscale image has no shell, so go through
# /proc from an ephemeral container; the pod shares its PID namespace)
PID=$(kubectl logs <pod> -n <ns> -c headplane | grep -o 'Found headscale serve (PID [0-9]*' | grep -o '[0-9]*$')
kubectl debug -n <ns> <pod> --image=busybox:latest --target=headscale \
  --container=peek --profile=sysadmin -q -- \
  sh -c "cat /proc/$PID/root/etc/headscale/config.yaml" >/dev/null
kubectl logs -n <ns> <pod> -c peek > live-config.yaml

# Diff it against what the chart would render
helm template <release> . -f your-values.yaml \
  | yq '. | select(.metadata.name == "headscale-config") | .data["config.yaml"]' > rendered.yaml
diff -u rendered.yaml live-config.yaml
```

Fold anything that exists only in `live-config.yaml` into your values, then
upgrade. `dns.extra_records` in the old file should move to the new
`extra_records.json`, which the init container seeds as `[]`.

## Note on names

The ConfigMap `headscale-config` and the PVC claim (also `headscale-config` by
default, via `headscale.persistence.pvc.name`) share a name but are different
objects. The claim name is left alone on purpose: renaming it would strand the
existing volume, and with it `noise_private.key` — losing that forces every
node to re-authenticate.

# k3s-jellyfin

Jellyfin Media Server deployment for the k3s cluster.

## Overview

This repository deploys Jellyfin Media Server to your k3s cluster using the official Jellyfin helm chart with custom values, following the established GitOps pattern with ArgoCD.

## Deployment Architecture

This deployment uses the official Jellyfin helm chart with custom configuration:

- **Chart**: `jellyfin` from https://jellyfin.github.io/jellyfin-helm
- **Custom Values**: `helm/values.yaml` (version-controlled in this repo)
- **PVCs**: Managed separately in `manifests/` directory (outside helm control)
- **ArgoCD**: Multi-source application combining helm chart + custom values + PVC manifests

### Repository Structure

```
k3s-jellyfin/
├── helm/
│   └── values.yaml          # Custom helm chart configuration
├── manifests/
│   ├── pvc-config.yaml      # 20Gi Longhorn PVC for config
│   └── pvc-cache.yaml       # 15Gi Longhorn PVC for cache
├── scripts/
│   └── create-secret.sh     # (Future use)
├── Makefile                 # Local development helpers
└── README.md
```

### Auto-Deployment

This repo is deployed automatically by ArgoCD from the `k3s-infra` cluster bootstrap. ArgoCD watches the `helm/` and `manifests/` directories on the `main` branch and automatically syncs changes.

### Prerequisites

- k3s cluster running with ArgoCD installed
- Longhorn storage system deployed and healthy
- Tailscale operator installed and configured
- A node labeled `storage=external` with media directories available

### Manual Deployment (Local Development)

For testing before committing to git:

```bash
# Copy environment template
cp .env.example .env

# Add Jellyfin helm repo and deploy
make deploy  # Installs PVCs, helm chart, and waits for ready

# Check status
make status

# Preview generated manifests
make helm-template
```

## Storage Architecture

### Persistent Volumes (Longhorn)

- **Config/Metadata**: 20GB Longhorn PVC
  - Stores Jellyfin configuration, database, metadata, plugins
  - Replicated across nodes (2 replicas)
  - Automatically backed up to MinIO S3

- **Cache**: 15GB Longhorn PVC
  - Transcoding cache and temporary files
  - Persistent across pod restarts
  - Can be increased if needed

### Host Path Mounts

- **TV Shows**: `/mnt/external/tv` → mounted at `/media/tv` (read-only)
- **Movies**: `/mnt/external/movies` → mounted at `/media/movies` (read-only)

Media directories are mounted read-only to prevent accidental deletion or modification.

## Network Access

### Tailscale (Recommended)

Jellyfin is exposed via Tailscale with hostname `jellyfin`:

- **Web UI**: `http://jellyfin.<your-tailnet>.ts.net:8096`
- Secure, encrypted access from anywhere on your Tailscale network
- No port forwarding or public exposure required

## Initial Setup

1. **Access Jellyfin Web UI** via Tailscale URL
2. **Create admin account** (first-run wizard)
3. **Complete setup wizard**
4. **Add media libraries**:
   - TV Shows: `/media/tv`
   - Movies: `/media/movies`
5. **Configure settings**:
   - Set preferred quality and bandwidth
   - Configure transcoding settings
   - Install desired plugins

## Hardware Acceleration (Optional)

If your cluster nodes have Intel CPUs with QuickSync support:

1. Edit [helm/values.yaml](helm/values.yaml)
2. Uncomment the hardware acceleration sections in `volumes` and `volumeMounts`
3. Commit and push changes
4. ArgoCD will auto-sync and restart the pod

## Troubleshooting

### Pod Won't Start

```bash
# Check PVC status
kubectl get pvc -n jellyfin

# Check pod events
kubectl describe pod -n jellyfin -l app.kubernetes.io/name=jellyfin

# Check logs
kubectl logs -n jellyfin -l app.kubernetes.io/name=jellyfin --tail=100
```

### Can't Access via Tailscale

```bash
# Check Tailscale operator
kubectl get pods -n tailscale

# Verify service annotations
kubectl get svc jellyfin -n jellyfin -o yaml | grep tailscale
```

### Media Not Showing

```bash
# Verify media mounts
kubectl exec -n jellyfin deployment/jellyfin -- ls -la /media/tv /media/movies

# Check permissions on host
ssh control-plane "ls -la /mnt/external/tv /mnt/external/movies"
```

## Maintenance

### Updating Jellyfin

The deployment uses chart's default image tag (latest stable). To pin a specific version:

1. Edit [helm/values.yaml](helm/values.yaml):
   ```yaml
   image:
     tag: "10.8.13"  # Pin to specific version
   ```
2. Commit and push changes
3. ArgoCD will auto-sync and restart the pod

### Expanding Storage

```bash
# Config PVC
kubectl patch pvc jellyfin-config -n jellyfin -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# Cache PVC
kubectl patch pvc jellyfin-cache -n jellyfin -p '{"spec":{"resources":{"requests":{"storage":"30Gi"}}}}'
```

### Adding Media Directories

Edit [helm/values.yaml](helm/values.yaml) and add new volumes:

```yaml
volumes:
  - name: music
    hostPath:
      path: /mnt/external/music
      type: DirectoryOrCreate

volumeMounts:
  - name: music
    mountPath: /media/music
    readOnly: true
```

Commit and push - ArgoCD will auto-sync.

## Makefile Targets

```bash
make help          # Show available targets
make deploy        # Full deployment (PVCs + helm chart)
make apply-pvcs    # Apply PVC manifests only
make install-helm  # Install/upgrade helm chart
make helm-template # Preview generated Kubernetes manifests
make status        # Show Jellyfin resources status
make clean         # Remove Jellyfin but keep PVCs
make destroy       # Remove Jellyfin completely (with confirmation)
```

## Comparison with Plex

Both Jellyfin and Plex can coexist on the same cluster:

| Feature | Jellyfin | Plex |
|---------|----------|------|
| License | Open source (GPL) | Freemium (Plex Pass) |
| Tailscale Hostname | `jellyfin` | `plex` |
| Port | 8096 | 32400 |
| Config PVC | 20Gi Longhorn | 20Gi Longhorn |
| Cache/Transcode | 15Gi Longhorn | 15Gi Longhorn |
| Media | Shared (`/mnt/external`) | Shared (`/mnt/external`) |

## License

This configuration is part of the k3s homelab cluster setup.

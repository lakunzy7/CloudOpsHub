# GitOps Sync Agent

This project uses a **lightweight GitOps sync agent** instead of Kubernetes-native ArgoCD,
since the infrastructure runs Docker Compose on GCE VMs (not Kubernetes).

## How It Works

The sync agent runs as a Docker container on the VM and implements the same GitOps principles as ArgoCD:

1. **Watches** the `main` branch of this Git repository
2. **Detects** changes to files under `gitops/` (docker-compose manifests, overlays)
3. **Pulls** updated Docker images from Artifact Registry
4. **Deploys** using `docker-compose up -d` with environment-specific overlays
5. **Records** the last synced Git SHA to avoid redundant deployments

## Architecture

```
GitHub Repo (gitops/)
       │
       ▼  (git poll every 60s)
┌──────────────────┐
│  GitOps Sync     │  ← Docker container on VM
│  Agent           │
└──────┬───────────┘
       │  docker-compose up -d
       ▼
┌──────────────────┐
│  App Containers  │  frontend, backend, database
│  + Monitoring    │  prometheus, grafana, alertmanager
└──────────────────┘
```

## CD Pipeline Flow

```
Code push → CI (build/scan/push images) → CD (update gitops/base/docker-compose.yml)
  → Git commit → GitOps agent detects change → pulls images → redeploys
```

## Configuration

| Env Variable | Default | Description |
|---|---|---|
| `GITOPS_REPO_URL` | repo URL | Git repository to watch |
| `GITOPS_BRANCH` | `main` | Branch to track |
| `GITOPS_ENVIRONMENT` | `dev` | Which overlay to use |
| `GITOPS_SYNC_INTERVAL` | `60` | Poll interval in seconds |

## Files

- `gitops/base/docker-compose.yml` — Base deployment manifest
- `gitops/overlays/{dev,staging,production}/` — Environment overrides
- `gitops/scripts/gitops-sync.sh` — The sync agent script
- `gitops/scripts/deploy.sh` — Manual deploy helper

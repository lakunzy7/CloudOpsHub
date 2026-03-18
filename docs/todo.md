# CloudOpsHub TODO

## Upcoming Tasks

### 1. Introduce Ansible for VM Configuration Management
- Switch base OS from COS to Ubuntu (required for Ansible SSH access)
- Create Ansible project structure (`ansible/inventory/`, `ansible/playbooks/`, `ansible/roles/`)
- Build roles: Docker installation, Artifact Registry auth, GitOps agent, monitoring stack
- Create per-environment inventories (dev, staging, production)
- Use Ansible Vault for secrets management
- Replace startup script with Ansible playbooks
- Integrate Ansible into CI/CD pipeline for automated provisioning
- Ensure all environments are configured identically

### 2. Set Up Staging Environment
- Provision staging infrastructure with Terraform (`terraform apply -var-file=envs/staging.tfvars`)
- Configure staging GitHub secrets (WIF, SA email)
- Add staging to CD pipeline

### 3. Re-enable Monitoring Stack
- Add Prometheus, Grafana, Alertmanager, Node Exporter back to docker-compose
- Verify monitoring runs on VM after deploy

### 4. Fix Security Scan Issues
- Upgrade vulnerable npm dependencies (mysql2, sequelize, express, lodash, etc.)
- Address Trivy image vulnerabilities
- Create SonarCloud project and remove `continue-on-error`
- Remove `continue-on-error` from Snyk after fixing deps

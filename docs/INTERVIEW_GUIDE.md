# Interview guide

## Two-minute explanation

This project builds a reusable EKS platform with Terraform and deploys workloads through Argo CD. CI validates Terraform, Helm, and security posture. In a production version, GitHub Actions would use OIDC to publish immutable images to ECR, then update the GitOps repository. Argo CD detects the change, deploys it, and continuously corrects drift.

## Improvements for a real production environment

- Separate AWS accounts for security, shared services, dev, QA, and production.
- Replace public API access with private endpoints or trusted corporate CIDRs.
- Add ECR, external-dns, AWS Load Balancer Controller, cert-manager, and External Secrets.
- Add Prometheus/Grafana, OpenTelemetry, centralized logs, SLOs, and burn-rate alerts.
- Use policy-as-code, signed images, admission control, backups, and tested disaster recovery.


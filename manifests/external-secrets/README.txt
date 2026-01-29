# External Secrets Example Configuration

This directory contains example External Secrets manifests for the test-app.

## Files

- `secret-store.yaml`: SecretStore and ClusterSecretStore configurations
- `external-secret-rds.yaml`: ExternalSecret for RDS database credentials

## Usage

These manifests are automatically applied during deployment via `script/deploy_module.sh`.

### Manual Application

```bash
# Apply SecretStore
kubectl apply -f manifests/external-secrets/secret-store.yaml

# Apply ExternalSecret for RDS
kubectl apply -f manifests/external-secrets/external-secret-rds.yaml -n default

# Verify
kubectl get externalsecrets -n default
kubectl get secrets rds-database-secret -n default
```

## Environment Variables

The ExternalSecret creates a Kubernetes secret with the following keys that are injected into the app:

- `DB_HOST`: Database host
- `DB_PORT`: Database port
- `DB_NAME`: Database name
- `DB_USERNAME`: Database username
- `DB_PASSWORD`: Database password
- `DATABASE_URL`: Complete connection string

## Prerequisites

1. External Secrets Operator must be installed (see infrastructure repo)
2. RDS credentials must exist in AWS Secrets Manager with key: `hlf-sit-rds-master-credentials`

## Customization

Update `external-secret-rds.yaml` to match your:
- Secret name in AWS Secrets Manager
- Kubernetes namespace
- Secret key mappings

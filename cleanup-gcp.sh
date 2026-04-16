#!/usr/bin/env bash
# =============================================================================
# GCP OIDC Cleanup
# =============================================================================
# Removes all resources created by setup-gcp.sh and the workflow.
# Run this when you want to tear down the lab environment.
#
# USAGE:
#   1. Fill in the CONFIGURATION section below (same values as setup-gcp.sh)
#   2. chmod +x cleanup-gcp.sh && ./cleanup-gcp.sh
# =============================================================================

set -uo pipefail  # no -e so we continue past already-deleted resources

# =============================================================================
# CONFIGURATION — use the same values as setup-gcp.sh
# =============================================================================

PROJECT_ID="your-gcp-project-id"
REGION="us-east1"
POOL_NAME="gh-actions-identity"
SA_NAME="gh-actions-sa"

# =============================================================================
# CLEANUP — do not edit below this line
# =============================================================================

echo "=== GCP cleanup ==="
echo "Project: $PROJECT_ID"
echo ""

# STEP 1 — Delete subnet (must be deleted before the VPC)
echo "[1/5] Deleting subnet subnet-gh-created..."
gcloud compute networks subnets delete "subnet-gh-created" \
  --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null \
  && echo "      ✓ deleted" || echo "      (already gone)"

# STEP 2 — Delete VPC
echo "[2/5] Deleting VPC vpc-gh-created..."
gcloud compute networks delete "vpc-gh-created" \
  --project="$PROJECT_ID" --quiet 2>/dev/null \
  && echo "      ✓ deleted" || echo "      (already gone)"

# STEP 3 — Delete the OIDC Provider inside the pool
echo "[3/5] Deleting OIDC Provider..."
gcloud iam workload-identity-pools providers delete "${POOL_NAME}-provider" \
  --workload-identity-pool="$POOL_NAME" \
  --location="global" --project="$PROJECT_ID" --quiet 2>/dev/null \
  && echo "      ✓ deleted" || echo "      (already gone)"

# STEP 4 — Delete the Workload Identity Pool
# NOTE: GCP soft-deletes pools for 30 days.
# The name cannot be reused until fully purged OR you use --undelete.
# The setup-gcp.sh script handles this automatically via --undelete.
echo "[4/5] Deleting Workload Identity Pool..."
gcloud iam workload-identity-pools delete "$POOL_NAME" \
  --location="global" --project="$PROJECT_ID" --quiet 2>/dev/null \
  && echo "      ✓ soft-deleted (purged in 30 days)" || echo "      (already gone)"

# STEP 5 — Delete the Service Account
echo "[5/5] Deleting Service Account..."
gcloud iam service-accounts delete \
  "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" --quiet 2>/dev/null \
  && echo "      ✓ deleted" || echo "      (already gone)"

echo ""
echo "=== Cleanup complete ==="
echo ""
echo "Note: If you want to reuse the same POOL_NAME within 30 days,"
echo "run setup-gcp.sh again — it will automatically undelete the pool."

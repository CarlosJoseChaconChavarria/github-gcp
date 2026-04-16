#!/usr/bin/env bash
# =============================================================================
# GCP OIDC Setup for GitHub Actions
# =============================================================================
# Configures Google Cloud to trust GitHub Actions via OIDC.
# Run this ONCE before using the workflow for the first time.
#
# WHAT IS OIDC?
# Instead of storing a GCP Service Account JSON key as a GitHub secret
# (a long-lived credential that can leak), OIDC lets GitHub and GCP trust
# each other using short-lived tokens. GitHub generates a JWT per workflow
# run. GCP validates it and issues temporary credentials.
# No keys. No secrets. No rotation needed.
#
# PREREQUISITES:
#   - gcloud CLI installed and authenticated (gcloud auth login)
#   - Owner or Editor role on your GCP project
#   - Run from Cloud Shell or a local terminal
#
# USAGE:
#   1. Fill in the CONFIGURATION section below
#   2. chmod +x setup-gcp.sh && ./setup-gcp.sh
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION — fill in your values here
# =============================================================================

# Your GCP Project ID (GCP Console → project selector)
PROJECT_ID="your-gcp-project-id"

# Your GCP Project NUMBER — different from ID, find it with:
#   gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"
PROJECT_NUMBER="your-gcp-project-number"

# Name for the Workload Identity Pool — you choose this label
POOL_NAME="gh-actions-identity"

# Name for the Service Account — you choose this label
SA_NAME="gh-actions-sa"

# Your GitHub username or organization name
GH_USER="your-github-username"

# The exact name of the GitHub repo that will run the workflow
GH_REPO="github-gcp"

# =============================================================================
# SETUP — do not edit below this line
# =============================================================================

echo "=== GCP OIDC setup ==="
echo "Project:  $PROJECT_ID ($PROJECT_NUMBER)"
echo "Pool:     $POOL_NAME"
echo "SA:       $SA_NAME"
echo "GitHub:   $GH_USER/$GH_REPO"
echo ""

# STEP 1 — Enable the IAM Credentials API
# Required for Workload Identity Federation to work.
# Allows the workflow to exchange a GitHub JWT token for GCP credentials.
echo "[1/6] Enabling IAM Credentials API..."
gcloud services enable iamcredentials.googleapis.com --project="$PROJECT_ID"

# STEP 2 — Enable the Compute API
# Required so the workflow can create VPCs and subnets.
# Enabled here so the SA does not need the serviceUsageAdmin role.
echo "[2/6] Enabling Compute API..."
gcloud services enable compute.googleapis.com --project="$PROJECT_ID"

# STEP 3 — Create the Workload Identity Pool
# GCP equivalent of the OIDC Identity Provider in AWS.
# Acts as a container holding the trust configuration for GitHub.
#
# NOTE: GCP soft-deletes pools for 30 days after deletion.
# If you see ALREADY_EXISTS it means a pool with this name still exists
# (possibly soft-deleted). This step handles both cases:
#   - If active: skips creation, undeletes if needed
#   - If soft-deleted: undeletes it so we can reuse it
echo "[3/6] Creating Workload Identity Pool..."
if gcloud iam workload-identity-pools describe "$POOL_NAME" \
    --project="$PROJECT_ID" --location="global" &>/dev/null; then
  echo "      Pool already exists — checking state..."
  POOL_STATE=$(gcloud iam workload-identity-pools describe "$POOL_NAME" \
    --project="$PROJECT_ID" --location="global" \
    --format="value(state)")
  if [ "$POOL_STATE" = "DELETED" ]; then
    echo "      Pool is soft-deleted — undeleting..."
    gcloud iam workload-identity-pools undelete "$POOL_NAME" \
      --project="$PROJECT_ID" --location="global"
    echo "      ✓ undeleted"
  else
    echo "      ✓ pool already active, skipping"
  fi
else
  gcloud iam workload-identity-pools create "$POOL_NAME" \
    --project="$PROJECT_ID" \
    --location="global" \
    --display-name="GitHub Actions Pool"
  echo "      ✓ created"
fi

# STEP 4 — Create the OIDC Provider inside the pool
# Tells GCP to trust tokens from GitHub's OIDC endpoint.
#
# --attribute-mapping maps GitHub JWT claims to GCP attributes:
#   google.subject         = unique identity (repo + ref)
#   attribute.actor        = GitHub user who triggered the run
#   attribute.repository   = repo name (used in the binding below)
#   attribute.repository_owner = your GitHub username or org
#
# --attribute-condition is REQUIRED by GCP — restricts the pool to
#   your GitHub user/org only. Without it GCP rejects this command.
#
# --issuer-uri is GitHub's public OIDC endpoint (same for everyone)
echo "[4/6] Creating OIDC Provider..."
if gcloud iam workload-identity-pools providers describe "${POOL_NAME}-provider" \
    --workload-identity-pool="$POOL_NAME" \
    --project="$PROJECT_ID" --location="global" &>/dev/null; then
  echo "      Provider already exists — skipping"
else
  gcloud iam workload-identity-pools providers create-oidc "${POOL_NAME}-provider" \
    --project="$PROJECT_ID" \
    --location="global" \
    --workload-identity-pool="$POOL_NAME" \
    --display-name="GitHub Actions OIDC Provider" \
    --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --attribute-condition="assertion.repository_owner == '${GH_USER}'" \
    --issuer-uri="https://token.actions.githubusercontent.com"
  echo "      ✓ created"
fi

# STEP 5 — Create the Service Account
# The GCP identity the workflow will impersonate.
# GCP equivalent of the IAM Role in AWS.
# The workflow never gets the SA key — it impersonates via the pool.
echo "[5/6] Creating Service Account..."
if gcloud iam service-accounts describe \
    "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    --project="$PROJECT_ID" &>/dev/null; then
  echo "      Service account already exists — skipping"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="GitHub Actions Service Account"
  echo "      ✓ created"
fi

# STEP 6 — Grant permissions and bind the pool to the Service Account
#
# Part A — Grant roles/compute.networkAdmin so the SA can create
# VPCs and subnets. Equivalent to AmazonVPCFullAccess in AWS.
# NOTE: In production, always use a least-privilege custom role.
#
# Part B — Allow the pool to impersonate the SA, scoped to this repo only.
# The principalSet uses attribute.repository which means ONLY
# GH_USER/GH_REPO can authenticate. Any other repo cannot use this SA.
echo "[6/6] Granting networkAdmin role + binding pool to SA..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.networkAdmin"

gcloud iam service-accounts add-iam-policy-binding \
  "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GH_USER}/${GH_REPO}"
echo "      ✓ done"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Now add these as GitHub Actions repository variables:"
echo "Repo -> Settings -> Secrets and variables -> Actions -> Variables tab"
echo ""
echo "  GCP_PROJECT_ID       = $PROJECT_ID"
echo "  GCP_PROJECT_NUMBER   = $PROJECT_NUMBER"
echo "  GCP_REGION           = us-east1"
echo "  GCP_POOL_NAME        = $POOL_NAME"
echo "  GCP_SA_NAME          = $SA_NAME"
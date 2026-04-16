# GitHub Actions → GCP via OIDC
> Deploy a VPC + Subnet using gcloud CLI — no long-lived credentials

## Why OIDC?
Without OIDC you store a Service Account JSON key as a GitHub secret — a long-lived credential that can leak. With OIDC, GitHub and GCP trust each other via short-lived tokens. No keys. No rotation.

## How it works
```
GitHub Actions
  │  1. Generates JWT token for this run
  ▼
token.actions.githubusercontent.com
  │  2. Sends token to GCP Security Token Service
  ▼
GCP Workload Identity Federation
  │  3. Validates token + checks attribute binding (repo condition)
  ▼
Impersonate Service Account → Temporary credentials
  │  4. Workflow runs gcloud commands
  ▼
GCP Resources (VPC, Subnet)
```

## AWS vs GCP — OIDC concept mapping
| AWS | GCP | Purpose |
|---|---|---|
| OIDC Identity Provider | Workload Identity Pool + Provider | Trusts GitHub's OIDC endpoint |
| IAM Role | Service Account | Identity the workflow assumes |
| Trust Policy `sub` condition | `attribute.repository` binding | Locks access to your specific repo |
| `sts:AssumeRoleWithWebIdentity` | `roles/iam.workloadIdentityUser` | Permission to impersonate |
| `AmazonVPCFullAccess` | `roles/compute.networkAdmin` | Permission to create network resources |

## Step 1 — Run setup-gcp.sh (once)
1. Open `setup-gcp.sh`
2. Fill in the **CONFIGURATION** section at the top
3. Run it:
```bash
chmod +x setup-gcp.sh && ./setup-gcp.sh
```

## Step 2 — Add GitHub Actions repository variables
**Settings → Secrets and variables → Actions → Variables tab**

The script prints these when it finishes:

| Variable | What it is |
|---|---|
| `GCP_PROJECT_ID` | Your GCP Project ID |
| `GCP_PROJECT_NUMBER` | Your GCP Project Number |
| `GCP_REGION` | e.g. `us-east1` |
| `GCP_POOL_NAME` | Pool name used in setup |
| `GCP_SA_NAME` | SA name used in setup |

## Step 3 — Run the workflow
Actions tab → **Deploy GCP VPC** → Run workflow → watch **Verify identity** confirm OIDC worked.
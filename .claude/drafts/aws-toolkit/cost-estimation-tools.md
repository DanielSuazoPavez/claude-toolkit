# AWS Cost Estimation & Optimization Tools — Research (2026-02)

Goal: let an `aws-architect` agent say "this will cost ~$X/month" at design time, not after the bill arrives.

## Pre-deploy cost estimation (the main need)

| Tool | What it does | Creds needed? | Notes |
|------|-------------|---------------|-------|
| **Infracost** | Parses Terraform plans → monthly cost breakdown | Free API key (not AWS) | ~11.8k stars, JSON output, Terraform only |
| **OpenInfraQuote** | Lightweight cost estimation from TF plan/state | Fully offline | Newer, daily pricing updates, simpler |
| **AWS Pricing Calculator API** | Programmatic estimate creation | AWS account | Official, all services, but not IaC-native |

### Infracost is the clear winner for IaC

```bash
infracost breakdown --path /path/to/terraform --format json
# → totalMonthlyCost, per-resource breakdown, unsupported resource count
```

No AWS creds, structured JSON, works in CI/CD. Limitation: Terraform only.

## Pricing data access

| Tool | What it does | Notes |
|------|-------------|-------|
| **AWS Price List API** | Bulk pricing data (JSON/CSV), public endpoint | Bulk API needs no creds, Query API needs creds |
| **Infracost Cloud Pricing API** | GraphQL, 3M+ prices across AWS/Azure/GCP | Free tier, weekly updates |

For non-Terraform estimates (e.g., agent recommending services without IaC), the Pricing API + custom logic is the fallback.

## Post-deploy optimization (secondary need)

| Tool | What it does | Notes |
|------|-------------|-------|
| **Cloud Custodian** (CNCF) | Policy-as-code for cost/security/governance | YAML rules, very active |
| **AWS Compute Optimizer** | Right-sizing recommendations for EC2/EBS/Lambda/RDS | Native, JSON via CLI |
| **Komiser** | Multi-cloud resource inspector, cost tracking | 3k+ stars, dashboard + CLI |
| **AWS Doctor** | Terminal cost diagnostics, idle resource detection | Lightweight, Go-based |

## Key takeaways

1. **Infracost covers the "how much will this cost?" question** for Terraform setups. Agent runs it, parses JSON, reports back.
2. **For architecture-stage estimates without IaC**, agent needs AWS Pricing API + its own logic to ballpark costs. This is harder but doable for common services (Lambda invocations, DynamoDB RCU/WCU, S3 storage).
3. **Cost optimization is a different problem** — Cloud Custodian is the most agent-friendly (policy-as-code, YAML-driven, CLI).
4. **Tag enforcement** (from the article's practice #6) maps to Cloud Custodian policies.

## For our scale

At small scale, the main value is:
- "You're about to deploy an RDS db.r5.xlarge — that's ~$350/month. Did you mean db.t3.medium (~$30/month)?"
- Catching accidentally expensive choices, not full FinOps.

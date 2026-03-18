# IAM Policy Validation Tools — Research (2026-02)

Goal: find trustable tools an `aws-security-auditor` agent can delegate to, instead of relying on LLM knowledge alone.

## Most relevant for our agent

### Static / offline (no AWS creds needed)

| Tool | What it does | Agent-friendly? | Notes |
|------|-------------|-----------------|-------|
| **Parliament** (duo-labs) | Lints IAM policies: syntax, wildcards, bad action/resource combos | Python lib + CLI, structured output | ~1.1k stars, 458k weekly downloads |
| **Policy Sentry** (Salesforce) | Generates least-privilege policies from resource ARNs + access levels | CLI `policy_sentry write-policy`, Python lib | Offline IAM docs database, good for "what should this policy look like?" |
| **Checkov** (Bridgecrew) | Static analysis for IaC templates (TF, CFN, K8s), 750+ policies incl IAM | CLI with JSON output | Very active, top IaC scanner |
| **IAM Policy Autopilot** (awslabs) | Analyzes app code (Python, Go, TS) to generate baseline IAM policies | CLI + **MCP server** | New, directly designed for AI agent integration |

### AWS-native (requires creds)

| Tool | What it does | Agent-friendly? | Notes |
|------|-------------|-----------------|-------|
| **IAM Access Analyzer** | Automated-reasoning validation against grammar + best practices + custom checks | `aws accessanalyzer validate-policy` → JSON | Mathematical proof-based, most authoritative |
| **cfn-policy-validator** (awslabs) | Validates IAM policies in CFN templates via Access Analyzer | CLI with exit codes | Also exists for Terraform |
| **IAM Policy Simulator** | Tests policy effects without executing | `aws iam simulate-principal-policy` → JSON | Good for "can role X do action Y?" |

### Comprehensive auditing (requires creds)

| Tool | What it does | Notes |
|------|-------------|-------|
| **Cloudsplaining** (Salesforce) | Risk-prioritized assessment, flags data exfil risks | ~2.1k stars, JSON + HTML output |
| **Prowler** | 576+ AWS checks, compliance frameworks (CIS, NIST, PCI-DSS) | Most widely used OSS cloud security tool |

### Policy generation from usage

| Tool | What it does | Notes |
|------|-------------|-------|
| **IAMLive** (iann0036) | Generates policies from actual API calls (local proxy/monitor) | ~3.3k stars, no AWS creds needed |
| **Access Analyzer Policy Generation** | Generates from CloudTrail (90 days) | AWS-native, requires creds |
| **Repokid** (Netflix) | Auto-removes unused permissions (>90 days) | Production-grade, DynamoDB backend |

## Key takeaways for agent design

1. **Don't validate IAM with LLM alone** — delegate to Parliament (offline) or Access Analyzer (online).
2. **Two-layer approach works well:**
   - Layer 1 (always): Parliament for syntax/lint + Policy Sentry for "what should it look like"
   - Layer 2 (when creds available): Access Analyzer for authoritative validation
3. **IAM Policy Autopilot has MCP support** — designed for AI agent integration, worth investigating first.
4. **Policy Sentry is the "generate correct policy" tool**, Parliament is the "check existing policy" tool. Complementary.
5. **Cloudsplaining + Prowler** are overkill for single-policy review but good for account-wide audits.

## Open questions

- Which tools are pip-installable vs require separate setup?
- Can Parliament + Policy Sentry cover 80% of cases without AWS creds?
- How does IAM Policy Autopilot's MCP server work in practice?

# AWS Reference

Two-layer reference for `/design-aws`. Applied between Design and Diagram phases.

---

## Layer 1: Checklists

### Security Review

#### Prevention

| Concern | What to check | Common mistake |
|---------|---------------|----------------|
| IAM scope | Every policy uses resource-level ARNs, not `*` | Using `*` for actions that support resource scoping |
| Encryption at rest | Every data store has encryption configured | Assuming defaults cover everything (SNS does NOT default to encrypted) |
| Public exposure | No `0.0.0.0/0` on sensitive ports, no `Principal: *` without conditions | RDS `publicly_accessible=true` + open SG |
| Secrets | No hardcoded credentials, passwords use Secrets Manager or `manage_master_user_password` | Passwords in Terraform state via plain `password` field |

#### Detection

| Resource type | Logging to add | Enabled by default? |
|---------------|----------------|---------------------|
| Account-wide | CloudTrail (API audit trail) | Yes (management events only, no S3 delivery) |
| VPC | VPC Flow Logs | No |
| S3 | Server access logging or CloudTrail data events | No |
| RDS | Audit logs, slow query logs (via parameter group) | No |
| Lambda | CloudWatch Logs (via execution role) | Yes (if role has permissions) |
| API Gateway | Access logs, execution logs | No |

#### Data in Transit

- All external endpoints must use HTTPS/TLS
- Internal service-to-service: use VPC endpoints for AWS services instead of public endpoints
- RDS: `require_ssl` parameter, enforce via `rds.force_ssl=1` parameter group
- S3: add `aws:SecureTransport` condition to deny HTTP access

#### Incident Prep

- Can you answer "who did what, when?" — CloudTrail must deliver to S3/CloudWatch
- Can you answer "what's happening now?" — CloudWatch alarms + SNS topic for notifications
- Can you answer "what traffic hit the network?" — VPC Flow Logs

### Monitoring Review

| Service | Metric | Alarm when | Why |
|---------|--------|------------|-----|
| Lambda | Errors | > 0 for 1 min | Silent failures |
| Lambda | Throttles | > 0 for 1 min | Hitting concurrency limit |
| Lambda | Duration | > 80% of timeout | About to start timing out |
| RDS | CPUUtilization | > 80% for 5 min | DB overloaded |
| RDS | FreeStorageSpace | < 20% of allocated | Will run out of disk |
| RDS | DatabaseConnections | > 80% of max | Connection exhaustion |
| DynamoDB | ThrottledRequests | > 0 for 1 min | Capacity exceeded (on-demand auto-scales but has burst limits) |
| SQS | ApproximateAgeOfOldestMessage | > threshold (app-specific) | Queue consumers falling behind |
| SQS | ApproximateNumberOfMessagesVisible | > threshold | Backlog growing |
| API Gateway | 5XXError | > 0 for 1 min | Backend failures reaching users |
| API Gateway | Latency (p99) | > threshold | Performance degradation |

**Rule: every resource in the design should have at least one alarm. If you can't name the alarm, the design is incomplete.**

### Quota & Limits Review

| Service | Default limit | Impact if hit | Action |
|---------|---------------|---------------|--------|
| Lambda | 1,000 concurrent executions (account-wide) | Throttling across all functions | Request increase for production |
| API Gateway (REST) | 10,000 req/s account-wide, 5,000 burst | 429 errors | Set per-stage throttling, request increase |
| API Gateway (HTTP) | 10,000 req/s account-wide | 429 errors | Request increase |
| SQS Standard | Nearly unlimited throughput | N/A | — |
| SQS FIFO | 300 msg/s (3,000 with batching), high-throughput mode up to 70,000 msg/s per queue | Message send failures | Enable high-throughput mode or use Standard |
| DynamoDB on-demand | 40,000 RCU / 40,000 WCU per table (initial) | Throttling on sudden spikes | Pre-warm or use provisioned for predictable load |
| S3 | 3,500 PUT/s, 5,500 GET/s per prefix | 503 SlowDown errors | Distribute across prefixes |
| VPC | 5 VPCs per region, 200 subnets per VPC | Can't create resources | Request increase before deployment |

### Backup Review

| Service | Backup mechanism | Default | Must configure |
|---------|-----------------|---------|----------------|
| RDS | Automated snapshots | 0 days retention (no backups) | Set `backup_retention_period` (1-35 days) |
| RDS | Manual snapshots | N/A | `final_snapshot_identifier` if `skip_final_snapshot=false` |
| DynamoDB | Point-in-time recovery (PITR) | Disabled | Enable explicitly, 35-day recovery window |
| DynamoDB | On-demand backups | N/A | Manual or via AWS Backup |
| S3 | Versioning | Disabled | Enable for recovery from accidental deletes |
| S3 | Cross-region replication | Disabled | Only if DR required (out of v1 scope) |
| EBS | Snapshots | None | Via AWS Backup or manual |
| Secrets Manager | Automatic versioning | Enabled | — |

---

## Layer 2: Precision

### Expert: IAM Policy Evaluation Flow

**Same-account evaluation:**
```
Request arrives
├─ Explicit Deny in ANY policy? → DENY (stop)
├─ SCP allows? (if in Organizations) → No → DENY
├─ Resource-based policy allows? → Yes → ALLOW (resource-based can independently grant)
├─ Permission boundary allows? (if set) → No → DENY
├─ Session policy allows? (if STS session) → No → DENY
└─ Identity-based policy allows? → Yes → ALLOW, No → DENY
```

Key insight: **Same-account resource-based policies can independently grant access** without identity-based policy.

**Cross-account evaluation:**
```
Request arrives → evaluated in BOTH accounts independently

Trusted account (caller's):
├─ Explicit Deny? → DENY
├─ SCP allows? → No → DENY
├─ Permission boundary allows? → No → DENY
└─ Identity-based policy allows? → No → DENY

Trusting account (resource's):
├─ Explicit Deny? → DENY
├─ RCP allows? (if in Organizations) → No → DENY
└─ Resource-based policy allows? → No → DENY

ALLOW only if BOTH accounts return Allow
```

Key insight: **Cross-account always requires both sides to allow.** Resource-based policy alone is NOT sufficient (unlike same-account).

### Expert: Compute Cost Crossover

Prices for us-east-1, x86, March 2026. Lambda at 128MB, 200ms avg. Fargate at 0.25 vCPU / 0.5 GB. EC2 t3.micro on-demand.

| | Lambda | Fargate | EC2 (t3.micro) |
|---|---|---|---|
| **Pricing unit** | $0.20/1M req + $0.0000166667/GB-s | $0.04048/vCPU-hr + $0.004445/GB-hr | $0.0104/hr |
| **1K req/day** (~30K/mo) | ~$0.01/mo | ~$29/mo (always-on) | ~$7.50/mo |
| **10K req/day** (~300K/mo) | ~$0.07/mo | ~$29/mo | ~$7.50/mo |
| **100K req/day** (~3M/mo) | ~$0.67/mo | ~$29/mo | ~$7.50/mo |
| **1M req/day** (~30M/mo) | ~$6.65/mo | ~$29/mo | ~$7.50/mo |
| **10M req/day** (~300M/mo) | ~$66/mo | ~$29/mo | ~$7.50/mo |

**Crossover**: Lambda cheaper below ~5M req/day for lightweight functions. Above that, always-on compute wins. For sustained CPU-heavy workloads, the crossover is much earlier.

Caveats: Fargate/EC2 assume single task/instance handling all requests (unrealistic at high scale). Lambda scales automatically. Real comparison depends on concurrency and compute needs per request.

### Expert: API Gateway REST (v1) vs HTTP (v2)

Only features where they differ — both support custom domains, IAM auth, Cognito, Lambda authorizer, Lambda/HTTP integrations, CloudWatch metrics, access logs.

| Feature | REST (v1) | HTTP (v2) |
|---------|-----------|-----------|
| **Pricing** | $3.50/M requests | $1.00/M requests |
| API keys / usage plans | Yes | No |
| Per-client throttling | Yes | No |
| Request validation | Yes | No |
| Request/response body transformation (VTL) | Yes | No |
| Caching | Yes | No |
| WAF integration | Yes | No |
| Resource policies | Yes | No |
| Canary deployments | Yes | No |
| Private endpoints | Yes | No |
| Edge-optimized endpoints | Yes | No |
| X-Ray tracing | Yes | No |
| Execution logs | Yes | No |
| Mock integrations | Yes | No |
| Native JWT authorizer | No | Yes |
| Automatic deployments | No | Yes |
| AWS Cloud Map integration | No | Yes |

**Decision rule: default to HTTP (v2) unless you need a feature from the "REST only" column.** Most common reasons to use REST: WAF, caching, request validation, API keys.

### Expert: Minimum Monthly Costs

"What does it cost to just turn this on?" — us-east-1, March 2026.

| Service | Minimum config | Approx. monthly cost | Notes |
|---------|---------------|---------------------|-------|
| Lambda | On-demand, no invocations | $0 | Free tier: 1M requests + 400K GB-s/mo |
| API Gateway (HTTP v2) | Deployed, no traffic | $0 | Pay per request only |
| API Gateway (REST v1) | Deployed, no traffic | $0 | Pay per request only |
| DynamoDB | On-demand, no traffic | $0 | Pay per request + storage |
| SQS | Standard queue, no messages | $0 | Free tier: 1M requests/mo |
| SNS | Topic, no messages | $0 | Free tier: 1M publishes/mo |
| S3 | Bucket, no objects | $0 | Pay per storage + requests |
| RDS (Postgres) | db.t4g.micro, single-AZ | ~$12-15/mo | + $0.115/GB-mo storage |
| RDS (Aurora Serverless v2) | 0.5 ACU minimum | ~$43/mo | Does NOT scale to zero |
| OpenSearch | t3.small.search, 1 node | ~$26/mo | + EBS storage |
| ElastiCache (Redis) | cache.t4g.micro | ~$12/mo | |
| EC2 | t3.micro, on-demand | ~$7.50/mo | + EBS storage |
| NAT Gateway | Single AZ | ~$32/mo | + $0.045/GB processed |
| Fargate | 0.25 vCPU / 0.5 GB, always-on | ~$9/mo | Per task |
| CloudTrail | Management events to S3 | $0 | First trail free; data events cost extra |
| VPC | VPC + subnets | $0 | VPC itself is free |

### Activation: IAM

**Lambda ARN semantics in policies:**
Unqualified ARN (`function:name`) matches invocations to `$LATEST` only. Qualified ARN (`function:name:alias` or `function:name:version`) matches that specific alias/version. A policy on the unqualified ARN does NOT cover qualified invocations — they are distinct resources. Use `function:name:*` to match all versions and aliases.

**MFA condition key absent-key handling:**
`aws:MultiFactorAuthPresent` is absent (not "false") for long-term credentials. A Deny with `"Bool": {"aws:MultiFactorAuthPresent": "false"}` does NOT deny long-term key access. Use `"BoolIfExists"` or combine with `"Null"` condition: `{"Null": {"aws:MultiFactorAuthPresent": "true"}}`.

**KMS permission mapping per service:**
- Services that write encrypted data need `kms:GenerateDataKey` (envelope encryption write-side)
- Services that read encrypted data need `kms:Decrypt` (envelope encryption read-side)
- `kms:Encrypt` is rarely needed — only for direct KMS API encryption of small data
- S3 with SSE-KMS: write needs `kms:GenerateDataKey`, read needs `kms:Decrypt`
- SQS with SSE-KMS: both send and receive need `kms:Decrypt` AND `kms:GenerateDataKey`

**Service-specific KMS requirements (non-obvious):**
SQS requires both `kms:GenerateDataKey` and `kms:Decrypt` for BOTH producers and consumers because SQS re-encrypts messages internally. Unlike S3 where read-only access needs only `kms:Decrypt`.

### Activation: Service Selection

**SQS FIFO throughput:** Base: 300 msg/s (3,000 with batching). High-throughput FIFO mode: up to 70,000 msg/s per queue when using distinct message group IDs. Must be enabled explicitly.

**Aurora Serverless v2 minimum cost:** 0.5 ACU minimum (does NOT scale to zero — that was v1, now deprecated). At ~$0.12/ACU-hour, minimum is ~$43/mo. Compare: db.t4g.micro RDS is ~$12-15/mo. Aurora Serverless v2 only saves money over provisioned when traffic is bursty enough to justify the premium.

**Lambda cold start benchmarks (approximate, basic function, no VPC):**
Python/Node.js: 200-500ms. Go/Rust: 50-200ms. Java (plain): 800ms-3s. Java (SnapStart): 200-400ms. .NET: 400ms-1s. VPC adds ~1s (Hyperplane ENI, post-2019). Provisioned Concurrency eliminates cold starts.

**DAX vs ElastiCache:** DAX is DynamoDB-specific read-through cache (microsecond reads). Only useful for DynamoDB read latency optimization. ElastiCache (Redis) is general-purpose. At small scale, neither is usually needed — DynamoDB is already single-digit milliseconds.

### Activation: Security

**SQS vs SNS encryption:** SQS defaults to SSE-SQS (enabled since 2023, free, transparent). SNS does NOT encrypt at rest by default — must explicitly enable SSE-KMS.

**Lambda function URL auth:** Auth type `NONE` = fully public, no authentication. Auth type `AWS_IAM` = requires SigV4 signature. With `NONE`, the function URL bypasses resource-based policy principal checks — restrict via condition keys (e.g., `aws:SourceIp`) or put CloudFront + WAF in front.

**API Gateway throttling defaults:** REST: 10,000 req/s steady-state, 5,000 burst (account-wide across all REST APIs in the region). HTTP: 10,000 req/s (account-wide). These are soft limits. Set per-stage and per-route throttling to protect individual APIs.

**API Gateway WAF:** REST (v1) supports WAF directly. HTTP (v2) does NOT — put CloudFront in front for WAF protection. Common reason to choose REST over HTTP.

**VPC Flow Log exclusions:** Flow logs do NOT capture: DNS traffic to Route 53 Resolver, DHCP traffic, traffic to instance metadata (169.254.169.254), traffic to Amazon Time Sync Service (169.254.169.123), DHCP relay, mirrored traffic, traffic to VPC router reserved IP.

### Activation: Terraform

**`prevent_destroy` removal edge case:** If you remove the entire resource block from config, `prevent_destroy` no longer applies — Terraform plans the destroy and the lifecycle block is gone. Only protects against changes that would destroy the resource while the block is still in config.

**RDS `apply_immediately`:** Default is `false`. Without it, these changes defer to maintenance window: instance class, storage size, engine version, parameter group, multi-AZ. Terraform shows the change as applied but the actual modification hasn't happened yet — creates state drift until the maintenance window runs.

**RDS `manage_master_user_password`:** Set `manage_master_user_password = true` to let RDS manage the password via Secrets Manager. Terraform never sees the actual password — cleanest approach for avoiding passwords in state. Available in AWS provider v5+.

**Security group default egress:** Defining ANY inline `egress` block on `aws_security_group` removes the default "allow all outbound" rule and replaces with only what you specified. If you only add inline `ingress` blocks without an `egress` block, outbound is preserved. With separate `aws_security_group_rule` resources (recommended), the default egress is preserved.

**`default_tags` perpetual diff:** Using `default_tags` in the provider block and also specifying the same tag key on a resource causes perpetual plan diffs. Fixed in AWS provider ~v4.x but can resurface with specific resource types. Workaround: don't duplicate tag keys between provider `default_tags` and resource-level `tags`.

**API Gateway deployment triggers:** Changing API Gateway resources/methods/integrations does NOT automatically trigger a new deployment. The `aws_api_gateway_deployment` resource only redeploys when its own config changes. Fix: use `triggers` argument with a hash of the API definition: `triggers = { redeployment = sha1(jsonencode(aws_api_gateway_rest_api.this.body)) }`.

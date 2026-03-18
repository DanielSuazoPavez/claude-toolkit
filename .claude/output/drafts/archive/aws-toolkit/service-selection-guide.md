# Service Selection Decision Guide — Placeholder (2026-02)

Gap: IAM and cost drafts cover "validate and price what you chose" but not "how to choose."
This guide should be the opinionated, small-scale decision framework for the `aws-architect` agent.

## Principles

- Default to the simpler option. Complexity must justify itself.
- Optimize for small-to-medium scale. Not Netflix.
- "Do I actually need this?" over "what's the best practice at scale?"

## Decision areas to cover

### Compute
- Lambda vs ECS Fargate vs EC2
- When Lambda's limits bite (15min timeout, cold starts, payload size)
- When ECS is worth the operational overhead

### Orchestration
- Single Lambda vs Step Functions vs EventBridge rules
- "Just chain Lambdas" vs "you actually need state management"
- When Step Functions complexity pays off (retries, parallel branches, human approval)

### Messaging / Event-driven
- SQS vs SNS vs EventBridge vs Kinesis
- "I just need async" → SQS
- "I need fan-out" → SNS + SQS
- "I need event routing with rules" → EventBridge
- "I need ordered, high-throughput streaming" → Kinesis (probably don't at small scale)

### Database
- DynamoDB vs RDS (Postgres) vs Aurora Serverless
- Access pattern driven: key-value → DynamoDB, relational/ad-hoc queries → RDS
- Cost cliffs: DynamoDB on-demand vs provisioned, Aurora Serverless v2 minimum cost
- RDS Proxy: when and why

### Storage
- S3 tiers: when to use Standard vs IA vs Glacier
- EFS vs EBS vs S3 for Lambda/ECS

### API layer
- API Gateway REST vs HTTP vs ALB
- HTTP API covers 90% of cases at lower cost
- When you actually need REST API features (request validation, caching, usage plans)

### Auth
- Cognito vs custom auth
- When Cognito's limitations become painful

## Format TBD

Could be:
- Decision tree (if X → use Y)
- Comparison tables per category
- "Start here, escalate when" progressive complexity guide

The "start simple, escalate when" framing probably fits best for small-scale bias.

## Source

Build from experience, not from AWS docs. The value is in the opinions, not the feature lists.

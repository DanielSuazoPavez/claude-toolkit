# AWS Architecture Diagrams (Mermaid architecture-beta)

## Syntax Reference

| Element | Syntax | Notes |
|---------|--------|-------|
| Group | `group id(icon)[Label]` | Container for services; can nest via `in parent` |
| Service | `service id(icon)[Label] in group` | `in group` optional for top-level services |
| Edge | `A:R -- L:B` | Positions required: `T`, `B`, `L`, `R` |
| Directional edge | `A:R --> L:B` | Arrow shows data/request direction |
| Reverse edge | `A:R <-- L:B` | Arrow points from B to A |
| Group boundary edge | `svc{group}:R --> L:other` | `{group}` modifier on a service, NOT on group ID |
| Junction | `junction id in group` | 4-way edge splitter, no icon/label |

## Built-in Icons

Only 5 icons render on GitHub. Custom icon packs (Iconify) show blue "?" boxes.

`cloud` · `database` · `disk` · `internet` · `server`

## AWS Service → Icon Mapping

Icon = category, label = specific service.

| Icon | AWS Services |
|------|-------------|
| `server` | Lambda, EC2, ECS/Fargate, SQS, SNS, Step Functions |
| `database` | RDS, DynamoDB, ElastiCache, OpenSearch, Redshift |
| `disk` | S3, EBS, EFS |
| `cloud` | VPC, CloudFront, CloudWatch, IAM, Secrets Manager |
| `internet` | ALB/NLB, API Gateway, Route 53, NAT Gateway |

## Worked Example: API Gateway → Lambda

API Gateway receives requests and invokes Lambda. Simplest multi-resource pattern.

```mermaid
architecture-beta
    group api(cloud)[API Layer]

    service gw(internet)[API Gateway] in api
    service fn(server)[Lambda Handler] in api

    gw:R --> L:fn
```

## Worked Example: Scheduled Cleanup Pipeline

EventBridge triggers Lambda on a schedule. Lambda scans DynamoDB for expired items and archives to S3. Shows groups, multiple service types, fan-out edges.

```mermaid
architecture-beta
    group trigger(cloud)[Scheduling]
    group processing(cloud)[Processing]
    group storage(cloud)[Storage]

    service eb(server)[EventBridge Cron] in trigger
    service fn(server)[Lambda Cleanup] in processing
    service ddb(database)[DynamoDB Records] in storage
    service s3(disk)[S3 Archive] in storage

    eb:R --> L:fn
    fn:R --> L:ddb
    fn:B --> T:s3
```

## Worked Example: S3 Ingest to OpenSearch

S3 notification triggers Lambda inside a VPC, which indexes documents in OpenSearch. Shows VPC grouping with nested subnets.

```mermaid
architecture-beta
    group vpc(cloud)[VPC]
    group public(cloud)[Public Subnet] in vpc
    group private(cloud)[Private Subnet] in vpc

    service s3(disk)[S3 Documents]
    service fn(server)[Lambda Indexer] in public
    service os(database)[OpenSearch Cluster] in private

    s3:R --> L:fn
    fn:R --> L:os
```

## Rendering Compatibility

| Renderer | Built-in icons | Custom icons (Iconify) |
|----------|---------------|----------------------|
| GitHub | Yes | No — blue "?" boxes |
| Mermaid Live Editor | Yes | Yes |
| mermaid-cli | Yes | Yes |
| VS Code | Depends on extension | Depends on extension |

**Rule:** Always use built-in icons when targeting GitHub or mixed renderers.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Edges without positions: `A -- B` | Always specify: `A:R -- L:B` |
| Service declared before its group | Declare `group` first, then `service ... in group` |
| Custom icons for GitHub targets | Use only: `cloud`, `database`, `disk`, `internet`, `server` |
| `{group}` modifier on group ID | Apply `{group}` to a service within the group, not the group itself |
| Colons in labels: `[Lambda: Handler]` | Colons conflict with edge syntax — use `[Lambda Handler]` or `[Lambda - Handler]` |
| Too many services (>12) in one diagram | Split by bounded context — one diagram per subsystem |

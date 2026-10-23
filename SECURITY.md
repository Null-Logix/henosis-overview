# Security policy

Henosis is unreleased pre-release alpha software. Do not use it as the sole security boundary for an exposed production system.

## Reporting a vulnerability

Send a private report to [security@nulllogix.com](mailto:security@nulllogix.com). Include the affected version, a minimal reproduction, impact, and any safe mitigation. Do not post exploit details, credentials, private endpoints, or customer data in a public issue.

Use [support@nulllogix.com](mailto:support@nulllogix.com) for non-sensitive operational support.

## Deployment boundary

Local mode is loopback-only by default and is not a remote multi-user deployment. Its single-operator quota and rate-limit counters use a dedicated protected SQLite database, survive process restarts, and fail startup closed when that state cannot be opened safely. Production needs authenticated ingress, TLS termination, source-aware login rate limiting at the ingress, managed PostgreSQL, protected persistent storage, backups, monitoring, an independent audit witness, and the private `phylaxd` credential broker.

Machine credentials are tenant-bound, scoped, revocable, and checked against live organization membership on every request. Production approvals require a different administrator principal from the request initiator. Operator access tokens expire after at most 15 minutes, and logging out revokes the durable refresh family immediately.

Every public dispatch requires an idempotency key scoped to the authenticated tenant and principal. A completed request replays only its stored, output-filtered result. Reusing a key with different request content fails as a conflict. If execution may have occurred but a safe completion cannot be established, the request is marked indeterminate and is never executed automatically on retry; only a live human owner or administrator can conclude it, with an evidence digest recorded in the audit chain.

Model-supplied paths for the built-in file tools are capability-confined to the task root. `bash` is a separate capability and runs with the operating-system permissions of the Henosis process; grant it independently and add process or container isolation appropriate to your threat model.

## Supply chain

The private build pipeline produces `SHA256SUMS`, SPDX SBOMs, and SLSA provenance signed through GitHub OIDC for every build. When releases are published here, verify the checksum of any archive before installing it.

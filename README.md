<p align="center">
  <img src="docs/assets/banner.svg" alt="Henosis persistent agent runtime banner" width="100%" />
</p>

# Henosis

Governed infrastructure for persistent AI agents. This repository is the public
project page: what Henosis is, how its trust boundary works, and what is not
finished. The source code is private and nothing is distributed yet.

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/license-PolyForm--Noncommercial--1.0.0-7b5740)](LICENSE)
[![Language: Rust](https://img.shields.io/badge/built%20with-Rust-b7410e?logo=rust)](#trust-model)

[Limitations](docs/limitations.md) · [Security](SECURITY.md) · [License](LICENSE)

Henosis gives agents a durable place to work across sessions while operators
retain control of identity, policy, approvals, credentials, execution, and
audit. Rift rooms provide the human coordination surface. A headless Rust
control plane owns the trust boundary.

Every request is authenticated, checked against current membership and policy,
bound to any approval it needs, executed under limits, filtered on the way out,
and committed to the audit record before control returns.

> **Pre-release alpha.** Local mode binds to loopback and supports one
> operator. Read the [limitations ledger](docs/limitations.md) before any
> network exposure.

## Availability

Henosis is not distributed yet. It has not been through its first round of
operator testing, and no release is published here or anywhere else. The
private build pipeline already produces signed native archives for Linux,
macOS, and Windows with SPDX SBOMs and SLSA provenance, and those will appear
in this repository when the first tested release is ready.

Evaluators, auditors, and prospective customers can request an evaluation build
or time-limited source access by writing to
[support@syntheos.dev](mailto:support@syntheos.dev) with the purpose and the
GitHub account to grant.

## Trust model

| Boundary | Henosis behavior |
| --- | --- |
| Identity | Human and machine credentials are tenant-bound, scoped, revocable, and checked against live membership. |
| Approval | Durable, one-use approvals bind to the request, principal, tenant, policy revision, and expiry. Production requires a different administrator from the requester. |
| Execution | The Wasmtime Component Model host enforces fuel, memory, time, output, and network limits. Third-party extension loading remains disconnected. |
| Filesystem | Built-in file tools accept task-root-relative paths and reject traversal and symlink escapes. `bash` is a separate capability with the operating-system access of the Henosis process. |
| Credentials | Tools request named broker operations without receiving raw secrets. Production uses the external `phylaxd` broker. |
| Audit | Henosis writes synchronous hash-chained records and supports an independent witness. Production requires off-host intent and outcome receipts. A blocked stream can be restored only by exact receipt-verified head recovery. |

```text
operator or agent
        |
        v
identity -> policy -> approval -> bounded execution -> filtered result
                                      |
                                      v
                               audit and witness
```

Model providers sit behind a shared interface. Capability authorization stays
on the server, so switching models does not move the trust boundary into a
prompt or client application.

## Deployment boundary

| Mode | Contract |
| --- | --- |
| Local | Loopback-only, one operator, SQLite state, embedded compatibility policy, and restart-durable quota and rate-limit counters. The signed compatibility room authorizes `henosis.probe` only. |
| Production | Managed PostgreSQL, TLS and authenticated ingress, protected storage, backups, source-aware login limits, an independent audit witness, and private `phylaxd` access. |

The Pistis policy service and the `phylaxd` credential broker are separate
private services and do not ship here. Production capability requests fail
closed until a deployment supplies trusted room state from Pistis.

## Security and support

Send vulnerability reports to [security@syntheos.dev](mailto:security@syntheos.dev).
Send non-sensitive support requests to [support@syntheos.dev](mailto:support@syntheos.dev).
Do not put credentials, private endpoints, or exploit details in a public issue.

## License

Henosis, including every document in this repository, is licensed
under the [PolyForm Noncommercial License 1.0.0](LICENSE). Personal, hobby,
research, and other noncommercial use is permitted. Any commercial use,
including selling, reselling, hosting, bundling, or otherwise earning revenue
from this software, requires a separate written commercial license. Contact
[support@syntheos.dev](mailto:support@syntheos.dev).

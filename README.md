<p align="center">
  <img src="docs/assets/banner.svg" alt="Henosis persistent agent runtime banner" width="100%" />
</p>

# Henosis

Governed infrastructure for persistent AI agents. This repository is the public
distribution point: signed release builds, SBOMs, provenance attestations, and
documentation. The source code is private.

[![Release](https://img.shields.io/github/v/release/Null-Logix/henosis-releases?include_prereleases&sort=semver&color=f05a42)](https://github.com/Null-Logix/henosis-releases/releases)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/license-PolyForm--Noncommercial--1.0.0-7b5740)](LICENSE)
[![Language: Rust](https://img.shields.io/badge/built%20with-Rust-b7410e?logo=rust)](#what-ships)

[Releases](https://github.com/Null-Logix/henosis-releases/releases) · [Limitations](docs/limitations.md) · [Security](SECURITY.md) · [License](LICENSE)

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

## What ships

| Asset | Contents |
| --- | --- |
| `henosis-<version>-<target>.tar.gz` / `.zip` | Native `henosis` and `crucible` binaries for Linux (x86-64, aarch64, musl), macOS (Intel, Apple silicon), and Windows (x86-64). |
| `SHA256SUMS` | Checksums for every native archive. |
| `*-native-provenance.sigstore.json` | SLSA build provenance for the native archives, signed through GitHub OIDC by the private build workflow. |
| `*-native-sbom.sigstore.json`, `*-source.spdx.json` | SPDX software bills of materials for the binaries and the source tree they were built from. |
| `*-container-*.json`, `*-container-image.env` | Provenance, SBOM, and image reference for the container build. |

Desktop installers (Linux deb and AppImage, macOS DMG, Windows NSIS) arrive
with the first beta release.

## Install

The installers select the host platform, verify `SHA256SUMS`, install into the
current user account, run `henosis init --quick`, and restore the previous
version if initialization fails. Both pin the installer script to a reviewed
commit and take the release version as a separate input.

Linux or macOS:

```sh
curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
  https://raw.githubusercontent.com/Null-Logix/henosis-releases/main/install.sh \
  | sh -s -- --version v0.1.0-alpha.6 --experience cli
```

Windows PowerShell:

```powershell
$installer = Join-Path ([IO.Path]::GetTempPath()) "henosis-install-$([guid]::NewGuid().ToString('N')).ps1"
try {
  irm 'https://raw.githubusercontent.com/Null-Logix/henosis-releases/main/install.ps1' -OutFile $installer
  $powerShell = (Get-Process -Id $PID).Path
  & $powerShell -NoProfile -ExecutionPolicy Bypass -File $installer -Version 'v0.1.0-alpha.6' -Experience 'cli'
  if ($LASTEXITCODE -ne 0) { throw "Henosis installer exited with code $LASTEXITCODE" }
} finally {
  Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
}
```

Start the loopback service and confirm it is ready:

```sh
$HOME/.local/bin/henosis serve
curl http://127.0.0.1:8088/health
```

The first boot writes a private owner token under `HENOSIS_HOME`. Create a
scoped machine token for an agent and send a probe dispatch:

```sh
export HENOSIS_AGENT_TOKEN="$($HOME/.local/bin/henosis token create first-agent --token-only)"
curl --fail-with-body http://127.0.0.1:8088/api/v1/dispatch \
  -H "Authorization: Bearer $HENOSIS_AGENT_TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Henosis-Idempotency-Key: first-agent-probe-1" \
  --data '{"tool":"henosis","action":"probe","args":{},"context":{"room":"!henosis-local:loopback"}}'
```

Repeating the same key and request returns the stored filtered result. Reusing
the key with different content returns a conflict. An action that needs
approval returns `202 Accepted`; approve it with
`henosis approvals approve <approval-id>` and repeat the request with the
original key and `X-Henosis-Approval-Id`.

Update to an explicit release tag with `henosis update --version <tag>`.
Removal is reversible: `henosis uninstall` reports the exact paths, and
`henosis uninstall --confirm-quarantine` moves only the marked binaries into a
same-directory quarantine while operator configuration and databases stay in
place.

## Verify a release

Check the archive you downloaded against `SHA256SUMS`:

```sh
grep -F '  henosis-0.1.0-alpha.6-x86_64-unknown-linux-musl.tar.gz' SHA256SUMS \
  | sha256sum --check
```

The provenance and SBOM bundles in each release are the original signed
artifacts from the private build repository, re-hosted here unchanged. Their
subjects match the archive digests in `SHA256SUMS`. Verifying them with
`gh attestation verify` requires read access to the build repository, which is
granted to evaluators on request through
[support@syntheos.dev](mailto:support@syntheos.dev).

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

## Source access

Henosis source is private. Evaluators, auditors, and prospective customers can
request time-limited read access by writing to
[support@syntheos.dev](mailto:support@syntheos.dev) with the purpose and the
GitHub account to grant.

## Security and support

Send vulnerability reports to [security@syntheos.dev](mailto:security@syntheos.dev).
Send non-sensitive support requests to [support@syntheos.dev](mailto:support@syntheos.dev).
Do not put credentials, private endpoints, or exploit details in a public issue.

## License

Henosis, including every binary and document in this repository, is licensed
under the [PolyForm Noncommercial License 1.0.0](LICENSE). Personal, hobby,
research, and other noncommercial use is permitted. Any commercial use,
including selling, reselling, hosting, bundling, or otherwise earning revenue
from this software, requires a separate written commercial license. Contact
[support@syntheos.dev](mailto:support@syntheos.dev).

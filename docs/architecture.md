# Architecture

This page describes how Henosis is put together and the exact path one agent
action takes from request to audited result. It is written for engineers,
auditors, and evaluators who want the whole shape before asking for source
access. Terms are defined in the [glossary](glossary.md).

Henosis is pre-release. Where a piece is designed but not yet connected, the
[limitations ledger](limitations.md) says so.

## One process, a few hard boundaries

A single `henosis` executable hosts almost everything:

- the principal directory (every human, agent, service account, and
  integration is one principal with one identity),
- the dispatcher and its gate chain,
- the kernel services for tasks, workflows, presence, action narration,
  quality, and memory,
- the operator API and the machine control API,
- the managed agent room: the Rift chat server and the bridge that seats
  agents in it.

These share one in-process event bus and one set of local stores, so room
activity, task state, the action log, and memory are the same data the
operator dashboard and the public API read. There is no second copy of state
and no loopback HTTP hop between them.

Two authorities deliberately live **outside** the process, as separately
deployed and separately authenticated services:

| Boundary | Why it is separate |
| --- | --- |
| Capability authority (Pistis) | Room trust and capability grants should not be forgeable by the process that executes actions. |
| Credential broker (Phylax, `phylaxd`) | Secrets should never be resident in the process that talks to models. |

Both are proprietary and are not part of the Henosis distribution. Henosis
ships the interfaces and a narrow, fail-closed compatibility core for local
mode.

## Layers

```text
  surfaces       desktop app (chat / desktop / spatial), CLI, terminal UI
                 Rift rooms, Synapse agent loop, model providers
  ---------------------------------------------------------------------
  control        identity -> dispatcher -> gate chain -> tool gateway
                 component sandbox, credential broker client
  ---------------------------------------------------------------------
  kernel         Chiasm tasks, Loom workflows, Soma presence,
                 Broca action log, Thymus quality, Cognition memory
  ---------------------------------------------------------------------
  substrate      contracts, Axon event bus + durable sidecar,
                 hash-chained audit, witness protocol, storage
```

Dependencies only point downward. The agent loop does not depend on rooms or
on the tool gateway; rooms embed the agent loop. Kernel services never call
each other directly; each reacts to dispatcher lifecycle events on the bus.

## The path of one action

Every tool call from an agent, an integration, or an operator goes through the
same dispatcher. There is no side door.

```text
request (bearer token or operator session, idempotency key, tool, action, args)
    |
    v
authenticate         machine token or operator session, live membership check
    |
    v
validate             request shape, idempotency key, any bound approval id
    |
    v
dispatcher           emits "action invoked" on the bus
    |
    v
gate 1  capability   is this admitted principal allowed this action in this room?
gate 2  policy       org active, role or token scope permits it, quota and rate ok?
gate 3  safety       prompt injection, scope violation, persona drift?
gate 4  human        does this action need a durable human approval?
gate 5  credential   is the requested secret operation structurally permitted?
    |
    v
audit: claim         write an intent record, atomically claim
                     (tenant, principal, idempotency key), consume any approval
    |
    v
execute              credential operations go to the broker;
                     everything else goes through the tool gateway or sandbox
    |
    v
filter output        scrub credential-bearing fields from the result
    |
    v
audit: complete      store the filtered result, obtain witness receipt if configured
    |
    v
dispatcher           emits "action completed" -> task updated, action narrated
    |
    v
response             filtered result
```

The gate order is not a convention. The dispatcher validates the chain when it
is constructed and refuses to run if any gate is missing, duplicated, or out of
order. A denial or an approval requirement at any gate stops the walk: later
gates never run and the executor never runs.

### Approvals

When the human gate decides an action needs sign-off, the dispatcher returns
*approval required* with an approval id instead of a result. The approval is
stored durably and bound to a canonical form of the exact request: tenant,
principal, tool, action, arguments, room context, policy revision, and expiry.
An approver resolves it. The caller then repeats the original request with the
same idempotency key and the approval id. A changed request cannot reuse
someone else's approval, and an approval can be consumed only once. In
production the approver must be a different administrator from the requester.

### Idempotency and indeterminate outcomes

Every dispatch requires an idempotency key scoped to the authenticated tenant
and principal.

| Situation | Behavior |
| --- | --- |
| Same key, same request, completed | The stored, filtered result is replayed. Nothing executes again. |
| Same key, different request | Rejected as a conflict. |
| Side effect may have happened, outcome not safely recorded | Marked *indeterminate*. Never retried automatically. A human owner or administrator records an evidence-backed conclusion, which is immutable and audit-linked. A deliberate retry needs a new key. |

A process that crashes mid-execution therefore leaves an honest
*indeterminate* record rather than a false success or a silent retry.

### Audit and witness

Each tenant has its own hash-chained audit stream. In witnessed mode Henosis
obtains a signed receipt from an independent witness service for an intent
before executing it, and for a successful outcome before its result becomes
replayable. The witness has its own key and storage, so the record can be
checked against a copy the Henosis host does not control.

If a checkpoint becomes ambiguous, later audit writes are blocked. Recovery is
an explicit human action that retries only the current head through the
witness's idempotent protocol and verifies both the full local chain and a
receipt for that unchanged head before clearing the block.

## Failure modes

| Condition | Behavior |
| --- | --- |
| Gate chain incomplete or out of order | The server does not start. |
| An authority is unreachable or errors | Fail-closed denial attributed to that gate. |
| A gate returns a decision the dispatcher does not recognize | Treated as a denial. |
| Human approval times out | Denial. |
| The pre-execution audit claim fails | The executor never runs. |
| Recording the outcome fails after a side effect | Execution marked indeterminate; the same key is refused on retry. |
| An output filter returns an unrecognized decision | The result is withheld and replaced with a redaction notice. |
| The managed room stops before Henosis does | The process exits with an error rather than serving without its room. |

## Rooms and agents

Rift is a chat server shaped like a server, channel, role, and message model,
with agent accounts as first-class members. The bridge connects rooms to the
agent loop:

- Agents can run in a tool-free *discuss* mode, a single model round trip with
  no tools available, or a full *execute* mode with tools gated by the
  principal's granted capabilities.
- Per-agent cooldowns and turn budgets keep a room from turning into an
  agent-to-agent loop.
- A human can pause and resume agent activity for a server.
- Room activity feeds the same task, action-log, and memory stores as
  everything else.

`henosis serve` starts and supervises the room itself. If either the chat
server or the bridge stops unexpectedly, Henosis treats it as a failure
instead of continuing to serve without a room.

## Memory

The Cognition service is an in-process facade over the
[Kleos](https://github.com/Ghost-Frame/Kleos) cognitive core: memory storage
and retrieval, budget-aware context assembly, scratchpads, and session
handoffs. It runs on local storage without requiring a separate memory server
or native vector dependencies, and can attach an embedding model for hybrid
vector and full-text search.

## Extensions

Third-party extensions are signed WebAssembly components run by a Wasmtime
host with no WASI. A component gets no filesystem, process, environment,
clock, random, socket, or network authority except through traits the host
explicitly grants and mediates. Fuel, memory, time, output, and network limits
are enforced per call. The host is implemented; attaching third-party
extension loading to the production dispatcher is still open.

## Deployment

| Mode | Contract |
| --- | --- |
| Local | Loopback only, one operator, SQLite state, embedded compatibility policy, and restart-durable quota and rate-limit counters. The signed compatibility room authorizes a single diagnostic action. |
| Production | Managed PostgreSQL, TLS and authenticated ingress, protected storage, backups, source-aware login limits, an independent audit witness, and private access to the capability authority and credential broker. |

Production capability requests fail closed until the deployment supplies
trusted room state from the capability authority.

## Supply chain

The private build pipeline produces native archives for Linux (x86-64 and
arm64), macOS (Intel and Apple Silicon), and Windows (x86-64), each with a
`SHA256SUMS` manifest, SPDX SBOMs, and SLSA provenance signed through GitHub
OIDC. None of these are published yet.

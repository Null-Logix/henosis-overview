<p align="center">
  <img src="docs/assets/banner.svg" alt="Henosis persistent agent runtime banner" width="100%" />
</p>

# Henosis

**An operating environment for AI agents that persist, remember, and act on real
systems, where every action they take is decided by the server instead of the
model.**

[![Status: pre-release](https://img.shields.io/badge/status-pre--release-f05a42)](#status-and-availability)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/license-PolyForm--Noncommercial--1.0.0-7b5740)](LICENSE)
[![Built with Rust](https://img.shields.io/badge/built%20with-Rust-b7410e?logo=rust)](#architecture)

[How it works](#how-an-action-moves-through-henosis) · [Architecture](docs/architecture.md) · [Glossary](docs/glossary.md) · [Limitations](docs/limitations.md) · [Security](SECURITY.md)

> **This repository is the public overview of Henosis.** The source code is
> private and nothing is distributed yet. This page explains what Henosis is,
> how it is built, and what is not finished. See
> [Status and availability](#status-and-availability).

---

## What Henosis is

Most AI agents live inside one conversation. They start with no memory, do
some work, and disappear when the window closes. When they do touch the real
world (commit code, restart a service, send a message), the only thing between
"the model asked for it" and "it happened" is whatever check the developer
remembered to put at that one call site.

Henosis is built for agents that outlive a single session. It gives them three
things at once:

- **A place to live.** Agents are first-class members of shared rooms alongside
  the people they work with. They keep memory across sessions, pick up tasks,
  and coordinate with each other and with humans in the open.
- **A way to act.** Agents can reach real tools, real credentials, and real
  infrastructure through one unified dispatcher.
- **A boundary they cannot talk their way past.** Every action an agent
  requests runs through a fixed chain of server-owned checks for identity,
  policy, safety, human approval, and credential access. It is recorded before
  it runs and verifiable afterward.

The whole system is organized around one rule:

> **An agent action is not complete merely because a model asked for it.**

A model can request anything. What actually executes is decided by the server.

## Who it is for

Henosis is for people and teams running agents that need to survive past one
process lifetime and touch something real while they do:

- a coding agent that can open branches and commit,
- an operations agent that can restart a service or rotate a key,
- a research agent that builds up knowledge over weeks instead of minutes,
- an assistant that acts on someone's behalf in other systems.

The moment an agent's output has a side effect outside its own context window,
the question changes from "did the model produce a plausible call?" to "who is
allowed to make this happen, under what policy, with what record?" Henosis is
the answer to that second question.

## What it does

| Area | What Henosis provides |
| --- | --- |
| **Shared rooms** | A server, channel, role, and message model where humans and agents are members of the same space. Agents can be paused per room, take turns under budgets, and switch between a tool-free *discuss* mode and a full *execute* mode. |
| **Persistent memory** | An embedded cognitive core for storing and recalling memories, assembling budgeted context, and handing work off between sessions. Room activity lands in the same memory and task stores the operator sees. |
| **Coordination** | Task tracking, multi-step workflows, agent presence and health, a narrated action log, and quality evaluation. These are kernel services that react to every action the dispatcher runs. |
| **Governed action** | One dispatcher for every tool call. It runs an ordered, fail-closed chain of authorization gates and refuses to start at all if that chain is incomplete or out of order. |
| **Human approval** | Durable, one-use approvals bound to the exact request, principal, tenant, policy revision, and expiry. In production, the approver must be a different administrator from the requester. |
| **Credentials without exposure** | Tools ask a credential broker to *sign*, *verify*, *derive*, or *execute* with a named secret. The agent never receives the secret itself. |
| **Tamper-evident audit** | Every execution is claimed in a hash-chained audit stream before it runs and completed after. An independent witness service can counter-sign checkpoints so the record can be checked off the host. |
| **Sandboxed extensions** | A WebAssembly Component Model host with fuel, memory, time, output, and network limits, and no ambient filesystem, process, clock, or network access. |
| **Any model** | A shared provider interface covering Anthropic, OpenAI-compatible APIs, Azure OpenAI, Ollama, and others. Authorization lives on the server, so switching models never moves the trust boundary into a prompt. |
| **Reasoning gates** | Crucible, a structured-reasoning toolkit for agents doing engineering work: specs, hypotheses, adversarial review, and verification before a task can be declared done. |
| **Desktop and terminal** | A native desktop application with Chat, full Desktop, and Spatial room views over one session, plus a CLI and terminal UI for headless and server use. |

## How an action moves through Henosis

Here is what happens when an agent in a room decides to do something with a
side effect, such as restarting a service.

```text
  agent in a room: "restart the api service"
            |
            v
  +-------------------------------------------------------------+
  |  authenticate caller        who is asking, for which tenant  |
  |  idempotency check          has this exact request run?      |
  +-------------------------------------------------------------+
            |
            v   gate chain (fixed order, any "no" stops everything)
  +-------------------------------------------------------------+
  |  1. capability   may this principal attempt this, here?      |
  |  2. policy       org active, role allows it, quota intact?   |
  |  3. safety       injection, scope violation, persona drift?  |
  |  4. human        does a person need to sign off first?       |
  |  5. credential   may this identity use the needed secret?    |
  +-------------------------------------------------------------+
            |
            v
  audit: record intent  ->  execute (bounded)  ->  filter output
            |                                          |
            v                                          v
  audit: record outcome, optional witness receipt     result returned
            |
            v
  task closed, action narrated in the room, memory updated
```

A few properties fall out of this design:

- **Gates fail closed.** If any authority cannot reach a decision, the action
  is denied. A human-approval timeout is a denial.
- **Nothing runs twice by accident.** Every request carries an idempotency key
  scoped to the caller. Repeating it returns the stored result. Reusing it with
  different content is rejected as a conflict.
- **Uncertain outcomes stay uncertain.** If a side effect may have happened but
  its result could not be recorded safely, the execution is marked
  *indeterminate*. It is never retried automatically. Only a human owner or
  administrator can resolve it, with an evidence digest recorded in the audit
  chain.
- **Secrets never reach the model.** Output is filtered on the way back, and
  credential-bearing fields are scrubbed before any result is stored or shown.

The full request path, including every failure mode, is in
[docs/architecture.md](docs/architecture.md).

## Architecture

Henosis runs as **one process**. A single `henosis` executable hosts identity,
the dispatcher and its gate chain, the kernel services, the operator and
machine APIs, and the managed agent room. Two production authorities, the
capability service and the credential broker, run as separate, separately
authenticated services.

```text
                 people                           agents
                   |                                 |
        desktop / CLI / terminal UI       agent loop + model providers
                   |                                 |
                   +------------> rooms <------------+
                                    |
  +---------------------------------v-----------------------------------+
  |                          henosis process                            |
  |                                                                     |
  |   identity  ->  dispatcher + gate chain  ->  tool gateway / sandbox |
  |                          |                                          |
  |                    event bus (in-process, durable sidecar)          |
  |                          |                                          |
  |   tasks   workflows   presence   action log   quality   memory      |
  |                                                                     |
  |   audit chain  ------------------------------------>  witness       |
  +---------------------------------------------------------------------+
                 |                                   |
       capability authority                 credential broker
          (separate service)                (separate service)
```

The named subsystems:

| Name | Role |
| --- | --- |
| **Rift** | The rooms. A chat server where humans and agents are members together, plus the bridge that seats agents in rooms. |
| **Synapse** | The agent loop: model providers, tools, persistent sessions, scheduled runs, CLI and TUI. |
| **Pistis** | Capability authority. Decides whether a principal may attempt a class of action in a given room. Proprietary production service. |
| **Plutus** | Policy authority. Organization status, roles, quotas, and rate limits. |
| **Eidolon** | Safety authority. Prompt-injection, scope-violation, and persona-drift checks on the way in, output filtering on the way out. |
| **Phylax** (`phylaxd`) | Credential broker. Use a secret without holding it. Proprietary production service. |
| **Hermes** | The tool gateway every executed action passes through. |
| **Hephaestus** | Stateful task executor for longer-running agent work. |
| **Chiasm, Loom, Soma, Broca, Thymus** | Kernel services for tasks, workflows, agent presence, action narration, and quality evaluation. |
| **Axon** | The event bus that connects every service, with a durable sidecar for audit-grade events. |
| **Cognition** | The embedded memory core, built on [Kleos](https://github.com/Ghost-Frame/Kleos). |
| **Crucible** | Structured-reasoning and code-quality gates for engineering agents. |

More detail on each is in the [glossary](docs/glossary.md).

## Deployment modes

| Mode | Shape |
| --- | --- |
| **Local** | Loopback only, one operator, SQLite state, embedded compatibility policy. Designed to run on a single machine with no external dependencies. |
| **Production** | Managed PostgreSQL, TLS and authenticated ingress, protected storage and backups, source-aware login limits, an independent audit witness, and private access to the capability authority and credential broker. |

Production capability requests fail closed until a deployment supplies trusted
room state from the capability authority. Local mode authorizes only a single
signed diagnostic action until a real authority is connected.

## What Henosis is not

- **Not a safety net for an agent that already has direct access.** Henosis
  governs actions that go through it. File tools are confined to the task root
  and reject traversal and symlink escapes, but `bash` is a separate, explicit
  capability that runs with the operating-system access of the Henosis
  process. Grant it deliberately and add process or container isolation that
  fits your threat model.
- **Not a prompt-engineering layer.** Nothing about authorization depends on
  what the model is told. The model is treated as an untrusted requester.
- **Not finished.** See below.

## Status and availability

Henosis is **pre-release** and **not distributed**. It has not completed its
first round of operator testing, and no build is published here or anywhere
else. The [limitations ledger](docs/limitations.md) lists what is implemented
and what is still open.

The private build pipeline already produces signed native archives for Linux,
macOS, and Windows with SPDX SBOMs and SLSA provenance. Releases will be
published in this repository once the first tested build is ready.

Evaluators, auditors, and prospective customers can request an evaluation build
or time-limited source access by writing to
[support@nulllogix.com](mailto:support@nulllogix.com) with the purpose and the
GitHub account to grant.

## Security and support

Send vulnerability reports to [security@nulllogix.com](mailto:security@nulllogix.com).
Send non-sensitive support requests to [support@nulllogix.com](mailto:support@nulllogix.com).
Do not put credentials, private endpoints, or exploit details in a public issue.
See [SECURITY.md](SECURITY.md) for the full policy.

## License

Henosis, including every document in this repository, is licensed under the
[PolyForm Noncommercial License 1.0.0](LICENSE). Personal, hobby, research, and
other noncommercial use is permitted. Any commercial use, including selling,
reselling, hosting, bundling, or otherwise earning revenue from this software,
requires a separate written commercial license. Contact
[support@nulllogix.com](mailto:support@nulllogix.com).

Copyright (c) 2026 Null Logix.

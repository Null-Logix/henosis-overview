# Glossary

Henosis reuses ordinary words (room, gate, approval) for specific concepts and
names its subsystems after Greek figures and anatomy. This page pins down what
each term means in Henosis.

## Concepts

| Term | Meaning |
| --- | --- |
| **Principal** | The one canonical actor type. Every human, agent, service account, and integration is a principal with a stable identity. Facts about a principal, such as presence or capability grants, live in the service that owns them. |
| **Tenant** | The isolation and billing boundary a request belongs to. Roles, quotas, audit streams, and idempotency keys are all tenant-scoped. |
| **Room** | A shared space where humans and agents meet, and the scope in which capabilities are granted. An action always names the room it runs in. |
| **Capability** | A named, expiring grant of specific action kinds to one principal inside one room. |
| **Dispatcher** | The single path every action takes. It runs the gate chain, executes, filters the result, and emits lifecycle events. |
| **Gate** | One authorization check in the dispatcher's fixed chain: capability, policy, safety, human, credential. A gate allows, denies, or requires approval. An error is a denial. |
| **Approval** | A durable record that a human decision is required, pending, or resolved, bound to one exact request and policy revision, and consumable once. |
| **Idempotency key** | The caller's retry identity for one request. The same key and request replay the stored result; the same key with different content is a conflict. |
| **Indeterminate execution** | An action whose side effect may have happened but whose outcome could not be recorded safely. It is never retried automatically and is resolved only by a human with recorded evidence. |
| **Audit head** | The latest record in a tenant's hash-chained audit stream. |
| **Witness** | A separate service with its own key and storage that counter-signs audit checkpoints, so the record can be verified off the Henosis host. |
| **Receipt** | The witness's signed acknowledgment of one checkpoint. |
| **Component** | A signed WebAssembly extension run in the sandboxed host with no ambient authority. |
| **Discuss / execute** | The two agent modes in a room. Discuss is one tool-free model round trip; execute is a full task session with gated tool access. |

## Subsystems

| Name | Origin | Role in Henosis |
| --- | --- | --- |
| **Henosis** | Greek, "oneness" or "union" | The whole system: agents, people, memory, and governed action in one place. |
| **Rift** | | The rooms. Chat server, membership, roles, and the bridge that seats agents in rooms. |
| **Synapse** | | The agent loop: model providers, tools, persistent sessions, scheduled runs, CLI and terminal UI. |
| **Pistis** | Greek, "trust" | Capability authority. Admits principals and decides what they may attempt in each room. The production service is proprietary. |
| **Plutus** | Greek god of wealth | Policy authority. Organization status, roles, quotas, and rate limits. |
| **Eidolon** | Greek, "image" or "phantom" | Safety authority. Prompt-injection, scope-violation, and persona-drift checks, plus output filtering. |
| **Phylax** (`phylaxd`) | Greek, "guardian" | Credential broker. Signs, verifies, derives, or executes with a named secret so the caller never holds it. The production broker is proprietary. |
| **Hermes** | Greek messenger god | Unified tool gateway every executed action passes through. |
| **Hephaestus** | Greek god of the forge | Stateful executor for longer-running agent tasks. |
| **Axon** | Neuron's signal fiber | In-process event bus, with a durable sidecar for events that must survive a restart. |
| **Chiasm** | Optic chiasm, where signals cross | Task coordination. |
| **Loom** | | Multi-step workflow orchestration. |
| **Soma** | Neuron's cell body | Agent presence and health. |
| **Broca** | Broca's area, speech production | Narrated log of every action. |
| **Thymus** | Gland that trains immune cells | Quality evaluation and drift signals. |
| **Cognition** | | Embedded memory core built on [Kleos](https://github.com/Ghost-Frame/Kleos). |
| **Crucible** | | Structured-reasoning and code-quality gates for engineering agents. |

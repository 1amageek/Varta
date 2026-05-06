# Varta

![Varta logo](Assets/varta-logo.png)

Varta is a filesystem submission contract and delivery daemon
for agent-to-agent messages.

The default service root is `~/Messaging`. Producers do not call a Swift
method, CLI, or direct recipient path as the process contract. They place
an envelope in the managed outbox:

```text
~/Messaging/
└── outbox/
    ├── pending/
    │   └── <envelope-id>/
    │       └── envelope.json
    ├── processing/
    ├── sent/
    └── failed/
└── quarantine/
    └── malformed/
        ├── outbox/
        └── control/
```

The daemon claims pending submissions, then routes them by `Envelope.to`:

```mermaid
flowchart LR
    Producer["Board / Bioid / Agent"] --> Pending["outbox/pending"]
    Pending --> Daemon["Varta daemon"]
    Daemon -->|"host == local"| Local["~/Messaging mapped inbox"]
    Daemon -->|"host == peer:*"| Remote["remote Varta"]
    Remote --> RemoteInbox["remote mapped inbox"]
```

Local and remote sends therefore use the same producer contract. Only
daemon-to-daemon remote delivery uses P2P/API transport.

## Products

| Product | Role |
|---|---|
| `Varta` | Filesystem submission queue, mailbox storage, registry, control commands, delivery routing, remote delivery wire types. |
| `VartaP2P` | `swift-peer-connectivity` adapter for daemon-to-daemon remote delivery. |

## Core Types

| Type | Role |
|---|---|
| `Address` | `(host, path)` route. `path` is the owner directory, not the storage directory. |
| `Envelope` | Durable message payload and metadata. |
| `FilesystemSubmissionQueue` | Writes and claims `outbox/pending/<id>/envelope.json`. |
| `MailboxStorageMapper` | Maps `Address.path` into `~/Messaging/mailboxes/...`. |
| `MailboxRegistry` | Records valid mailbox roots. |
| `MessagingControlCommand` | P0 mailbox lifecycle operation requested through the filesystem. |
| `Varta` | Daemon-side processor for control commands, pending submissions, receive, and ack. |
| `VartaService` | Remote receiver that validates and stores P2P deliveries locally. |

## Recipient Mailbox

Consumers keep using `Address.path` as their owner directory. Mailbox
state is centralized under the Messaging service root:

```text
Address.path:
  /Users/1amageek/Desktop/workspace 2

Mailbox root:
  /Users/1amageek/Messaging/mailboxes/local/Users/1amageek/Desktop/workspace 2
```

Mailbox layout:

```text
~/Messaging/
└── mailboxes/
    └── local/
        └── Users/
            └── <user>/
                └── .../
                    └── <owner-directory>/
                        ├── inbox/
                        ├── processed/
                        ├── rejected/
                        └── failed/
```

`receive()` snapshots `inbox/` in deterministic `issuedAt` order.
`ack(_:)` moves an envelope from `inbox/` to `processed/`.

## Control Plane

Board can act as the human P0 control plane by writing control commands:

```text
~/Messaging/
└── control/
    ├── pending/
    │   └── <command-id>/
    │       └── command.json
    ├── processing/
    ├── applied/
    └── rejected/
```

Supported commands:

| Command | Effect |
|---|---|
| `registerMailbox` | Create mailbox storage and a registry entry for an address. |
| `unregisterMailbox` | Remove the registry entry, optionally deleting storage. |
| `runGarbageCollection` | Apply retention to durable message, control, audit, and quarantine state. |

Registry entries live under:

```text
~/Messaging/
└── registry/
    └── mailboxes/
        └── local/
            └── ...
                └── registration.json
```

## Invariants

1. Filesystem is the inter-process API.
2. Local and remote submissions enter through the same outbox shape.
3. Agent working directories do not contain mailbox state.
4. `Address.path` remains the owner/context path.
5. Varta owns the mapping from owner path to storage path.
6. Remote paths are never mounted or written by the sender.
7. Delivery acknowledgement means durable storage, not task completion.

See [SPEC.md](SPEC.md) for the stable contract and
[OPERATIONS.md](OPERATIONS.md) for process-level behavior.

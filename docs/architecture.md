# Architecture

End-to-end picture of LastSeen.

```mermaid
flowchart TB
    subgraph user [User device]
        iOS[iOS App]
    end

    subgraph edge [Edge]
        Caddy[Caddy]
    end

    subgraph backend [Backend]
        API[Fastify API]
        TrackingW[Tracking worker]
        NotifyW[Notify worker]
        RollupW[Rollup worker]
        BaileysPool["Baileys session pool (in worker process)"]
    end

    subgraph data [Stateful]
        PG[("Postgres + TimescaleDB")]
        Redis[(Redis)]
        S3[(S3 / MinIO)]
    end

    subgraph external [External]
        WA[WhatsApp servers]
        Apple[Apple App Store]
        APNs[APNs]
    end

    iOS -->|"HTTPS, JWT bearer"| Caddy --> API

    API --- PG
    API -->|"jobs"| Redis

    TrackingW --- Redis
    TrackingW --- BaileysPool
    NotifyW --- Redis
    RollupW --- Redis

    BaileysPool <-->|"presenceSubscribe / presence.update"| WA
    BaileysPool -->|"presence events"| API
    BaileysPool -->|"auth state JSON"| S3

    API -->|"verify JWS"| Apple
    Apple -->|"S2S v2 webhook"| API
    NotifyW -->|"push"| APNs --> iOS
```

## Process boundaries

There are two long-running Node processes:

1. **API** (`src/api/server.ts`) — stateless HTTP server. Horizontally scalable. All Baileys session state lives in S3, so any API instance can serve any request.
2. **Worker** (`src/workers/index.ts`) — runs the BullMQ workers AND owns the in-process Baileys session pool. Currently a single instance; not horizontally safe yet because the in-memory session map would need a coordinator (Redis lock or sharded queues by scraper id).

When we scale workers, the path forward is one worker per scraper, with each worker subscribed to a scraper-specific queue.

## Data flow: a tracked number coming online

```mermaid
sequenceDiagram
    participant WA as WhatsApp
    participant Baileys as Baileys session
    participant Worker as Tracking worker
    participant Redis
    participant DB as Postgres
    participant Notify as Notify worker
    participant APNs

    WA->>Baileys: presence.update {jid, available}
    Baileys->>Worker: emit presence event
    Worker->>DB: insert presence_events row
    Worker->>Redis: enqueue notify(online)
    Worker->>Redis: enqueue rollup(today, debounced 30s)
    Notify->>DB: load TrackedNumber + prefs
    Notify->>APNs: send push if onlineEnabled
    APNs-->>iOS: notification banner
```

## Data flow: subscription purchase

```mermaid
sequenceDiagram
    participant iOS
    participant API
    participant Apple as App Store

    iOS->>Apple: Product.purchase()
    Apple-->>iOS: VerificationResult (signed JWS)
    iOS->>API: POST /v1/billing/verify { signedTransaction }
    API->>Apple: verify JWS via app-store-server-library
    Apple-->>API: decoded payload
    API->>API: upsert subscription row (status=ACTIVE, expiresAt)
    API-->>iOS: 200 OK
    Note over Apple,API: Later, Apple sends S2S v2 notifications<br/>for renewals, refunds, billing issues<br/>to /v1/billing/apple-notifications
```

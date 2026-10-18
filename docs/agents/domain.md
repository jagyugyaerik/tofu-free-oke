# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root: the project glossary (Language, Relationships, Flagged ambiguities). It plays the role other skills call `GLOSSARY.md`.
- **`docs/adr/`**: read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates or extends them lazily when terms or decisions actually get resolved. When it would write `GLOSSARY.md`, write to `CONTEXT.md` instead.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-oidc-wif-with-thin-local-bootstrap.md
│   ├── 0002-private-endpoint-flannel-single-node.md
│   └── 0003-state-in-oci-object-storage-s3-compat.md
├── bootstrap/
├── environments/
└── modules/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms listed on its `_Avoid_:` lines (e.g. say **Service user**, not "CI user"; **Bootstrap**, not "setup").

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0002 (private endpoint, flannel, single node), but worth reopening because…_

# CipherDAO

> The first coercion-resistant private DAO governance platform on Fhenix.

**Encrypted votes. Hidden tallies. Private treasury execution. Public blockchains finally work for serious organizations.**

---

![CipherDAO Architecture](cipherdao_architecture.jpg)

---

## The Problem

Public DAO governance is broken in ways most builders ignore:

- Every vote on Snapshot is visible in real time — whales watch and manipulate outcomes
- Members face social pressure and retaliation for dissenting votes
- Treasury swaps get front-run the moment a proposal passes
- Institutions with compliance requirements **cannot participate** — their legal teams won't allow permanent public voting records

This is not a minor inconvenience. It is why serious organizations don't use on-chain governance. The problem is architectural — transparency was baked in from day one.

**CipherDAO fixes this at the foundation using Fhenix CoFHE.**

---

## How It Works

Every sensitive piece of governance state stays encrypted on-chain throughout its entire lifecycle.

1. **Create proposal** — encrypted payload submitted via `@cofhe/sdk` client-side
2. **Cast vote** — `euint8` choice + `euint64` weight, encrypted before leaving the browser
3. **Tally** — `FHE.add` accumulates votes homomorphically, `FHE.gt` checks outcome — no individual vote ever decrypted
4. **Execute** — winning proposal triggers Privara confidential payment via `FHE.select` wrap — failed proposal is a silent no-op with no observable side effect

---

## Why FHE and Not ZK or Commit-Reveal

| Approach | Why It Fails |
|---|---|
| Commit-reveal | Leaks at reveal phase — coercer waits and correlates |
| ZK proofs | Can verify a vote is valid but cannot tally encrypted votes — no ZK equivalent to `FHE.add()` on ciphertexts |
| TEEs | Hardware trust assumptions |
| **FHE** | **Computes directly on ciphertexts — no decryption ever required** |

Remove FHE and coercion resistance collapses entirely.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Frontend — @cofhe/react hooks                      │
│  client-side encrypt · vote UI · tally reveal       │
└──────────┬──────────────┬──────────────┬────────────┘
           ↓              ↓              ↓
    ┌──────────┐  ┌───────────────┐  ┌────────────────┐
    │ Factory  │  │  Governance   │  │    Treasury    │
    │ .sol     │  │  .sol         │  │    .sol        │
    │          │  │               │  │                │
    │ deploy() │  │ euint8 vote   │  │ FHE.select     │
    │ no FHE   │  │ euint64 weight│  │ Privara SDK    │
    │          │  │ FHE.add tally │  │ silent no-op   │
    └──────────┘  └───────────────┘  └────────────────┘
           ↓              ↓              ↓
┌─────────────────────────────────────────────────────┐
│  Fhenix CoFHE — Nitrogen Testnet                    │
│  euint8 · euint64 · FHE.add · FHE.gt · FHE.select  │
│  FHE.allow · threshold decryption                   │
└─────────────────────────────────────────────────────┘
```

---

## FHE Operations Map

| Operation | FHE Function | Purpose |
|---|---|---|
| Store vote choice | `FHE.asEuint8(inEuint8)` | 1=For, 2=Against, 3=Abstain — encrypted |
| Store vote weight | `FHE.asEuint64(inEuint64)` | Token balance or fixed weight — encrypted |
| Accumulate For votes | `FHE.add(forVotes, weight)` | Homomorphic sum — no decryption needed |
| Accumulate Against votes | `FHE.add(againstVotes, weight)` | Same pattern |
| Check outcome | `FHE.gt(forVotes, againstVotes)` | Returns ebool — only this is decrypted |
| Check quorum | `FHE.gt(totalVotes, threshold)` | Quorum check stays encrypted |
| Conditional treasury | `FHE.select(passed, amount, zero)` | Failed proposal = silent no-op |
| Auditor access | `FHE.allow(handle, auditor)` | Scoped decryption permit |

---

## Privacy Threat Model

| Threat | Mitigation |
|---|---|
| Voter coercion | Votes revocable before deadline — no on-chain receipt of specific choice |
| Whale watching | All votes are euint ciphertext — tally is homomorphic |
| Front-running treasury | Treasury action encrypted until execution — FHE.select wrap |
| Vote buying | Revocability means any proven vote can be changed after payment |
| Replay attack | EIP-712 signed votes + per-voter nonce per proposal |
| Side-channel on treasury | FHE.select — failed proposal is silent no-op, not revert |
| Auditor overreach | FHE.allow scoped to specific proposal + specific data field only |
| Sybil voting | Membership enforced by token gate or address list |
| Quorum manipulation | Quorum threshold stored as encrypted euint64 — value unknown |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Encryption | Fhenix CoFHE (`@fhenixprotocol/cofhe-contracts`) |
| Payments | Privara SDK (`@reineira-os/sdk`) |
| Smart Contracts | Solidity 0.8.24 |
| Dev Tools | Hardhat + cofhe-hardhat-plugin |
| Frontend | React + `@cofhe/react` + `@cofhe/sdk` |
| Wallet | wagmi v2 + viem |
| Testnet | Fhenix Nitrogen |

---

## Wave Roadmap

| Wave | Deliverable |
|---|---|
| **Wave 1** | Architecture, Solidity interfaces, privacy model, threat analysis |
| **Wave 2** | Deploy Factory + Governance on Nitrogen testnet. React dashboard: create proposal, cast vote, view tally |
| **Wave 3** | Treasury module + Privara SDK. Auditor permit flow. Multi-proposal support. Full test suite |
| **Wave 4** | Gas optimization. Token-gated membership. UX polish. Upgradeable contracts |
| **Wave 5** | Pilot DAO deployment. Auditor dashboard. Mainnet readiness |

---

## Contract Interfaces

See `contracts/` folder for full Solidity interfaces:

- `IFactory.sol` — permissionless DAO deployment (no FHE ops)
- `IGovernance.sol` — encrypted voting + homomorphic tally
- `ITreasury.sol` — Privara SDK + FHE.select conditional execution

---

## Why This Cannot Be Built Without FHE

Coercion-resistant voting requires that a voter cannot prove to a third party how they voted — even if they try to. This property requires computation on hidden inputs. FHE is the only technology that provides this on a public EVM chain without trusted hardware or off-chain components.

**CipherDAO cannot exist without FHE. It is not FHE bolted on — it is FHE as the foundation.**

---

## Acknowledgements

Built on top of the official Fhenix CoFHE stack and awesome-fhenix templates. Integrates Privara SDK for confidential payment rails.

- Fhenix docs: https://docs.fhenix.io
- CoFHE SDK: `@cofhe/sdk`
- Privara: https://reineira.xyz/docs
- awesome-fhenix: https://github.com/FhenixProtocol/awesome-fhenix

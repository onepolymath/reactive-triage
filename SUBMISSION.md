# Draft BUIDL — Triage (Reactive Omni Buildathon)

Paste or adapt this on DoraHacks when submitting. Do not submit until the GitHub repository is public, the demo video is recorded, and (if faucets were completed) live testnet addresses and full-loop transaction hashes are filled in.

**Deadline:** 5 December 2026, 21:00 Africa/Lagos (20:00 Europe/London).

**Primary track:** Reactive Meets AI

---

## Title

Triage — leave a clerk watching your approvals

## Tagline

A Lasna reactive clerk that scores ERC-20 transfers and approvals, opens cases on Base Sepolia, and lets an in-loop policy agent escalate unlimited approvals.

## Description

Triage watches a token on Base Sepolia for `Transfer` and `Approval` logs. A reactive contract on Lasna receives those logs, scores them on-chain, and requests an authenticated Omni callback that opens a case on `TriageDesk`. A policy agent that ships with the project — part of the running system, not just the tool used to write it — files a verdict: record, watch, or escalate. Unlimited approvals raise an on-chain `AlertRaised` event you can subscribe to.

The reactive contract does real work (decode + score) before it asks for a callback, and it never reverts on an ordinary mismatch. The destination desk accepts `openCase` only from the official Base Sepolia callback proxy, and only when the injected sender is the reactive contract.

This is a personal automation you can leave running, and an AI clerk that is actually in the loop.

## How it uses Reactive Omni

- `TriageReactive` inherits `AbstractReactive` and, in the constructor, subscribes to the demo token’s `Transfer` and `Approval` topics on Base Sepolia (specific chain id, contract, and topic0).
- `react(LogRecord)` is `onlySystem`. It scores the event and calls `SYSTEM.requestCallbackV_1_0` with a payload whose first argument is `address(0)` so the callback proxy can inject the reactive address.
- `TriageDesk` inherits `AbstractCallback`, constructed with the official Base Sepolia callback proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585` and the predicted reactive address. `openCase` is `onlyServiceProvider` + `onlyCallbackSender`.
- Contracts are payable and funded at deploy time so reactive transactions and callbacks can be paid for.

## Deployed addresses (fill after testnet deploy)

- DemoToken (Base Sepolia, 84532): `TBD`
- TriageDesk (Base Sepolia, 84532): `TBD`
- TriageReactive (Lasna, 5318007): `TBD`
- Callback proxy (official): `0x476F44b11F5C942c58f4c8E3d0300E5710743585`
- System contract (Lasna): `0x8888888888888888888888888888888888888888`

## Full-loop transaction hashes (fill after the live demo)

The submission requires the origin event, the Lasna `react` transaction, and the destination callback.

- Origin (unlimited approval or large transfer) on Base Sepolia: `TBD`
- Reactive `react()` on Lasna: `TBD`
- Callback `openCase` on Base Sepolia: `TBD`
- Policy `fileVerdict` on Base Sepolia (optional but recommended): `TBD`

## Demo video

Record a walkthrough under 3 minutes using `demo/walkthrough.md` as the script. Suggested beats: problem (unlimited approval), architecture diagram, Foundry tests, origin transaction, Lasna react, destination case, agent verdict, `AlertRaised`.

## GitHub

Private during development: `https://github.com/onepolymath/reactive-triage`  
Make the repository **public** immediately before submitting (the hackathon requires a public repo).

## Submitter checklist (Yusuf)

1. Review the private repository and this draft.
2. If the throwaway testnet address is still unfunded, use a free Base Sepolia faucet on the address in `.env` (never a mainnet or real-funds wallet). If the faucet shows a captcha or login, complete it yourself. Then run `scripts/request-lreact.sh` and `scripts/deploy-testnet.sh`.
3. Run `scripts/emit-demo-events.sh`, wait for the Lasna reaction and the Base Sepolia callback, file verdicts with the policy agent, and copy every hash into this file and `deployments/loop.json`.
4. Record a demo video shorter than 3 minutes and upload it where DoraHacks can reach it.
5. Register for the Reactive Omni Buildathon on DoraHacks if you have not already.
6. Make `onepolymath/reactive-triage` public.
7. Create the BUIDL, pick **Reactive Meets AI** as the primary track, paste the text above with the live addresses and hashes, and attach the video.
8. Submit before **5 December 2026, 21:00 Africa/Lagos**.
9. Do not deploy to mainnet, do not use real funds, and do not spend money on faucets, APIs, or boosts for this entry.

## Tracks and judging (self-review)

- **Reactive Meets AI:** the policy agent files verdicts in the live loop; an optional LLM may only rewrite the rationale.
- **Set It and Forget It (secondary story):** once deployed and funded, the clerk keeps watching approvals without further input.
- **Execution:** on-chain reactive transactions and callbacks are the core demo; tests cover the same loop if a faucet is still pending.
- **Integration:** scoring happens in `react()`, not in a bolted-on script that ignores the reactive contract.
- **Usefulness:** escalated approvals are a real personal-automation problem.
- **Craft:** tests, this README, a mermaid diagram, and a working local demo.

# Demo walkthrough (keep it under 3 minutes)

Suggested narration. Screen recordings can follow the frames in `demo/frames/` and the silent stitch `demo/triage-walkthrough.mp4`.

**0:00–0:20 — The problem.**
“Unlimited token approvals are how a lot of wallets still get drained. I do not want to babysit every `Approval` log. I want a clerk that watches them for me.”

**0:20–0:50 — The loop.**
Open `README.md` or `demo/index.html` and show the mermaid diagram. Point at each hop: Base Sepolia token, Lasna `TriageReactive.react()`, callback into `TriageDesk.openCase`, policy agent, `AlertRaised`.

**0:50–1:20 — Tests prove the loop.**
Run `forge test --match-test test_fullLoop_unlimitedApprovalEscalates -vv` and `python3 -m services.policy.agent --dry-run --cases demo/cases.json`. Mention that `react()` scores the event on-chain and that a mismatched log does not revert.

**1:20–2:20 — Live testnet (if funded).**
Show `deployments/testnet.json`. Open the origin approval on Base Sepolia, the `react` transaction on https://lasna.reactscan.net, and the `openCase` callback on Base Sepolia. Then show `fileVerdict` and `AlertRaised`. Read the three hashes out loud or paste them on screen — the judges need them.

**2:20–2:50 — Close.**
“Triage is a clerk you can leave running. The AI is in the loop, not just in the editor I used to write it.”

If live hashes are not ready, walk through the Foundry full-loop test and say the same contracts will be deployed to Base Sepolia and Lasna once the throwaway address is faucet-funded. Do not show a mainnet wallet.

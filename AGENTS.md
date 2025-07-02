# AGENTS.md — Blob Edge Stack (BBOD + BSP)

## Repo Scope

This file governs all code, infra, and documentation changes to this repository.
Any proposed patch, pull request, or AI/agent-generated code must follow these rules.

## Critical Requirements

1. **All protocol logic must remain fully auditable, upgradable, and adversarially robust.**
   - No contract or off-chain bot should introduce a backdoor, privileged outcome control, or non-auditable admin flow.
   - All core parameters (rake, threshold, margin, oracles) must be justified and documented in PRs.

2. **Testing**
   - Every code change must pass:  
     - `forge test -vv`
     - All custom fuzz/adversarial edge-case tests in `test/`
     - Linter (e.g. `pnpm lint`) and any formatting (`pnpm format`)
   - If tests are added or changed, include output logs in PRs or task results.

3. **Task Context**
   - Each PR or agent request must specify:  
     - Repo, branch, affected files (by path)
     - Summary of what and why (link to audit delta or bug if applicable)
     - Exact code changes as unified diffs or patch files

4. **Manual Execution & Evidence**
   - No agent or bot applies changes automatically. All edits must be reviewed and merged by a human or the designated repo operator.
   - All terminal logs and relevant evidence (e.g. test output, deploy tx hashes) must be pasted in the PR/task.

5. **Red-Team Review**
   - Every protocol or economic change must be adversarially challenged before merge:
     - What grief/MEV/copycat/fork path could break this change?
     - Is there any new stuck funds or edge decay path introduced?
     - Could this break compounding, liveness, or monopoly window?
   - If any reviewer or agent finds a critical issue, the change is blocked until resolved.

6. **Doc and Config Sync**
   - All public functions and configs must be documented in code and updated in `README.md` as needed.
   - Any new agent, bot, or keeper must be described in `/bots/` or `/docs/`.

7. **Constraints**
   - No off-chain negotiation, no privileged access, no unreviewed changes to core economics.
   - Any oracle or bot change must be logged and justified, with new keys or endpoints flagged.

## Testing Instructions (for Codex or Humans)

- Run all unit and fuzz tests with `forge test -vv --fork-url <RPC>`
- Run all off-chain bots in dry-run mode (`pnpm ts-node bots/seedBot.ts --dry-run`)
- Deploy on Sepolia first and paste deploy addresses in the PR/task

## Completion

- Every merged change must include a summary, affected files, and evidence that all tests and checks passed.
- Any known issues, TODOs, or audit flags must be listed at the bottom of the PR/task for follow-up.

## Blockers

- Do NOT merge any change that fails a test, adds a known exploit, or removes review requirements.
- Do NOT push directly to mainnet unless this file’s process is followed and all tests/evidence are posted.

# End of AGENTS.md

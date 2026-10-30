# Sessions: tiers and proposals

How several Claude Code sessions on one host work together without trusting
each other. Written 2026-10-20 from the first live case: a session in an
org repo was refused an edit by the hook (the rule for `devenv.nix`
matched ai-jailer's own module source), wrote the change up as a diff,
sent it to the session open in the ai-jailer checkout, and that session put
the diff in front of Raul before applying it. That sequence is the design;
this file says which parts of it to make structural, and in what order.
The roadmap keeps the order against everything else.

## 1. Principles

- **Identity comes from the host, never from a message.** Which session is
  allowed to touch what is a property of the directory it was started in
  and the configuration that names the directories. A session can claim
  anything in a message; the receiver acts on none of it.
- **The human is the only party who can accept a relayed request.** A
  session that was refused an action does not get it done by asking a peer.
  Claude Code's own guidance to the receiving session says so (it calls it
  permission laundering); the jailer makes it a check the engine performs,
  not a courtesy the model extends.
- **Coordination is a separate layer from enforcement.** `env-guard.sh`, the
  deny rules and the sandbox stay the hard rules, enforceable from a repo
  on any host. Everything in this file is coordination: it may make the
  rules easier to live with, it never relaxes one.
- **Observe before act.** Anything that shows state ships before anything
  that changes it.

## 2. What Claude Code already provides

Built into the binary, no mod involved, on this build (2.1.304):

- Sessions on one machine see each other (`ListAgents`) and message each
  other (`SendMessage`). The name is the directory the session runs in,
  plus its tmux pane.
- A message between sessions in different permission modes is held for the
  receiving human's approval; a message between sessions in the same mode
  is delivered to the model.
- The receiving model is told that a peer's request carries no user
  authority and that a request to do what the sender was refused must go
  to the human.

What it does not provide: a record of a proposal, a guarantee that the
receiver asks the human, a notion of which session may touch what, or any
view across sessions. The deny rules and the mod policy do not cover
messaging at all; a repo cannot isolate its session from its peers.
Whether sessions under different Linux users still see each other is not
checked.

## 3. Tiers, realised as Linux users

Planned on 2026-10-20 as two tiers, org and platform, chosen by
`ajmux` from the directory and exported as `AI_JAILER_TIER`. Realised on
2026-10-24 as a role the repo's devenv shell set (`harness.role`,
`AI_JAILER_ROLE`). Replaced on 2026-10-27 by Linux users, because a role set
inside one UID separated nothing: every session ran as the same user with
the same files. A tier is now a user, and which session may touch what is a
property of the operating system. Section 5 keeps the old words.

| Tier | Who | Rules | Part in the flow |
|---|---|---|---|
| work | the worker user `w-<org>`, one per org: private 0750 home, own Claude login, own git identity, own clones under its code root (`~/code/git/<org>/<repo>`), no push credential, no sudo | the law from the host's managed settings, and the jail: the full deny set, the sandbox with its lists and the account sync off in its own user settings, written by `aj bootstrap` from `/etc/claude-code/jail-settings.json` and checked against it by the hook before every tool (2026-10-28, roadmap item 14); plus the repo's project layer, the cell | proposes; never applies a change the rules refused |
| owner | your own account, a member of every worker's group, with `sudo -u w-<org>` to the workers and no sudo rule the other way | the law alone: credential reads, `git commit` and `git push` refused, bypass mode and mods off; no sandbox, no other deny rule or hook rule (2026-10-28, roadmap item 14): the ai-jailer checkout needs nix, sudo, `gh` and the daemon socket | the human: accepts or rejects proposals, applies diffs as the owner or as the worker, reads the workers' clones through the group |

Which tier a session is in is its UID, not a line in a file an agent could
edit: a worker cannot become the owner, cannot read the owner's home or
another worker's (0750; untested live, check V7 and `aj check` case
18), and cannot use sudo (hook rule 4 refuses it by text; the sudoers file
has no rule for a worker). `ajmux <org>/<repo>` from the owner's
account hands over to the worker (`sudo -u w-<org> -i`); a worker
naming another org is refused. No session has a different rule set
from the workers': a session in this checkout is an ordinary managed
session. A tmux server is per user, so a worker's `send-keys` reaches only
its own server (runbook section 8).

The 2026-10-20 trigger remains: the hook's rule for `*/devenv.nix` matches
ai-jailer's own `devenv/devenv.nix` too, so a change there comes to the
human as a diff, in every session.

## 4. The proposal flow

A proposal is a diff plus a rationale, the user and directory it came
from, and a timestamp. It is the only thing that crosses from a worker to
the owner.

1. A work session hits a refusal for a change to a jailer-owned or
   project-config file (`devenv.nix`, `.envrc`, `.claude/settings.json`,
   the ai-jailer source). It writes the change as a diff and submits it as a
   proposal. It does not ask any session to apply it.
2. The owner's session, or the owner reading the worker's window, shows
   the proposal to the human: the model relays it in chat and asks. The
   window it waits in turns colour in tmux (`tmux-notify.sh`), per user.
3. The human accepts and applies the diff, as the owner or as the worker
   (`sudo -u w-<org> -i`), in an editor or a terminal, since the hook
   refuses a session's edit to these files in every session. The
   `direnv allow` that follows is the human's, run as the worker: the hook
   refuses it to sessions.
4. The applied change is traceable to the accepted proposal.

The flow is unchanged by the move to users. Steps 1 and 2 are the CLAUDE.md
contract in both places: the block `aj init` writes into work repos
("Do not work around it: propose a diff or ask") and this repo's own
CLAUDE.md ("propose those as diffs"; it has no line of its own on relayed
requests, so the receiving side is Claude Code's guidance in section 2).
Step 3 is the human. Step 4 is the chat transcript. That is the whole
mechanism: the broker mod that was to make steps 2, 3 and 4 structural was
dropped on 2026-10-24 (section 5).

Relay is for the genuine case: a work session needing a change to
ai-jailer source or project configuration. Routine work bouncing through the
owner means a rule over-matches, and the fix is the rule.

## 5. The broker mod: dropped 2026-10-24

Roadmap item 8 planned one mod, `harness-broker`, shipped from this
repository through a managed marketplace directory in three stages:
observe (a row per session in the mod's store, `/fleet`, the tier in the
status line), propose (`/propose`, and a `/proposals` pane with accept and
reject in the platform session), gate (a `tool.call` hook in the platform
session letting through only edits that match an accepted proposal). The
builder, the registration keys and the first observe slice went in on
2026-10-21; the mod never loaded on a managed host.

Dropped on 2026-10-24, with the machinery that built and shipped it
(changelog). A mod is a hooks module loaded into the engine of every
session on the machine: it sees every event, can deny or rewrite any tool
call and change the system prompt, runs with the engine's reach outside
the Bash sandbox, and keeps a store every session shares. An enabled
organisation mod is the one kind the built-in guard lets through, so
shipping one makes its code, its build, the marketplace that serves it and
the keys that enable it a trust surface the jailer would have to defend
on every host, for coordination that never relaxes a rule (section 1).

What stays is the policy that refuses mods:

- The built-in guard's `allowManagedModsOnly` with no
  organisation mod enabled, so every mod is refused;
  `strictKnownMarketplaces` empty unless `harness.extraKnownMarketplaces`
  lists a source, so no marketplace can be added; `disableSideloadFlags`;
  `allowManagedHooksOnly`. The managed tree has no marketplace directory.
- Any host: the deny rules and the hook refuse `claude plugin` and the
  plugin flags on a nested `claude`; `aj init` refuses a repo with a
  plugin manifest under `.claude`.
- Since 2026-10-27 the managed settings carry `syncClaudeAiSkills` and
  `syncClaudeAiPlugins = false` (V9, 2026-10-29: honoured as far as the log shows), so the claude.ai
  account's plugins and skills do not load; bootstrap's user-scope write
  and `--account-sync` are gone.

Coordination stays the proposal flow of section 4 plus `ajmux`: the
CLAUDE.md contract in each tier, Claude Code's own messaging between
sessions, the human as the gate, and the tmux window colour as the sign
that a session waits. A record of proposals and a structural gate have no
replacement; reopening either takes a new
dated roadmap entry.

## 6. Testing

- The mod policy: `managed-tree-test` over both managed trees (no
  marketplace directory, no `extraKnownMarketplaces` or `enabledPlugins`,
  the guard option, an empty `strictKnownMarketplaces`,
  `disableSideloadFlags`, `allowManagedHooksOnly`), `managed-host-eval` for
  the host.nix options and the `managed-wsl` tree, `hook-test` for the
  `claude plugin` refusals.
- The proposal flow is a contract between models and a human, so its test
  is live: the live suite (`aj check`) is to gain a case where a work
  session's refused edit ends as a proposal in chat and not as an edit
  anywhere. The case does not exist yet.

## 7. Open questions

- Whether the managed settings alone keep a session out of bypass mode
  (`disableBypassPermissionsMode` is honoured from any scope; confirm it
  covers `--permission-mode` on the outer `claude`, which the hook cannot
  see).
- Remote Control: a driven session is still the local process, so the
  rules apply unchanged; confirm once Remote Control can start on a
  ai-jailer host (roadmap, Ideas).

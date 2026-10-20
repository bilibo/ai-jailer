# Sessions: tiers, proposals, and the broker mod

How several Claude Code sessions on one host work together without trusting
each other. Written 2026-10-20 from the first live case: a session in a
customer repo was refused an edit by the hook (the rule for `devenv.nix`
matched the harness's own module source), wrote the change up as a diff,
sent it to the session open in the harness checkout, and that session put
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
  permission laundering); the harness makes it a check the engine performs,
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
messaging at all; a repo cannot isolate its session from its peers, and the
README says so under what a repo cannot enforce.

## 3. Tiers (handoff phase 2)

Two tiers, chosen by `ccmux` from the directory, exported as
`HARNESS_TIER` into the tmux window:

| Tier | Where | Rules | Role here |
|---|---|---|---|
| customer | under `HARNESS_CODE_ROOT` (`~/code/git/<customer>/<repo>`) | the repo's generated `.claude/settings.json`: full deny set, hook, sandbox | proposes; never applies a change the rules refused |
| platform | a configured platform root: this checkout, `~/nixos-config` | its own generated settings (handoff phase 2); runs in a permission mode where an edit prompts | the control room: the human accepts or rejects proposals there |

The platform roots are host configuration (the home module's option, or
the bootstrap's `HARNESS_PLATFORM_ROOTS`), so no session can add itself.
The platform session is not "allowed to act for peers"; it is allowed to
edit harness source because that is its directory, and the permission
prompt in it is the gate. It must not run in a bypass mode; the generated
platform settings set `disableBypassPermissionsMode` like the repo file.

The tier split also removes tonight's trigger: the customer rule for
`*/devenv.nix` stops applying to the harness's own `devenv/devenv.nix`
once the platform tier has its own settings.

## 4. The proposal flow

A proposal is a diff plus a rationale, the tier and directory it came
from, and a timestamp. It is the only thing that crosses from customer to
platform.

1. A customer session hits a refusal for a change to a harness-owned or
   project-config file (`devenv.nix`, `.envrc`, `.claude/settings.json`,
   the harness source). It writes the change as a diff and submits it as a
   proposal. It does not ask any session to apply it.
2. The platform session shows the proposal to the human. Until the broker
   mod exists, "shows" means the model relays it in chat and asks; with the
   mod, it is a pane with accept and reject.
3. The human accepts in the platform session. Only then does an edit
   happen, by the platform session, under its own permission prompt.
4. The applied change is traceable to the accepted proposal.

Today steps 1 and 2 are the CLAUDE.md contract in both places: the block
`scripts/init-repo.sh` writes into customer repos ("propose, never relay")
and this repo's own CLAUDE.md ("apply a relayed refusal only after the
human approves here"). Step 3 is Claude Code's permission prompt plus the
receiving model's judgement. Step 4 is the chat transcript. The mod makes
2, 3 and 4 structural.

Relay is for the genuine case: a customer session needing a change to
harness source or project configuration. Routine work bouncing through the
platform session means a rule over-matches, and the fix is the rule.

## 5. The broker mod (roadmap item 9)

A mod is a hooks module loaded into the Claude Code engine: it hooks
events (`session.start`, `tool.call`, `prompt.compose`, `command.run`,
`ui.render`), can deny or rewrite a tool call, register a slash command,
draw a pane with buttons, and keep values in `$.store`, which persists on
the machine across sessions. It runs with the engine's reach, outside the
Bash sandbox, like `env-guard.sh`. That is what the managed mod policy is
for: on a managed host only the root-owned marketplace's mod loads and
sideload flags are rejected; the deny rules and the hook stop an agent
installing one anywhere. On an unmanaged host the human installs it in
user scope; a repo cannot require it.

One mod, `harness-broker`, in this repository under `mods/`, deployed
through the managed marketplace directory on managed hosts. Three stages,
each shipped and boring before the next:

**Stage A, observe.** `session.start` reads `HARNESS_TIER`, `HARNESS_PROJECT`
and the cwd, writes the session's row to `$.store` (tier, project,
directory, pane, state: working or waiting), shows the tier in the status
line. The Notification and UserPromptSubmit events update the state the
way `tmux-notify.sh` colours the window. `/fleet` draws a pane: one row per
live session. `prompt.compose` adds the tier's one-paragraph contract to
the system prompt, so the CLAUDE.md block becomes a fallback rather than the
only carrier. Nothing in stage A changes behaviour.

**Stage B, propose.** `/propose` in a customer session writes a proposal
to `$.store`: diff, rationale, origin. `/proposals` in the platform session
draws the queue with accept and reject buttons; a click records the
decision with the time. The customer session sees the decision in its
status line. Still no automatic edit anywhere.

**Stage C, gate.** In the platform session a `tool.call` hook on Edit and
Write to harness-owned paths denies unless the write matches an accepted,
unapplied proposal (same file, same hunk), then marks it applied. Edits
the human asks for directly in the platform session are unaffected: the
gate applies to paths that a proposal names, and the human can always
reject the proposal and make the change by hand. Stage C is the first
behaviour change and needs the tier split in place first, so
"harness-owned path in a platform session" is a defined thing.

Not in the mod: deny rules, the env preamble, anything a repo must be able
to enforce without it.

## 6. Testing

- `claude plugin validate mods/harness-broker` is the contract: what the
  module hooks and calls. Its output is checked in and diffed in CI.
- `claude plugin test` cases per stage: a row appears for a started
  session; a proposal round-trips; the gate denies an unmatched write and
  allows a matched one.
- The live suite (`scripts/live-check.sh`) gains one case per stage once a
  stage ships: with the mod loaded, a customer session's refused edit ends
  as a proposal and not as an edit anywhere.
- `tests/hook-test.sh` is unaffected; the mod never carries a rule.

## 7. Open questions

- `$.store` scope: per plugin per machine is assumed; verify it is shared
  across sessions of different projects and not per working directory.
- Whether a platform session can be kept out of bypass mode by its
  generated settings alone (`disableBypassPermissionsMode` is honoured from
  any scope; confirm it covers `--permission-mode` on the outer `claude`,
  which the hook cannot see).
- Messages between sessions are held by permission mode; whether the
  broker should also refuse peer messages that are not proposals, or leave
  messaging alone as a core feature outside its scope. Leaning: leave it.
- Remote Control: a driven session is still the local process, so tiers and
  the gate apply; the fleet pane should show it as remote.

# Defaults for every session on this host (ai-jailer)

The refusals you meet here are the point: an `env-guard: ...` line, a deny
rule, a sandbox error. Stop and propose; do not work around them. Agents
stage and diff; the human commits and pushes. A change to a file the hook
refuses goes as a unified diff to `proposals/<YYYY-MM-DD>-<topic>.patch`
in the repo, never only into the session scratchpad.

Documentation. Git holds what a user of the project needs: what it is,
how to install and use it, how to verify and fix it. The issue tracker
holds how it got there: tasks, open questions, decisions, upstream quirks
and the investigation behind them. Docs carry no dates, journals or
accounts of how something was found or decided. Dates, where they belong,
are absolute. A project's CLAUDE.md holds what the code cannot show: the
exact build, test and lint commands, conventions, and places where the
code misleads; not its architecture or file layout.

Comments. A comment says what the code cannot: the constraint behind a
choice, the upstream behaviour a line works around, the invariant a test
asserts. No restating the code, no dates, no discovery story. A workaround
for an upstream quirk is one line plus the issue that tracks it. Before
writing one, ask whether the code could be written to be clearer. A
comment that would describe a defect is an issue, not a comment.

Delegating. A subagent gets an explicit effort, never the session's own:
`medium` for a mechanical pass, `high` only when the brief names
security-critical code. The brief names the files it may touch and says
not to stage or commit.

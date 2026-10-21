// The row a session keeps in `$.store` under `session:<id>` (docs/sessions.md
// section 5, stage A). `tier` is `HARNESS_TIER` once handoff phase 2 exports
// it, null until then; `project` is `HARNESS_PROJECT` from the devenv shell,
// else `DEVENV_ROOT`, else null for a session started by hand.
export type FleetRow = {
  id: string
  tier: string | null
  project: string | null
  cwd: string
  startedAt: string
}

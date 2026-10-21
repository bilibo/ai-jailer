// harness-broker, the first slice of stage A (docs/sessions.md section 5):
// a row per session in `$.store`, the tier in the status line, `/fleet` to
// list the rows. Nothing here changes behaviour; the proposal flow (stage B)
// and the gate (stage C) come later and need the tier split first.
//
// `$.store` is this plugin's, shared by every session on the machine. A
// session that ends cleanly removes its row; one that is killed leaves it,
// so `/fleet` prints the start time and the row is overwritten the next time
// that session id starts.
import type { Register } from 'claude-code'

import type { FleetRow } from '../types'

const PREFIX = 'session:'
const key = (id: string): string => `${PREFIX}${id}`

const isRow = (value: unknown): value is FleetRow =>
  typeof value === 'object' && value !== null && typeof (value as FleetRow).id === 'string'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const id = await $.session.id()
    const tier = await $.env.get('HARNESS_TIER')
    const project = (await $.env.get('HARNESS_PROJECT')) ?? (await $.env.get('DEVENV_ROOT'))
    const row: FleetRow = {
      id,
      tier: tier ?? null,
      project: project ?? null,
      cwd: e.cwd,
      startedAt: new Date(await $.clock.now()).toISOString(),
    }
    await $.store.set(key(id), row)
    await $.command.register({
      name: 'fleet',
      description: 'List the harness sessions on this machine',
    })
    if (tier !== undefined) $.ui.status(`tier ${tier}`)

    return next(e)
  })

  on('session.end', async ($, e, next) => {
    await $.store.delete(key(await $.session.id()))

    return next(e)
  })

  on('command.run', { command: 'fleet' }, async $ => {
    const keys = (await $.store.keys()).filter(k => k.startsWith(PREFIX))
    const rows: FleetRow[] = []
    for (const k of keys) {
      const value = await $.store.get(k)
      if (isRow(value)) rows.push(value)
    }
    if (rows.length === 0) return { text: 'No harness sessions recorded.' }
    const lines = rows.map(r => `${r.tier ?? '-'}\t${r.project ?? r.cwd}\t${r.startedAt}\t${r.id}`)

    return { text: ['tier\tproject\tstarted\tsession', ...lines].join('\n') }
  })
}

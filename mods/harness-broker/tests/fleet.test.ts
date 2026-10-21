// `claude plugin test <built mod>` (tests/mod-validate-test.sh runs it).
//
// A test's `$` raises events only (`session.start`, `command.run`, ...); the
// plugin's own calls (`$.session.id`, `$.store`, `$.clock`, `$.ui.status`)
// are answered by the test's hooks beneath it, so each test checks what the
// plugin did through `/fleet` and through what it sent those hooks.
import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import type { FleetRow } from '../types'

const ID = 'session-1'
const NOW = Date.UTC(2026, 9, 21, 9, 0)
const STARTED = new Date(NOW).toISOString()

// Another session on the same machine, as its row sits in the shared store.
const OTHER: FleetRow = {
  id: 'session-0',
  tier: null,
  project: '/home/u/code/claude-nix-harness',
  cwd: '/home/u/code/claude-nix-harness',
  startedAt: '2026-10-21T08:00:00.000Z',
}

// Stands for the engine beneath the plugin; returns the status line texts.
const engine = (on: On, store: Record<string, unknown> = {}): (string | undefined)[] => {
  const statuses: (string | undefined)[] = []
  mock.store(on, store)
  mock.clock(on, { now: NOW })
  on('session.id', () => ({ value: ID }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.end', () => ({ sessionId: ID }))
  on('command.register', () => ({ value: { command: 'fleet' } }))
  on('ui.status', (_, e) => {
    statuses.push(e.text)
    return { value: undefined }
  })
  return statuses
}

const start = { surface: 'terminal', isInteractive: true } as const
const end = { reason: 'prompt_input_exit', sessionId: ID, resume: { id: ID } } as const

test('two sessions on one machine: /fleet lists both', async ($, on) => {
  engine(on, { [`session:${OTHER.id}`]: OTHER })
  mock.env(on, { HARNESS_TIER: 'customer', HARNESS_PROJECT: 'acme' })

  await $.session.start({ ...start, cwd: '/home/u/code/acme' })
  const { text } = await $.command.run({ command: 'fleet' })

  expect(text).toContain('tier\tproject\tstarted\tsession')
  expect(text).toContain(`customer\tacme\t${STARTED}\t${ID}`)
  expect(text).toContain(`-\t${OTHER.project}\t${OTHER.startedAt}\t${OTHER.id}`)
})

test('a session that ends removes its own row, not the other one', async ($, on) => {
  engine(on, { [`session:${OTHER.id}`]: OTHER })
  mock.env(on, { HARNESS_TIER: 'customer', HARNESS_PROJECT: 'acme' })

  await $.session.start({ ...start, cwd: '/home/u/code/acme' })
  await $.session.end(end)
  const { text } = await $.command.run({ command: 'fleet' })

  expect(text).not.toContain(ID)
  expect(text).toContain(OTHER.id)
})

test('the status line shows the tier', async ($, on) => {
  const statuses = engine(on)
  mock.env(on, { HARNESS_TIER: 'customer' })

  await $.session.start({ ...start, cwd: '/home/u/code/acme' })

  expect(statuses).toEqual(['tier customer'])
})

test('a session started by hand has no tier, its cwd as project', async ($, on) => {
  const statuses = engine(on)
  mock.env(on, {})

  await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
  const { text } = await $.command.run({ command: 'fleet' })

  expect(text).toContain(`-\t/repo\t${STARTED}\t${ID}`)
  expect(statuses).toEqual([])
})

test('/fleet with nothing recorded says so', async ($, on) => {
  engine(on)
  mock.env(on, {})

  const { text } = await $.command.run({ command: 'fleet' })
  expect(text).toBe('No harness sessions recorded.')
})

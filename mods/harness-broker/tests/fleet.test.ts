// `claude plugin test <built mod>` (tests/mod-validate-test.sh runs it).
import { expect, mock, test } from 'claude-code/testing'

test('a started session has a row and /fleet lists it', async ($, on) => {
  mock.store(on)
  mock.env(on, { HARNESS_TIER: 'customer', HARNESS_PROJECT: 'acme' })

  await $.session.start({ cwd: '/home/u/code/acme', surface: 'terminal', isInteractive: true })
  const id = await $.session.id()

  expect(await $.store.get(`session:${id}`)).toEqual(
    expect.objectContaining({ id, tier: 'customer', project: 'acme', cwd: '/home/u/code/acme' }),
  )

  const { text } = await $.command.run({ command: 'fleet' })
  expect(text).toContain('customer')
  expect(text).toContain('acme')
  expect(text).toContain(id)
})

test('a session started by hand has no tier and no project', async ($, on) => {
  mock.store(on)
  mock.env(on, {})

  await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
  const id = await $.session.id()

  expect(await $.store.get(`session:${id}`)).toEqual(
    expect.objectContaining({ id, tier: null, project: null, cwd: '/repo' }),
  )
})

test('/fleet with nothing recorded says so', async ($, on) => {
  mock.store(on)
  mock.env(on, {})

  await $.session.start({ cwd: '/repo', surface: null, isInteractive: false })
  await $.store.delete(`session:${await $.session.id()}`)

  const { text } = await $.command.run({ command: 'fleet' })
  expect(text).toBe('No harness sessions recorded.')
})

const test = require('node:test')
const assert = require('node:assert/strict')
const { describe: describeRow } = require('../services/notifyService')

const row = (fields) => ({
    id: '12', actor: 'ada', group_name: 'Dinner', label: 'The Tack Room', amount_cents: 4036,
    group_id: 3, split_id: 9, direct_payment_id: null, read_at: null, created_at: new Date(0), ...fields,
})

test('each kind reads naturally and says where tapping goes', () => {
    const cases = {
        bill_opened: ['ada opened The Tack Room', 'Pick what you had · Dinner', 'group'],
        bill_cancelled: ['ada cancelled The Tack Room', 'Dinner · nobody was charged', 'group'],
        share_charged: ['You paid $40.36 for The Tack Room', 'Dinner · charged to your card', 'payments'],
        share_declined: ['Your card was declined for The Tack Room', 'Open the bill to pick another card', 'group'],
        paid_you: ['ada paid you $40.36', 'The Tack Room · Dinner', 'payments'],
        group_invite: ['ada invited you to Dinner', 'Accept or decline in Groups', 'groups'],
    }
    for (const [kind, [title, body, target]] of Object.entries(cases)) {
        const n = describeRow(row({ kind }))
        assert.deepEqual([n.title, n.body, n.target], [title, body, target], kind)
    }
    const payback = describeRow(row({ kind: 'payback_received', label: 'Concert tickets', group_name: null, amount_cents: 2500 }))
    assert.deepEqual([payback.title, payback.body], ['ada paid you $25.00', 'Concert tickets'])
})

test('ids are numbers and read state is a boolean', () => {
    const n = describeRow(row({ kind: 'paid_you', read_at: new Date() }))
    assert.equal(n.id, 12)
    assert.equal(n.read, true)
})

test('missing details still read sensibly', () => {
    const n = describeRow(row({ kind: 'bill_opened', actor: null, label: null, group_name: null }))
    assert.equal(n.title, 'Someone opened a bill')
    assert.equal(n.body, 'Pick what you had')
})

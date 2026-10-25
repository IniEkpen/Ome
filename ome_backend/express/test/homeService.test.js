const test = require('node:test')
const assert = require('node:assert/strict')
const { stageFor, amountFor } = require('../services/homeService')

const host = { userId: 1, isHost: true, chargeCents: 0, paymentStatus: 'not_required' }
const alice = { userId: 2, isHost: false, chargeCents: 1200, paymentStatus: 'pending' }
const bob = { userId: 3, isHost: false, chargeCents: 800, paymentStatus: 'succeeded' }

const bill = (overrides) => ({
    status: 'claiming',
    mode: 'by_item',
    items: [{ id: 10, claimedBy: [] }],
    participants: [host, alice, bob],
    ...overrides,
})

test('members pick items until they claim something', () => {
    assert.equal(stageFor(bill(), alice), 'pick_items')
    assert.equal(stageFor(bill({ items: [{ id: 10, claimedBy: [2] }] }), alice), 'waiting_on_host')
})

test('even splits have nothing to pick', () => {
    assert.equal(stageFor(bill({ mode: 'even' }), alice), 'waiting_on_host')
})

test('after confirm, members are charging until their payment succeeds', () => {
    assert.equal(stageFor(bill({ status: 'confirmed' }), alice), 'charging')
    assert.equal(stageFor(bill({ status: 'confirmed' }), bob), 'paid')
    assert.equal(stageFor(bill({ status: 'confirmed' }), host), 'charging')
    assert.equal(stageFor(bill({ status: 'settled' }), host), 'paid')
})

test('members see their share; hosts see only what is still coming in', () => {
    assert.equal(amountFor(bill(), alice), 1200)
    assert.equal(amountFor(bill(), host), 1200, "bob already paid, so only alice's share is outstanding")
})

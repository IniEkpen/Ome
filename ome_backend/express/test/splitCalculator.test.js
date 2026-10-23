const test = require('node:test')
const assert = require('node:assert/strict')
const { computeSplit, divideProportionally } = require('../services/splitCalculator')

const host = { userId: 1, isHost: true, waivedCents: 0 }
const alice = { userId: 2, isHost: false, waivedCents: 0 }
const bob = { userId: 3, isHost: false, waivedCents: 0 }

const byUser = (result) => Object.fromEntries(result.perUser.map((u) => [u.userId, u]))
const sumOwed = (result) => result.perUser.reduce((s, u) => s + u.owedCents, 0)

test('even split shares the whole bill and gives leftover pennies to the host', () => {
    const result = computeSplit({
        mode: 'even',
        items: [{ id: 1, quantity: 1, unitPriceCents: 1000, claimedBy: [] }],
        taxCents: 0,
        tipCents: 0,
        participants: [alice, bob, host],
    })
    const users = byUser(result)
    assert.equal(users[1].owedCents, 334)
    assert.equal(users[2].owedCents, 333)
    assert.equal(users[3].owedCents, 333)
    assert.equal(sumOwed(result), 1000)
    assert.equal(users[1].chargeCents, 0, 'host is never charged')
    assert.equal(result.collectedCents, 666)
    assert.equal(result.hostCoveredCents, 334)
})

test('by-item split charges claimers and spreads tax/tip by what they ordered', () => {
    const result = computeSplit({
        mode: 'by_item',
        items: [
            { id: 10, quantity: 1, unitPriceCents: 3000, claimedBy: [2] },
            { id: 11, quantity: 2, unitPriceCents: 500, claimedBy: [3] },
            { id: 12, quantity: 1, unitPriceCents: 900, claimedBy: [2, 3] },
        ],
        taxCents: 490,
        tipCents: 0,
        participants: [host, alice, bob],
    })
    const users = byUser(result)
    assert.equal(users[2].itemsCents, 3450)
    assert.equal(users[3].itemsCents, 1450)
    assert.equal(users[1].itemsCents, 0)
    assert.equal(users[2].extrasCents + users[3].extrasCents, 490)
    assert.equal(users[2].extrasCents, 345)
    assert.equal(sumOwed(result), result.totalCents)
    assert.deepEqual(result.unclaimedItemIds, [])
})

test('unclaimed items are shared by everyone and reported', () => {
    const result = computeSplit({
        mode: 'by_item',
        items: [{ id: 7, quantity: 1, unitPriceCents: 900, claimedBy: [] }],
        participants: [host, alice, bob],
    })
    assert.deepEqual(result.unclaimedItemIds, [7])
    assert.equal(byUser(result)[2].owedCents, 300)
})

test('waivers reduce the charge, are capped at what is owed, and the host covers them', () => {
    const result = computeSplit({
        mode: 'even',
        items: [{ id: 1, quantity: 1, unitPriceCents: 3000, claimedBy: [] }],
        participants: [host, { ...alice, waivedCents: 400 }, { ...bob, waivedCents: 99999 }],
    })
    const users = byUser(result)
    assert.equal(users[2].chargeCents, 600)
    assert.equal(users[3].waivedCents, 1000)
    assert.equal(users[3].chargeCents, 0)
    assert.equal(result.collectedCents, 600)
    assert.equal(result.hostCoveredCents, 2400)
})

test('co-hosts are both exempt from charges', () => {
    const result = computeSplit({
        mode: 'even',
        items: [{ id: 1, quantity: 1, unitPriceCents: 900, claimedBy: [] }],
        participants: [host, { ...alice, isHost: true }, bob],
    })
    assert.equal(result.collectedCents, 300)
})

test('proportional division always sums exactly', () => {
    const weights = new Map([[1, 1], [2, 1], [3, 1]])
    const shares = divideProportionally(100, weights, [1, 2, 3])
    assert.equal([...shares.values()].reduce((a, b) => a + b), 100)
    assert.equal(shares.get(1), 34)
})

// Rules for a split. Everyone in the group can claim items; only hosts can
// change the split mode, waive amounts, confirm, cancel or retry charges.
// Every change is broadcast so all open payment popups stay in sync.
const config = require('../config')
const { pool } = require('../db')
const { HttpError } = require('../auth')
const { group: Group } = require('../models/Group')
const { split: Split, Split: SplitModel } = require('../models/Split')
const { SPLIT_MODES } = require('./splitCalculator')
const { publishSplit } = require('./splitEvents')
const payments = require('./paymentService')
const cards = require('./cardService')
const receipts = require('./receiptService')
const { notify } = require('./notifyService')

const MAX_ITEMS = 100
const MAX_CENTS = 10_000_00 // $10,000 per line / tax / tip

const isInt = (value, min, max) => Number.isInteger(value) && value >= min && value <= max
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/

function validateBill(body) {
    const title = typeof body.title === 'string' ? body.title.trim() : ''
    if (!title || title.length > 255) throw new HttpError(400, 'Give the bill a name.', 'invalid_title')
    const items = Array.isArray(body.items) ? body.items : []
    if (items.length === 0 || items.length > MAX_ITEMS) {
        throw new HttpError(400, `Add between 1 and ${MAX_ITEMS} items.`, 'invalid_items')
    }
    const cleanItems = items.map((item) => {
        const name = typeof item?.name === 'string' ? item.name.trim() : ''
        if (!name || name.length > 255 || !isInt(item.quantity, 1, 99) || !isInt(item.unitPriceCents, 0, MAX_CENTS)) {
            throw new HttpError(400, 'Each item needs a name, a quantity and a price.', 'invalid_items')
        }
        return { name, quantity: item.quantity, unitPriceCents: item.unitPriceCents }
    })
    const taxCents = body.taxCents ?? 0
    const tipCents = body.tipCents ?? 0
    if (!isInt(taxCents, 0, MAX_CENTS) || !isInt(tipCents, 0, MAX_CENTS)) {
        throw new HttpError(400, 'Tax and tip must be valid amounts.', 'invalid_extras')
    }
    // Optional receipt details (e.g. from the OCR service).
    const merchantName = typeof body.merchantName === 'string' ? body.merchantName.trim().slice(0, 255) || null : null
    const receiptDate = typeof body.receiptDate === 'string' && ISO_DATE.test(body.receiptDate)
        && !Number.isNaN(Date.parse(body.receiptDate)) ? body.receiptDate : null
    return { title, merchantName, receiptDate, items: cleanItems, taxCents, tipCents }
}

async function broadcast(splitId) {
    const snapshot = await Split.Snapshot(splitId)
    if (snapshot) publishSplit(snapshot.groupId, snapshot)
    return snapshot
}

async function requireAcceptedMember(groupId, userId) {
    const membership = await Group.GetMembership(groupId, userId)
    if (!membership || membership.status !== 'accepted') {
        throw new HttpError(403, "You're not in this group.", 'not_a_member')
    }
    return membership
}

async function participantRow(client, splitId, userId) {
    const result = await client.query(
        'SELECT is_host FROM split_participants WHERE split_id = $1 AND user_id = $2', [splitId, userId])
    if (result.rowCount === 0) throw new HttpError(403, "You're not part of this bill.", 'not_a_participant')
    return result.rows[0]
}

// Runs a change on an open bill. `hostOnly` limits it to the people footing the bill.
async function changeOpenSplit(user, splitId, { hostOnly }, fn) {
    const outcome = await Split.Mutate(splitId, async (client, split) => {
        const participant = await participantRow(client, splitId, user.id)
        if (hostOnly && !participant.is_host) {
            throw new HttpError(403, 'Only a host can do that.', 'host_only')
        }
        if (split.status !== 'claiming') {
            throw new HttpError(409, 'This bill is already closed.', 'split_closed')
        }
        return fn(client, split)
    })
    if (!outcome) throw new HttpError(404, 'Bill not found.', 'not_found')
    return outcome
}

// The group owner opens a bill. They're always a host and can add co-hosts.
// Everyone currently in the group becomes a participant and sees the popup.
async function startSplit(user, groupId, body) {
    const membership = await requireAcceptedMember(groupId, user.id)
    if (membership.role !== 'owner') {
        throw new HttpError(403, 'Only the group owner can start a bill.', 'owner_only')
    }
    const bill = validateBill(body)
    const receiptId = await receipts.claimForBill(user.id, body.receiptId)
    const members = await Group.AcceptedMembers(groupId)
    const memberIds = members.map((m) => m.id)
    const coHostNames = Array.isArray(body.hostUsernames) ? body.hostUsernames : []
    const coHostIds = members.filter((m) => coHostNames.includes(m.username)).map((m) => m.id)
    const hostIds = [...new Set([user.id, ...coHostIds])]

    let splitId
    try {
        splitId = await Split.CreateSplit({
            groupId,
            createdBy: user.id,
            // Always USD for now; there is no currency conversion anywhere.
            currency: config.stripe.currency,
            hostIds,
            memberIds,
            receiptId,
            ...bill,
        })
    } catch (error) {
        if (error.code === '23505') {
            throw new HttpError(409, 'This group already has an open bill.', 'split_already_open')
        }
        throw error
    }
    const snapshot = await broadcast(splitId)
    await notify(memberIds.filter((id) => id !== user.id), {
        kind: 'bill_opened', key: `bill_opened:${splitId}`, actorId: user.id, groupId, splitId, label: bill.title,
    })
    return snapshot
}

async function getActiveSplit(user, groupId) {
    await requireAcceptedMember(groupId, user.id)
    const splitId = await Split.ActiveSplitIdForGroup(groupId)
    return splitId ? Split.Snapshot(splitId) : null
}

async function getSplit(user, splitId) {
    const snapshot = await Split.Snapshot(splitId)
    if (!snapshot) throw new HttpError(404, 'Bill not found.', 'not_found')
    await requireAcceptedMember(snapshot.groupId, user.id)
    return snapshot
}

// "I had this" toggle from the receipt icon.
async function setClaim(user, splitId, itemId, claimed) {
    await changeOpenSplit(user, splitId, { hostOnly: false }, async (client) => {
        if (!(await Split.ItemBelongsToSplit(client, itemId, splitId))) {
            throw new HttpError(404, 'Item not found.', 'not_found')
        }
        await Split.SetClaim(client, itemId, user.id, Boolean(claimed))
    })
    return broadcast(splitId)
}

async function setMode(user, splitId, mode) {
    if (!SPLIT_MODES.includes(mode)) throw new HttpError(400, 'Unknown split mode.', 'invalid_mode')
    await changeOpenSplit(user, splitId, { hostOnly: true }, (client) => Split.SetMode(client, splitId, mode))
    return broadcast(splitId)
}

// Hosts can forgive any part of what someone owes; it's capped at their share.
async function setWaiver(user, splitId, targetUserId, waivedCents) {
    if (!isInt(waivedCents, 0, MAX_CENTS * MAX_ITEMS)) {
        throw new HttpError(400, 'Enter a valid amount to waive.', 'invalid_amount')
    }
    await changeOpenSplit(user, splitId, { hostOnly: true }, async (client) => {
        if (!(await Split.SetWaiver(client, splitId, targetUserId, waivedCents))) {
            throw new HttpError(400, "Hosts aren't charged, so there's nothing to waive.", 'invalid_target')
        }
    })
    return broadcast(splitId)
}

// Freezes everyone's share, closes claiming, then charges the cards on file.
async function confirmSplit(user, splitId) {
    await changeOpenSplit(user, splitId, { hostOnly: true }, async (client) => {
        const totals = SplitModel.Calculate(await Split.Load(splitId, client))
        await Split.FreezeAmounts(client, splitId, totals.perUser)
        await Split.SetStatus(client, splitId, 'confirmed', user.id)
    })
    await broadcast(splitId)
    const result = await payments.chargeSplit(splitId)
    const snapshot = await broadcast(splitId)
    return { split: snapshot, paymentsSent: result.charged }
}

async function cancelSplit(user, splitId) {
    await changeOpenSplit(user, splitId, { hostOnly: true }, (client) => Split.SetStatus(client, splitId, 'cancelled', user.id))
    const snapshot = await broadcast(splitId)
    if (snapshot) {
        await notify(snapshot.participants.map((p) => p.userId).filter((id) => id !== user.id), {
            kind: 'bill_cancelled', key: `bill_cancelled:${splitId}`, actorId: user.id,
            groupId: snapshot.groupId, splitId, label: snapshot.title,
        })
    }
    return snapshot
}

// After a decline or once Stripe keys are configured, a host can try unpaid shares again.
async function retryCharges(user, splitId) {
    const outcome = await Split.Mutate(splitId, async (client, split) => {
        const participant = await participantRow(client, splitId, user.id)
        if (!participant.is_host) throw new HttpError(403, 'Only a host can do that.', 'host_only')
        if (split.status !== 'confirmed') throw new HttpError(409, 'Nothing to retry.', 'nothing_to_retry')
        await client.query(
            `UPDATE split_participants SET payment_status = 'processing'
             WHERE split_id = $1 AND charge_cents > 0 AND payment_status IN ('pending', 'failed', 'requires_action')`,
            [splitId])
    })
    if (!outcome) throw new HttpError(404, 'Bill not found.', 'not_found')
    const result = await payments.chargeSplit(splitId, `retry-${Date.now()}`)
    return { split: await broadcast(splitId), paymentsSent: result.charged }
}

// A host gives a member back what they paid. The host's payout is pulled back
// from their Stripe balance first (see paymentService.refundPayment).
async function refundParticipant(user, splitId, targetUserId) {
    const snapshot = await Split.Snapshot(splitId)
    if (!snapshot) throw new HttpError(404, 'Bill not found.', 'not_found')
    const participant = await participantRow(pool, splitId, user.id)
    if (!participant.is_host) throw new HttpError(403, 'Only a host can do that.', 'host_only')
    if (!['confirmed', 'settled'].includes(snapshot.status)) {
        throw new HttpError(409, 'Nothing has been paid on this bill.', 'nothing_to_refund')
    }
    await payments.refundPayment(splitId, targetUserId)
    return broadcast(splitId)
}

// Someone picks which of their own cards pays their share of this bill
// (null = their default). Allowed while the bill is open, or after their
// payment failed so the host can retry it on the new card.
async function chooseCard(user, splitId, paymentMethodId) {
    const choice = await cards.checkChoice(user, paymentMethodId)
    const outcome = await Split.Mutate(splitId, async (client, split) => {
        const { rows } = await client.query(
            'SELECT is_host, payment_status FROM split_participants WHERE split_id = $1 AND user_id = $2',
            [splitId, user.id])
        const me = rows[0]
        if (!me) throw new HttpError(403, "You're not part of this bill.", 'not_a_participant')
        if (me.is_host) throw new HttpError(409, "Hosts aren't charged for their own bill.", 'host_not_charged')
        const canChange = split.status === 'claiming'
            || (split.status === 'confirmed' && ['pending', 'failed', 'requires_action'].includes(me.payment_status))
        if (!canChange) throw new HttpError(409, "Your share has already been charged.", 'split_closed')
        await client.query(
            'UPDATE split_participants SET payment_method_id = $3 WHERE split_id = $1 AND user_id = $2',
            [splitId, user.id, choice])
    })
    if (!outcome) throw new HttpError(404, 'Bill not found.', 'not_found')
    return broadcast(splitId)
}

// A host puts an item on someone's share (or takes it off), e.g. from the
// roulette in the bill popup. Adding someone to an item others already have
// makes it shared, the same as if they'd claimed it themselves.
async function assignItem(user, splitId, itemId, targetUserId, claimed) {
    let item
    await changeOpenSplit(user, splitId, { hostOnly: true }, async (client) => {
        const { rows } = await client.query(
            'SELECT name, quantity, unit_price_cents FROM split_items WHERE id = $1 AND split_id = $2', [itemId, splitId])
        item = rows[0]
        if (!item) throw new HttpError(404, 'Item not found.', 'not_found')
        const target = await client.query(
            'SELECT 1 FROM split_participants WHERE split_id = $1 AND user_id = $2', [splitId, targetUserId])
        if (target.rowCount === 0) throw new HttpError(404, "That person isn't part of this bill.", 'not_a_participant')
        await Split.SetClaim(client, itemId, targetUserId, Boolean(claimed))
    })
    const snapshot = await broadcast(splitId)
    if (claimed && targetUserId !== user.id) {
        await notify(targetUserId, {
            kind: 'item_assigned', key: `assign:${splitId}:${itemId}:${targetUserId}:${Date.now()}`,
            actorId: user.id, groupId: snapshot?.groupId ?? null, splitId,
            amountCents: item.quantity * item.unit_price_cents, label: item.name,
        })
    }
    return snapshot
}

module.exports = {
    assignItem,
    chooseCard,
    refundParticipant,
    startSplit,
    getActiveSplit,
    getSplit,
    setClaim,
    setMode,
    setWaiver,
    confirmSplit,
    cancelSplit,
    retryCharges,
    broadcast,
    requireAcceptedMember,
}

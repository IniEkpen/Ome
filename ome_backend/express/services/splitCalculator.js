// Pure bill-splitting math. All money is integer cents so totals always add
// up exactly. Leftover pennies go to hosts first since they are covering the
// bill anyway, then to everyone else in participant order.

const SPLIT_MODES = ['by_item', 'even']

// Hosts first, then by user id, so penny rounding is deterministic.
function orderParticipants(participants) {
    return [...participants].sort((a, b) =>
        (a.isHost === b.isHost ? 0 : a.isHost ? -1 : 1) || a.userId - b.userId)
}

// Splits `amount` across `userIds` (already ordered); the first users get the extra pennies.
function divideEvenly(amount, userIds) {
    const shares = new Map()
    if (userIds.length === 0) return shares
    const base = Math.floor(amount / userIds.length)
    let remainder = amount - base * userIds.length
    for (const id of userIds) {
        shares.set(id, base + (remainder > 0 ? 1 : 0))
        if (remainder > 0) remainder--
    }
    return shares
}

// Splits `amount` in proportion to `weights` (Map userId -> weight) using the
// largest-remainder method so the parts sum to exactly `amount`.
function divideProportionally(amount, weights, orderedIds) {
    const totalWeight = orderedIds.reduce((sum, id) => sum + (weights.get(id) || 0), 0)
    if (totalWeight === 0) return divideEvenly(amount, orderedIds)

    const shares = new Map()
    const fractions = []
    let allocated = 0
    orderedIds.forEach((id, index) => {
        const exact = (amount * (weights.get(id) || 0)) / totalWeight
        const floor = Math.floor(exact)
        shares.set(id, floor)
        allocated += floor
        fractions.push({ id, fraction: exact - floor, index })
    })
    fractions.sort((a, b) => b.fraction - a.fraction || a.index - b.index)
    for (let i = 0; i < amount - allocated; i++) {
        const { id } = fractions[i]
        shares.set(id, shares.get(id) + 1)
    }
    return shares
}

/**
 * @param {object} bill
 * @param {'by_item'|'even'} bill.mode
 * @param {{id:number, quantity:number, unitPriceCents:number, claimedBy:number[]}[]} bill.items
 * @param {number} bill.taxCents
 * @param {number} bill.tipCents
 * @param {{userId:number, isHost:boolean, waivedCents:number}[]} bill.participants
 */
function computeSplit({ mode, items, taxCents = 0, tipCents = 0, participants }) {
    if (!SPLIT_MODES.includes(mode)) throw new Error(`Unknown split mode: ${mode}`)
    if (participants.length === 0) throw new Error('A split needs at least one participant')

    const ordered = orderParticipants(participants)
    const orderedIds = ordered.map((p) => p.userId)
    const isParticipant = new Set(orderedIds)

    const subtotalCents = items.reduce((sum, item) => sum + item.quantity * item.unitPriceCents, 0)
    const extrasCents = taxCents + tipCents
    const totalCents = subtotalCents + extrasCents

    const itemsCents = new Map(orderedIds.map((id) => [id, 0]))
    let extrasShares
    const unclaimedItemIds = []

    if (mode === 'even') {
        const shares = divideEvenly(subtotalCents, orderedIds)
        shares.forEach((cents, id) => itemsCents.set(id, cents))
        extrasShares = divideEvenly(extrasCents, orderedIds)
    } else {
        for (const item of items) {
            const lineCents = item.quantity * item.unitPriceCents
            const claimers = orderedIds.filter((id) => item.claimedBy.includes(id) && isParticipant.has(id))
            // Nobody claimed it: everyone shares it rather than it silently vanishing.
            if (claimers.length === 0) unclaimedItemIds.push(item.id)
            const shares = divideEvenly(lineCents, claimers.length > 0 ? claimers : orderedIds)
            shares.forEach((cents, id) => itemsCents.set(id, itemsCents.get(id) + cents))
        }
        // Tax and tip follow what each person ordered.
        extrasShares = divideProportionally(extrasCents, itemsCents, orderedIds)
    }

    const perUser = ordered.map((p) => {
        const owedCents = itemsCents.get(p.userId) + extrasShares.get(p.userId)
        // Hosts pay the bill directly, so they are never charged through the app.
        const waivedCents = p.isHost ? 0 : Math.min(Math.max(p.waivedCents || 0, 0), owedCents)
        return {
            userId: p.userId,
            isHost: p.isHost,
            itemsCents: itemsCents.get(p.userId),
            extrasCents: extrasShares.get(p.userId),
            owedCents,
            waivedCents,
            chargeCents: p.isHost ? 0 : owedCents - waivedCents,
        }
    })

    const collectedCents = perUser.reduce((sum, u) => sum + u.chargeCents, 0)
    return {
        mode,
        subtotalCents,
        taxCents,
        tipCents,
        totalCents,
        collectedCents,
        hostCoveredCents: totalCents - collectedCents,
        unclaimedItemIds,
        perUser,
    }
}

module.exports = { SPLIT_MODES, computeSplit, divideEvenly, divideProportionally }

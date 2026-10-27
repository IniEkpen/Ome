// The network map: who has paid whom. Public payments form a graph anyone can
// walk; private ones are only shown to the two people involved. Amounts and
// notes are only sent for payments the viewer took part in.
const { pool } = require('../db')

const MAX_DEPTH = 6
const MAX_PEOPLE = 300
const MAX_ROWS_PER_LAYER = 2000

async function publicTransactionsTouching(userIds) {
    const { rows } = await pool.query(
        `SELECT id, sender_id, recipient_id, amount_cents, is_private, note, created_at
         FROM transactions
         WHERE NOT is_private AND (sender_id = ANY($1::int[]) OR recipient_id = ANY($1::int[]))
         ORDER BY created_at DESC LIMIT $2`, [userIds, MAX_ROWS_PER_LAYER])
    return rows
}

// Breadth-first, one query per layer: layer N holds people N payments away.
// Stops after `depth` layers, at MAX_PEOPLE, or once `targetId` is found.
// `parent` maps each person reached to who led there (for rebuilding a path).
async function walk(viewerId, depth, targetId = null) {
    const parent = new Map([[viewerId, null]])
    const transactions = new Map()
    let frontier = [viewerId]
    for (let layer = 0; layer < depth && frontier.length > 0; layer++) {
        const inFrontier = new Set(frontier)
        const next = []
        for (const tx of await publicTransactionsTouching(frontier)) {
            transactions.set(tx.id, tx)
            for (const [from, to] of [[tx.sender_id, tx.recipient_id], [tx.recipient_id, tx.sender_id]]) {
                if (inFrontier.has(from) && !parent.has(to) && parent.size < MAX_PEOPLE) {
                    parent.set(to, from)
                    next.push(to)
                }
            }
        }
        if (targetId !== null && parent.has(targetId)) break
        frontier = next
    }
    return { parent, transactions: [...transactions.values()] }
}

async function parties(userIds) {
    const { rows } = await pool.query(
        `SELECT id, CASE WHEN deleted_at IS NULL THEN username ELSE 'Deleted user' END AS label
         FROM users WHERE id = ANY($1::int[])`, [userIds])
    return rows.map((u) => ({ id: String(u.id), label: u.label }))
}

function toJson(tx, viewerId) {
    const mine = tx.sender_id === viewerId || tx.recipient_id === viewerId
    return {
        id: String(tx.id),
        senderId: String(tx.sender_id),
        recipientId: String(tx.recipient_id),
        amount: mine ? tx.amount_cents / 100 : 0,
        isPrivate: tx.is_private,
        note: mine ? tx.note : null,
        timestamp: tx.created_at,
    }
}

async function payload(viewerId, people, transactions, path = []) {
    return {
        parties: await parties([...people]),
        transactions: transactions.map((tx) => toJson(tx, viewerId)),
        path: path.map(String),
    }
}

async function layer(viewerId, depth) {
    const { parent, transactions } = await walk(viewerId, Math.min(Math.max(depth, 1), MAX_DEPTH))
    // Past MAX_PEOPLE some rows point at people we stopped adding.
    const visible = transactions.filter((tx) => parent.has(tx.sender_id) && parent.has(tx.recipient_id))
    return payload(viewerId, parent.keys(), visible)
}

// Shortest chain of public payments from the viewer to `targetId`, or null.
async function path(viewerId, targetId) {
    if (targetId === viewerId) return payload(viewerId, [viewerId], [], [viewerId])
    const { parent, transactions } = await walk(viewerId, MAX_DEPTH, targetId)
    if (!parent.has(targetId)) return null
    const chain = [targetId]
    while (parent.get(chain[0]) !== null) chain.unshift(parent.get(chain[0]))
    // Only the payments along the chain are sent back.
    const links = new Set(chain.slice(1).map((id, i) => [chain[i], id].sort().join('-')))
    const onPath = transactions.filter((tx) => links.has([tx.sender_id, tx.recipient_id].sort().join('-')))
    return payload(viewerId, chain, onPath, chain)
}

async function myPrivate(viewerId) {
    const { rows } = await pool.query(
        `SELECT id, sender_id, recipient_id, amount_cents, is_private, note, created_at
         FROM transactions
         WHERE is_private AND (sender_id = $1 OR recipient_id = $1)
         ORDER BY created_at DESC LIMIT 500`, [viewerId])
    const people = new Set([viewerId])
    for (const tx of rows) people.add(tx.sender_id).add(tx.recipient_id)
    return payload(viewerId, people, rows)
}

module.exports = { layer, path, myPrivate, MAX_DEPTH }

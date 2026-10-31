// In-app notifications: the inbox behind the bell on Home, delivered live to
// any open app over GET /users/me/events. There's no push service, so
// people see them the next time they open the app.
//
// Rows store what happened (kind, who, which bill/payment), and the wording
// is built when read, so renamed or deleted people always show correctly.
// notify() never throws: a notification must never undo the action behind it.
const { EventEmitter } = require('events')
const { pool } = require('../db')

const PAGE = 30
const emitter = new EventEmitter()
emitter.setMaxListeners(0)
const channel = (userId) => `user:${userId}`

const money = (cents) => `$${(cents / 100).toFixed(2)}`

// Title, body, and where tapping it goes: 'group' (that group's bill),
// 'groups' (the Groups tab) or 'payments' (payment history).
function describe(row) {
    const who = row.actor ?? 'Someone'
    const label = row.label ?? 'a bill'
    const amount = row.amount_cents == null ? '' : money(row.amount_cents)
    const group = row.group_name
    const [title, body, target] = {
        bill_opened: [`${who} opened ${label}`, `Pick what you had${group ? ` · ${group}` : ''}`, 'group'],
        bill_cancelled: [`${who} cancelled ${label}`, group ? `${group} · nobody was charged` : 'Nobody was charged', 'group'],
        share_charged: [`You paid ${amount} for ${label}`, `${group ? `${group} · ` : ''}charged to your card`, 'payments'],
        share_declined: [`Your card was declined for ${label}`, 'Open the bill to pick another card', 'group'],
        paid_you: [`${who} paid you ${amount}`, [label, group].filter(Boolean).join(' · '), 'payments'],
        payback_received: [`${who} paid you ${amount}`, label, 'payments'],
        payback_refunded: [`${who} refunded your ${amount}`, label, 'payments'],
        group_invite: [`${who} invited you to ${group ?? 'a group'}`, 'Accept or decline in Groups', 'groups'],
    }[row.kind] ?? ['Something changed', '', 'payments']
    return {
        id: Number(row.id), // BIGINT arrives as a string
        kind: row.kind,
        title,
        body,
        target,
        groupId: row.group_id,
        splitId: row.split_id,
        directPaymentId: row.direct_payment_id,
        read: row.read_at !== null,
        at: row.created_at,
    }
}

const RENDER = `
    SELECT n.*, CASE WHEN a.deleted_at IS NULL THEN a.username ELSE 'Deleted user' END AS actor,
           g.group_name, COALESCE(s.title, n.label) AS label
    FROM notifications n
    LEFT JOIN users a ON a.id = n.actor_id
    LEFT JOIN groups g ON g.id = n.group_id
    LEFT JOIN splits s ON s.id = n.split_id`

async function unreadCount(userId) {
    const { rows } = await pool.query(
        'SELECT count(*)::int AS n FROM notifications WHERE user_id = $1 AND read_at IS NULL', [userId])
    return rows[0].n
}

/**
 * Adds a notification for each of `userIds` and pushes it to their open app.
 * `key` identifies the event, so repeats (webhook retries) are ignored.
 */
async function notify(userIds, { kind, key, actorId = null, groupId = null, splitId = null, directPaymentId = null,
    amountCents = null, label = null }) {
    const ids = [...new Set((Array.isArray(userIds) ? userIds : [userIds]).filter(Number.isInteger))]
    if (ids.length === 0) return
    try {
        const { rows } = await pool.query(
            `INSERT INTO notifications (user_id, kind, actor_id, group_id, split_id, direct_payment_id,
                                        amount_cents, label, dedupe_key)
             SELECT uid, $2, $3, $4, $5, $6, $7, $8, $9 FROM unnest($1::int[]) AS uid
             ON CONFLICT (user_id, dedupe_key) DO NOTHING
             RETURNING id`,
            [ids, kind, actorId, groupId, splitId, directPaymentId, amountCents,
                typeof label === 'string' ? label.slice(0, 255) : null, key])
        // Only people with the app open right now get it live.
        if (rows.length === 0 || !ids.some((id) => emitter.listenerCount(channel(id)) > 0)) return
        const created = await pool.query(`${RENDER} WHERE n.id = ANY($1::bigint[])`, [rows.map((r) => r.id)])
        for (const row of created.rows) {
            if (emitter.listenerCount(channel(row.user_id)) === 0) continue
            emitter.emit(channel(row.user_id), {
                type: 'notification',
                notification: describe(row),
                unreadCount: await unreadCount(row.user_id),
            })
        }
    } catch (error) {
        console.error(`Notification ${kind} (${key}) failed:`, error.message)
    }
}

/** Newest first; pass `before` (the last id seen) for the next page. */
async function list(userId, { before, limit } = {}) {
    const size = Math.min(Math.max(Number(limit) || PAGE, 1), 100)
    const beforeId = Number.isInteger(Number(before)) && Number(before) > 0 ? Number(before) : null
    const { rows } = await pool.query(
        `${RENDER} WHERE n.user_id = $1 AND ($2::bigint IS NULL OR n.id < $2) ORDER BY n.id DESC LIMIT $3`,
        [userId, beforeId, size + 1])
    const page = rows.slice(0, size)
    return {
        items: page.map(describe),
        unreadCount: await unreadCount(userId),
        nextBefore: rows.length > size ? Number(page[page.length - 1].id) : null,
    }
}

/** Marks some (`ids`) or all of a user's notifications read. */
async function markRead(userId, { ids, all } = {}) {
    if (all === true) {
        await pool.query('UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL', [userId])
    } else if (Array.isArray(ids) && ids.length > 0) {
        await pool.query(
            `UPDATE notifications SET read_at = now()
             WHERE user_id = $1 AND read_at IS NULL AND id = ANY($2::bigint[])`,
            [userId, ids.filter((id) => Number.isInteger(id))])
    }
    const count = await unreadCount(userId)
    emitter.emit(channel(userId), { type: 'read', unreadCount: count })
    return count
}

function subscribe(userId, listener) {
    emitter.on(channel(userId), listener)
    return () => emitter.off(channel(userId), listener)
}

module.exports = { notify, list, markRead, unreadCount, subscribe, describe }

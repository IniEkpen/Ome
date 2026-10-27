// The home page: bills that still need something from you, and recent
// activity (payments, waivers, people joining your groups).
const { pool } = require('../db')
const { split: Split } = require('../models/Split')

const BILL_LIMIT = 20
const ACTIVITY_LIMIT = 20
const DONE = ['succeeded', 'not_required']

// Where a bill is, from this person's point of view.
function stageFor(snapshot, me) {
    if (snapshot.status === 'claiming') {
        const claimed = snapshot.items.some((item) => item.claimedBy.includes(me.userId))
        return snapshot.mode === 'by_item' && !claimed ? 'pick_items' : 'waiting_on_host'
    }
    if (me.isHost) return snapshot.status === 'settled' ? 'paid' : 'charging'
    return DONE.includes(me.paymentStatus) ? 'paid' : 'charging'
}

// Members see their share; hosts see what's still coming in to them.
function amountFor(snapshot, me) {
    if (!me.isHost) return me.chargeCents ?? 0
    return snapshot.participants
        .filter((p) => !p.isHost && !DONE.includes(p.paymentStatus))
        .reduce((sum, p) => sum + (p.chargeCents ?? 0), 0)
}

async function openBills(userId) {
    const { rows } = await pool.query(
        `SELECT s.id, g.group_name
         FROM split_participants p
         JOIN splits s ON s.id = p.split_id
         JOIN groups g ON g.id = s.group_id
         WHERE p.user_id = $1 AND s.status IN ('claiming', 'confirmed')
         ORDER BY s.created_at DESC LIMIT $2`, [userId, BILL_LIMIT])
    const bills = await Promise.all(rows.map(async (row) => {
        const snapshot = await Split.Snapshot(row.id)
        const me = snapshot?.participants.find((p) => p.userId === userId)
        if (!me) return null
        return {
            splitId: snapshot.id,
            groupId: snapshot.groupId,
            groupName: row.group_name,
            title: snapshot.title,
            stage: stageFor(snapshot, me),
            amountCents: amountFor(snapshot, me),
            people: snapshot.participants.length,
            isHost: me.isHost,
        }
    }))
    return bills.filter(Boolean)
}

// Built from the tables that already record each event, so there's no
// separate feed to keep in sync.
async function recentActivity(userId) {
    const { rows } = await pool.query(
        `SELECT * FROM (
            SELECT CASE WHEN t.sender_id = $1 THEN 'you_paid' ELSE 'paid_you' END AS kind,
                   CASE WHEN other.deleted_at IS NULL THEN other.username ELSE 'Deleted user' END AS who,
                   g.group_name, t.amount_cents, t.created_at AS at
            FROM transactions t
            JOIN users other ON other.id = CASE WHEN t.sender_id = $1 THEN t.recipient_id ELSE t.sender_id END
            LEFT JOIN groups g ON g.id = t.group_id
            WHERE t.sender_id = $1 OR t.recipient_id = $1

            UNION ALL
            SELECT 'waived', COALESCE(host.username, 'A host'), g.group_name, p.waived_cents, s.confirmed_at
            FROM split_participants p
            JOIN splits s ON s.id = p.split_id
            JOIN groups g ON g.id = s.group_id
            LEFT JOIN users host ON host.id = s.confirmed_by
            WHERE p.user_id = $1 AND p.waived_cents > 0 AND s.confirmed_at IS NOT NULL

            UNION ALL
            SELECT 'joined', u.username, g.group_name, 0, other.joined_at
            FROM groupmembers mine
            JOIN groupmembers other ON other.group_id = mine.group_id AND other.user_id <> mine.user_id
            JOIN users u ON u.id = other.user_id
            JOIN groups g ON g.id = mine.group_id
            WHERE mine.user_id = $1 AND mine.status = 'accepted'
              AND other.status = 'accepted' AND other.role <> 'owner' AND other.joined_at IS NOT NULL
         ) feed
         ORDER BY at DESC LIMIT $2`, [userId, ACTIVITY_LIMIT])
    return rows.map((row) => ({
        kind: row.kind,
        who: row.who,
        groupName: row.group_name ?? 'Deleted group',
        amountCents: row.amount_cents,
        at: row.at,
    }))
}

async function homeFor(user) {
    const [bills, activity] = await Promise.all([openBills(user.id), recentActivity(user.id)])
    return { bills, activity }
}

module.exports = { homeFor, stageFor, amountFor }

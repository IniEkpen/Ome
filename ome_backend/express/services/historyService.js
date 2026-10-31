// Payment history: every payment in or out, newest first.
//   - Pay-backs (direct_payments) in every state. Failed or pending attempts
//     are only shown to the payer; the recipient sees what actually arrived.
//   - Completed bill payments (transactions from a bill). A refunded bill
//     payment drops off, as it no longer happened.
// Paged with `before`, the previous page's `nextBefore`.
const { pool } = require('../db')

const PAGE = 30
const RECIPIENT_SEES = ['succeeded', 'refunded', 'disputed']

// Microsecond text timestamps, so paging never skips two payments made in
// the same millisecond (a JS Date would round them together).
const cursor = (column) => `to_char(${column} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`
const otherName = (alias) => `CASE WHEN ${alias}.deleted_at IS NULL THEN ${alias}.username ELSE 'Deleted user' END`

async function history(userId, { before, limit = PAGE } = {}) {
    const size = Math.min(Math.max(Number(limit) || PAGE, 1), 100)
    const beforeAt = typeof before === 'string' && !Number.isNaN(Date.parse(before)) ? before : null
    const { rows } = await pool.query(
        `SELECT * FROM (
            SELECT 'payback' AS kind, d.id, d.created_at AS at, ${cursor('d.created_at')} AS cursor,
                   CASE WHEN d.payer_id = $1 THEN 'out' ELSE 'in' END AS direction,
                   other.id AS other_id, ${otherName('other')} AS other_username,
                   d.amount_cents, d.note, NULL AS group_name, d.status, d.payment_error_code
            FROM direct_payments d
            JOIN users other ON other.id = CASE WHEN d.payer_id = $1 THEN d.recipient_id ELSE d.payer_id END
            WHERE d.payer_id = $1 OR (d.recipient_id = $1 AND d.status = ANY($4))

            UNION ALL
            SELECT 'bill', t.id, t.created_at, ${cursor('t.created_at')},
                   CASE WHEN t.sender_id = $1 THEN 'out' ELSE 'in' END,
                   other.id, ${otherName('other')},
                   t.amount_cents, t.note, g.group_name, 'succeeded', NULL
            FROM transactions t
            JOIN users other ON other.id = CASE WHEN t.sender_id = $1 THEN t.recipient_id ELSE t.sender_id END
            LEFT JOIN groups g ON g.id = t.group_id
            WHERE (t.sender_id = $1 OR t.recipient_id = $1) AND t.direct_payment_id IS NULL
         ) items
         WHERE $2::timestamptz IS NULL OR at < $2::timestamptz
         ORDER BY at DESC, kind, id DESC
         LIMIT $3`, [userId, beforeAt, size + 1, RECIPIENT_SEES])
    const page = rows.slice(0, size)
    return {
        items: page.map((row) => ({
            kind: row.kind,
            // transactions.id is a BIGINT, which node-postgres returns as a string.
            id: Number(row.id),
            direction: row.direction,
            other: { id: String(row.other_id), username: row.other_username },
            amountCents: row.amount_cents,
            note: row.note,
            groupName: row.group_name,
            status: row.status,
            errorCode: row.direction === 'out' ? row.payment_error_code : null,
            at: row.at,
            // Only the person who received a pay-back can give it back.
            canRefund: row.kind === 'payback' && row.direction === 'in' && row.status === 'succeeded',
        })),
        nextBefore: rows.length > size ? page[page.length - 1].cursor : null,
    }
}

module.exports = { history }

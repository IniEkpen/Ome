// A bill inside a group: its items, who claimed what, who is hosting, and
// (once a host confirms) what each person is charged.
const { pool, withTransaction } = require('../db')
const { computeSplit } = require('../services/splitCalculator')
const { Profile } = require('./Profile')

class Split {
    constructor(pool) {
        this.pool = pool
    }

    async CreateSplit({
        groupId, createdBy, title, merchantName, receiptDate, currency, taxCents, tipCents, items, hostIds, memberIds,
    }) {
        return withTransaction(async (client) => {
            const created = await client.query(
                `INSERT INTO splits (group_id, created_by, title, merchant_name, receipt_date, currency, tax_cents, tip_cents)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
                [groupId, createdBy, title, merchantName, receiptDate, currency, taxCents, tipCents])
            const splitId = created.rows[0].id
            await client.query(
                `INSERT INTO split_participants (split_id, user_id, is_host)
                 SELECT $1, member_id, member_id = ANY($3::int[]) FROM unnest($2::int[]) AS member_id`,
                [splitId, memberIds, hostIds])
            await client.query(
                `INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position)
                 SELECT $1, i.name, i.quantity, i.unit_price_cents, i.position
                 FROM jsonb_to_recordset($2::jsonb) AS i(name text, quantity int, unit_price_cents int, position int)`,
                [splitId, JSON.stringify(items.map((item, position) => ({
                    name: item.name,
                    quantity: item.quantity,
                    unit_price_cents: item.unitPriceCents,
                    position,
                })))])
            return splitId
        })
    }

    // Latest bill that still needs attention (open for claiming, or confirmed but not fully paid).
    async ActiveSplitIdForGroup(groupId) {
        const result = await this.pool.query(
            `SELECT id FROM splits WHERE group_id = $1 AND status IN ('claiming', 'confirmed')
             ORDER BY id DESC LIMIT 1`, [groupId])
        return result.rows[0]?.id ?? null
    }

    // Locks the split row, runs fn, and bumps the version so live clients refresh.
    async Mutate(splitId, fn) {
        return withTransaction(async (client) => {
            const locked = await client.query('SELECT * FROM splits WHERE id = $1 FOR UPDATE', [splitId])
            const split = locked.rows[0]
            if (!split) return null
            const result = await fn(client, split)
            await client.query('UPDATE splits SET version = version + 1 WHERE id = $1', [splitId])
            return { split, result }
        })
    }

    async Load(splitId, client = this.pool) {
        // Sequential on purpose: `client` may be a single transaction connection.
        const splitResult = await client.query('SELECT * FROM splits WHERE id = $1', [splitId])
        const split = splitResult.rows[0]
        if (!split) return null
        const itemsResult = await client.query(
            'SELECT * FROM split_items WHERE split_id = $1 ORDER BY position, id', [splitId])
        const claimsResult = await client.query(
            `SELECT c.item_id, c.user_id FROM split_item_claims c
             JOIN split_items i ON i.id = c.item_id WHERE i.split_id = $1`, [splitId])
        const participantsResult = await client.query(
            `SELECT p.*, u.username, u.default_payment_method_id, u.card_exp_month, u.card_exp_year
             FROM split_participants p JOIN users u ON u.id = p.user_id
             WHERE p.split_id = $1 ORDER BY p.is_host DESC, u.username`, [splitId])
        const claimsByItem = new Map()
        for (const { item_id: itemId, user_id: userId } of claimsResult.rows) {
            if (!claimsByItem.has(itemId)) claimsByItem.set(itemId, [])
            claimsByItem.get(itemId).push(userId)
        }
        const items = itemsResult.rows.map((row) => ({
            id: row.id,
            name: row.name,
            quantity: row.quantity,
            unitPriceCents: row.unit_price_cents,
            claimedBy: claimsByItem.get(row.id) || [],
        }))
        return { split, items, participants: participantsResult.rows }
    }

    // Live math while claiming; frozen amounts once a host has confirmed.
    static Calculate({ split, items, participants }) {
        return computeSplit({
            mode: split.split_mode,
            items,
            taxCents: split.tax_cents,
            tipCents: split.tip_cents,
            participants: participants.map((p) => ({
                userId: p.user_id,
                isHost: p.is_host,
                waivedCents: p.waived_cents,
            })),
        })
    }

    // The JSON every client renders. Same for every viewer, so it can be broadcast.
    async Snapshot(splitId, client = this.pool) {
        const loaded = await this.Load(splitId, client)
        if (!loaded) return null
        const { split, items, participants } = loaded
        const totals = Split.Calculate(loaded)
        const live = new Map(totals.perUser.map((u) => [u.userId, u]))
        const frozen = split.status !== 'claiming'
        return {
            id: split.id,
            groupId: split.group_id,
            title: split.title,
            merchantName: split.merchant_name,
            receiptDate: split.receipt_date,
            status: split.status,
            mode: split.split_mode,
            currency: split.currency,
            taxCents: split.tax_cents,
            tipCents: split.tip_cents,
            version: split.version,
            createdBy: split.created_by,
            items: items.map((item) => ({ ...item, totalCents: item.quantity * item.unitPriceCents })),
            participants: participants.map((p) => {
                const calc = live.get(p.user_id)
                return {
                    userId: p.user_id,
                    username: p.username,
                    isHost: p.is_host,
                    owedCents: frozen ? p.owed_cents : calc.owedCents,
                    waivedCents: frozen ? p.waived_cents : calc.waivedCents,
                    chargeCents: frozen ? p.charge_cents : calc.chargeCents,
                    paymentStatus: p.payment_status,
                    // Lets hosts spot anyone whose card expired since they joined.
                    cardOnFile: Profile.HasValidCard(p),
                }
            }),
            totals: {
                subtotalCents: totals.subtotalCents,
                totalCents: totals.totalCents,
                collectedCents: frozen
                    ? participants.reduce((sum, p) => sum + (p.charge_cents || 0), 0)
                    : totals.collectedCents,
                unclaimedItemIds: totals.unclaimedItemIds,
            },
        }
    }

    async SetClaim(client, itemId, userId, claimed) {
        if (claimed) {
            await client.query(
                'INSERT INTO split_item_claims (item_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
                [itemId, userId])
        } else {
            await client.query('DELETE FROM split_item_claims WHERE item_id = $1 AND user_id = $2', [itemId, userId])
        }
    }

    async ItemBelongsToSplit(client, itemId, splitId) {
        const result = await client.query('SELECT 1 FROM split_items WHERE id = $1 AND split_id = $2', [itemId, splitId])
        return result.rowCount > 0
    }

    async SetMode(client, splitId, mode) {
        await client.query('UPDATE splits SET split_mode = $1 WHERE id = $2', [mode, splitId])
    }

    async SetWaiver(client, splitId, userId, waivedCents) {
        const result = await client.query(
            `UPDATE split_participants SET waived_cents = $3
             WHERE split_id = $1 AND user_id = $2 AND NOT is_host`, [splitId, userId, waivedCents])
        return result.rowCount > 0
    }

    // `byUserId` is the host making the change (recorded on confirm).
    async SetStatus(client, splitId, status, byUserId) {
        await client.query(
            `UPDATE splits SET status = $2::varchar,
                confirmed_at = CASE WHEN $2::varchar = 'confirmed' THEN now() ELSE confirmed_at END,
                confirmed_by = CASE WHEN $2::varchar = 'confirmed' THEN $3::int ELSE confirmed_by END,
                cancelled_at = CASE WHEN $2::varchar = 'cancelled' THEN now() ELSE cancelled_at END
             WHERE id = $1`, [splitId, status, byUserId])
    }

    // Freezes each person's amount. People with nothing to pay are marked not_required.
    async FreezeAmounts(client, splitId, perUser) {
        for (const u of perUser) {
            await client.query(
                `UPDATE split_participants
                 SET owed_cents = $3, waived_cents = $4, charge_cents = $5,
                     payment_status = CASE WHEN $5 > 0 THEN 'processing' ELSE 'not_required' END
                 WHERE split_id = $1 AND user_id = $2`,
                [splitId, u.userId, u.owedCents, u.waivedCents, u.chargeCents])
        }
    }

    async ParticipantsToCharge(splitId) {
        const result = await this.pool.query(
            `SELECT p.user_id, p.charge_cents, u.stripe_customer_id, u.default_payment_method_id, s.currency
             FROM split_participants p
             JOIN users u ON u.id = p.user_id
             JOIN splits s ON s.id = p.split_id
             WHERE p.split_id = $1 AND p.charge_cents > 0 AND p.payment_status = 'processing'`, [splitId])
        return result.rows
    }

    async Hosts(splitId) {
        const result = await this.pool.query(
            `SELECT u.id, u.stripe_connect_account_id, u.payouts_enabled
             FROM split_participants p JOIN users u ON u.id = p.user_id
             WHERE p.split_id = $1 AND p.is_host ORDER BY u.id`, [splitId])
        return result.rows
    }

    // `errorCode` is Stripe's decline code; it's cleared once a charge succeeds.
    // Refunded and disputed payments are only changed by paymentService directly.
    async SetPaymentStatus(splitId, userId, status, paymentIntentId, errorCode) {
        await this.pool.query(
            `UPDATE split_participants
             SET payment_status = $3::varchar,
                 stripe_payment_intent_id = COALESCE($4, stripe_payment_intent_id),
                 payment_error_code = CASE WHEN $3::varchar = 'succeeded' THEN NULL
                                           ELSE COALESCE($5, payment_error_code) END,
                 paid_at = CASE WHEN $3::varchar = 'succeeded' THEN COALESCE(paid_at, now()) ELSE paid_at END
             WHERE split_id = $1 AND user_id = $2 AND payment_status NOT IN ('refunded', 'disputed')`,
            [splitId, userId, status, paymentIntentId || null, errorCode || null])
    }

    // Marks the bill settled once nobody is still waiting to be charged.
    async SettleIfComplete(splitId) {
        const result = await this.pool.query(
            `UPDATE splits SET status = 'settled', settled_at = now(), version = version + 1
             WHERE id = $1 AND status = 'confirmed'
               AND NOT EXISTS (SELECT 1 FROM split_participants
                               WHERE split_id = $1 AND payment_status IN ('pending', 'processing', 'requires_action', 'failed'))
             RETURNING id`, [splitId])
        return result.rowCount > 0
    }

    async BumpVersion(splitId) {
        await this.pool.query('UPDATE splits SET version = version + 1 WHERE id = $1', [splitId])
    }
}

const split = new Split(pool)
module.exports = { split, Split }

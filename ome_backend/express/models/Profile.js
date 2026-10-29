const { pool } = require('../db')

const PUBLIC_COLUMNS = `id, username, first_name, last_name, email, phone, transactions_private,
    stripe_customer_id, default_payment_method_id,
    card_brand, card_last4, card_exp_month, card_exp_year,
    stripe_connect_account_id, payouts_enabled, connect_transfers_status, connect_payouts_status,
    connect_requirements_due, created_at`

// Fields a user may change about themselves, mapped to their columns.
const EDITABLE = {
    firstName: 'first_name',
    lastName: 'last_name',
    phone: 'phone',
    transactionsPrivate: 'transactions_private',
}

class Profile {
    constructor(pool) {
        this.pool = pool
    }

    // Usernames are matched ignoring case (see users_username_lower_key).
    // Includes the password hash, for login only.
    async GetProfileWithPassword(username) {
        const result = await this.pool.query(
            `SELECT ${PUBLIC_COLUMNS}, password FROM users WHERE lower(username) = lower($1) AND deleted_at IS NULL`, [username])
        return result.rows[0] || null
    }

    async GetProfileById(userId) {
        const result = await this.pool.query(
            `SELECT ${PUBLIC_COLUMNS} FROM users WHERE id = $1 AND deleted_at IS NULL`, [userId])
        return result.rows[0] || null
    }

    async GetProfilesByUsernames(usernames) {
        const result = await this.pool.query(
            `SELECT id, username FROM users
             WHERE lower(username) = ANY(SELECT lower(name) FROM unnest($1::text[]) AS name)
               AND deleted_at IS NULL`, [usernames])
        return result.rows
    }

    // Username search for pickers and the network map. Matches any username that
    // contains the typed letters in order, ranked exact > prefix > substring > in-order.
    async SearchByUsername(query, excludeUserId, limit = 10) {
        // '_' is allowed in usernames but is a LIKE wildcard, so escape it.
        const escape = (s) => s.replace(/[\\%_]/g, (c) => `\\${c}`)
        const q = query.toLowerCase()
        const inOrder = `%${[...q].map(escape).join('%')}%`
        const result = await this.pool.query(
            `SELECT id, username, first_name, last_name FROM users
             WHERE lower(username) LIKE $2 AND id <> $3 AND deleted_at IS NULL
             ORDER BY CASE
                        WHEN lower(username) = $1 THEN 0
                        WHEN lower(username) LIKE $4 || '%' THEN 1
                        WHEN lower(username) LIKE '%' || $4 || '%' THEN 2
                        ELSE 3
                      END,
                      length(username), lower(username)
             LIMIT $5`, [q, inOrder, excludeUserId, escape(q), limit])
        return result.rows
    }

    async UsernameOrEmailTaken(username, email) {
        const result = await this.pool.query(
            'SELECT 1 FROM users WHERE lower(username) = lower($1) OR lower(email) = lower($2)', [username, email])
        return result.rowCount > 0
    }

    async CreateProfile({ username, firstName, lastName, email, phone, passwordHash }) {
        const result = await this.pool.query(
            `INSERT INTO users (username, first_name, last_name, email, phone, password)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, username`,
            [username, firstName, lastName, email, phone, passwordHash])
        return result.rows[0]
    }

    // `changes` uses the API's names (see EDITABLE); unknown keys are ignored.
    async UpdateProfile(userId, changes) {
        const entries = Object.entries(changes).filter(([key]) => key in EDITABLE)
        if (entries.length === 0) return this.GetProfileById(userId)
        const sets = entries.map(([key], i) => `${EDITABLE[key]} = $${i + 2}`)
        const result = await this.pool.query(
            `UPDATE users SET ${sets.join(', ')} WHERE id = $1 RETURNING ${PUBLIC_COLUMNS}`,
            [userId, ...entries.map(([, value]) => value)])
        return result.rows[0] || null
    }

    async RecordLogin(userId) {
        await this.pool.query('UPDATE users SET last_login_at = now() WHERE id = $1', [userId])
    }

    // Account deletion: removes everything that identifies the person but
    // keeps the row, so the other side of each past payment still has it.
    // Their payments are made private so they drop off the network map.
    async Scrub(client, userId) {
        await client.query('UPDATE transactions SET is_private = true WHERE sender_id = $1 OR recipient_id = $1', [userId])
        await client.query(
            `UPDATE users SET username = 'deleted_' || id, first_name = NULL, last_name = NULL,
                email = NULL, phone = NULL, password = NULL, transactions_private = true,
                stripe_customer_id = NULL, default_payment_method_id = NULL, card_brand = NULL,
                card_last4 = NULL, card_exp_month = NULL, card_exp_year = NULL,
                stripe_connect_account_id = NULL, payouts_enabled = false,
                google_sub = NULL, apple_sub = NULL, apple_refresh_token = NULL, deleted_at = now()
             WHERE id = $1`, [userId])
    }

    async IsActive(userId) {
        const result = await this.pool.query('SELECT 1 FROM users WHERE id = $1 AND deleted_at IS NULL', [userId])
        return result.rowCount > 0
    }

    async UpdatePasswordHash(userId, passwordHash) {
        await this.pool.query('UPDATE users SET password = $1 WHERE id = $2', [passwordHash, userId])
    }

    // A card counts only if Stripe gave us a payment method and it hasn't expired.
    static HasValidCard(user, now = new Date()) {
        if (!user || !user.default_payment_method_id) return false
        if (!user.card_exp_year || !user.card_exp_month) return true
        const year = now.getUTCFullYear()
        const month = now.getUTCMonth() + 1
        return user.card_exp_year > year || (user.card_exp_year === year && user.card_exp_month >= month)
    }

    static CardSummary(user) {
        return {
            hasValidCard: Profile.HasValidCard(user),
            brand: user?.card_brand || null,
            last4: user?.card_last4 || null,
            expMonth: user?.card_exp_month || null,
            expYear: user?.card_exp_year || null,
            payoutsEnabled: Boolean(user?.payouts_enabled),
        }
    }

    // What a host sees about their payout account.
    static ConnectSummary(user) {
        return {
            hasAccount: Boolean(user?.stripe_connect_account_id),
            payoutsEnabled: Boolean(user?.payouts_enabled),
            transfersStatus: user?.connect_transfers_status || null,
            bankPayoutsStatus: user?.connect_payouts_status || null,
            requirementsDue: Boolean(user?.connect_requirements_due),
        }
    }

    async SetStripeCustomer(userId, stripeCustomerId) {
        await this.pool.query('UPDATE users SET stripe_customer_id = $1 WHERE id = $2', [stripeCustomerId, userId])
    }

    async SetDefaultCard(stripeCustomerId, card) {
        const result = await this.pool.query(
            `UPDATE users SET default_payment_method_id = $1, card_brand = $2, card_last4 = $3,
                card_exp_month = $4, card_exp_year = $5
             WHERE stripe_customer_id = $6 RETURNING id`,
            [card.paymentMethodId, card.brand, card.last4, card.expMonth, card.expYear, stripeCustomerId])
        return result.rows[0] || null
    }

    async SetConnectAccount(userId, accountId) {
        await this.pool.query('UPDATE users SET stripe_connect_account_id = $1 WHERE id = $2', [accountId, userId])
    }

    // Returns the host and whether they just became able to receive transfers.
    async SyncConnectStatus(accountId, { transfersStatus, payoutsStatus, requirementsDue }) {
        const result = await this.pool.query(
            `UPDATE users u SET payouts_enabled = COALESCE($2::varchar = 'active', false), connect_transfers_status = $2::varchar,
                connect_payouts_status = $3, connect_requirements_due = $4
             FROM (SELECT id, payouts_enabled AS was_enabled FROM users WHERE stripe_connect_account_id = $1) old
             WHERE u.id = old.id
             RETURNING u.id, u.payouts_enabled, old.was_enabled`,
            [accountId, transfersStatus, payoutsStatus, requirementsDue])
        const row = result.rows[0]
        return row ? { id: row.id, payoutsEnabled: row.payouts_enabled, newlyEnabled: row.payouts_enabled && !row.was_enabled } : null
    }
}

const profile = new Profile(pool)
module.exports = { profile, Profile }

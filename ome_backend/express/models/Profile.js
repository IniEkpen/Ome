const { pool } = require('../db')

const PUBLIC_COLUMNS = `id, username, first_name, last_name, email, phone, transactions_private,
    stripe_customer_id, default_payment_method_id,
    card_brand, card_last4, card_exp_month, card_exp_year,
    stripe_connect_account_id, payouts_enabled, created_at`

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
            `SELECT ${PUBLIC_COLUMNS}, password FROM users WHERE lower(username) = lower($1)`, [username])
        return result.rows[0] || null
    }

    async GetProfileById(userId) {
        const result = await this.pool.query(`SELECT ${PUBLIC_COLUMNS} FROM users WHERE id = $1`, [userId])
        return result.rows[0] || null
    }

    async GetProfilesByUsernames(usernames) {
        const result = await this.pool.query(
            `SELECT id, username FROM users
             WHERE lower(username) = ANY(SELECT lower(name) FROM unnest($1::text[]) AS name)`, [usernames])
        return result.rows
    }

    // Prefix match for "find a person" on the network map.
    async SearchByUsername(query, excludeUserId, limit = 10) {
        // '_' is allowed in usernames but is a LIKE wildcard, so escape it.
        const prefix = query.toLowerCase().replace(/[\\%_]/g, (c) => `\\${c}`)
        const result = await this.pool.query(
            `SELECT id, username, first_name, last_name FROM users
             WHERE lower(username) LIKE $1 || '%' AND id <> $2
             ORDER BY lower(username) LIMIT $3`, [prefix, excludeUserId, limit])
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

    async SetPayoutsEnabled(accountId, enabled) {
        const result = await this.pool.query(
            'UPDATE users SET payouts_enabled = $1 WHERE stripe_connect_account_id = $2 RETURNING id',
            [enabled, accountId])
        return result.rows[0] || null
    }
}

const profile = new Profile(pool)
module.exports = { profile, Profile }

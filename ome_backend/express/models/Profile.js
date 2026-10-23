const { pool } = require('../db')

const PUBLIC_COLUMNS = `id, username, email, stripe_customer_id, default_payment_method_id,
    card_brand, card_last4, card_exp_month, card_exp_year,
    stripe_connect_account_id, payouts_enabled`

class Profile {
    constructor(pool) {
        this.pool = pool
    }

    // Get profile of user with the name (includes the password hash, for login only)
    async GetProfileWithPassword(username) {
        const result = await this.pool.query(
            `SELECT ${PUBLIC_COLUMNS}, password FROM users WHERE username = $1`, [username])
        return result.rows[0] || null
    }

    async GetProfileById(userId) {
        const result = await this.pool.query(`SELECT ${PUBLIC_COLUMNS} FROM users WHERE id = $1`, [userId])
        return result.rows[0] || null
    }

    async GetProfilesByUsernames(usernames) {
        const result = await this.pool.query(
            'SELECT id, username FROM users WHERE username = ANY($1::text[])', [usernames])
        return result.rows
    }

    async UsernameOrEmailTaken(username, email) {
        const result = await this.pool.query(
            'SELECT 1 FROM users WHERE username = $1 OR (email IS NOT NULL AND email = $2)', [username, email])
        return result.rowCount > 0
    }

    async CreateProfile(username, email, phone, passwordHash) {
        const result = await this.pool.query(
            `INSERT INTO users (username, email, phone, password, card_info)
             VALUES ($1, $2, $3, $4, 'no') RETURNING id, username`,
            [username, email, phone, passwordHash])
        return result.rows[0]
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
                card_exp_month = $4, card_exp_year = $5, card_info = 'yes'
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

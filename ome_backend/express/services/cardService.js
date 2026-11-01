// Several saved cards per person. One is the default (kept on `users`, which
// the card gate and charges read); in each bill a person can pick another of
// their cards for their share (split_participants.payment_method_id).
const { pool, withTransaction } = require('../db')
const { HttpError } = require('../auth')
const { profile } = require('../models/Profile')
const { getStripe, isStripeConfigured } = require('./stripeClient')

function expired(card, now = new Date()) {
    if (!card.exp_year || !card.exp_month) return false
    const year = now.getUTCFullYear()
    const month = now.getUTCMonth() + 1
    return card.exp_year < year || (card.exp_year === year && card.exp_month < month)
}

function toJson(card, defaultId) {
    return {
        id: card.stripe_payment_method_id,
        brand: card.brand,
        last4: card.last4,
        expMonth: card.exp_month,
        expYear: card.exp_year,
        isDefault: card.stripe_payment_method_id === defaultId,
        expired: expired(card),
    }
}

async function cardRows(userId) {
    const { rows } = await pool.query(
        'SELECT * FROM user_cards WHERE user_id = $1 ORDER BY created_at DESC', [userId])
    return rows
}

/** The user's cards, default first. */
async function listCards(user) {
    const rows = await cardRows(user.id)
    // A default saved before user_cards existed (or by the seed) still counts.
    if (user.default_payment_method_id && !rows.some((r) => r.stripe_payment_method_id === user.default_payment_method_id)) {
        rows.push({
            stripe_payment_method_id: user.default_payment_method_id, brand: user.card_brand, last4: user.card_last4,
            exp_month: user.card_exp_month, exp_year: user.card_exp_year,
        })
    }
    return rows
        .map((row) => toJson(row, user.default_payment_method_id))
        .sort((a, b) => Number(b.isDefault) - Number(a.isDefault))
}

/** Called whenever a card is saved through Stripe: remembered in the list. */
async function rememberCard(userId, card) {
    await pool.query(
        `INSERT INTO user_cards (stripe_payment_method_id, user_id, brand, last4, exp_month, exp_year)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (stripe_payment_method_id) DO UPDATE SET brand = EXCLUDED.brand, last4 = EXCLUDED.last4,
             exp_month = EXCLUDED.exp_month, exp_year = EXCLUDED.exp_year`,
        [card.paymentMethodId, userId, card.brand, card.last4, card.expMonth, card.expYear])
}

async function ownedCard(user, paymentMethodId) {
    const card = (await listCards(user)).find((c) => c.id === paymentMethodId)
    if (!card) throw new HttpError(404, "We couldn't find that card.", 'card_not_found')
    return card
}

async function makeDefault(user, card) {
    if (user.stripe_customer_id && isStripeConfigured()) {
        await getStripe().customers.update(user.stripe_customer_id, {
            invoice_settings: { default_payment_method: card.id },
        })
    }
    await pool.query(
        `UPDATE users SET default_payment_method_id = $2, card_brand = $3, card_last4 = $4,
             card_exp_month = $5, card_exp_year = $6
         WHERE id = $1`, [user.id, card.id, card.brand, card.last4, card.expMonth, card.expYear])
}

async function setDefault(user, paymentMethodId) {
    const card = await ownedCard(user, paymentMethodId)
    if (card.expired) throw new HttpError(409, 'That card has expired. Add a new one.', 'card_expired')
    await makeDefault(user, card)
    return listCards(await profile.GetProfileById(user.id))
}

// Bills where this person still has to be charged: removing their last card
// would make that charge fail.
async function openBillsToPay(userId) {
    const { rows } = await pool.query(
        `SELECT s.id FROM split_participants p JOIN splits s ON s.id = p.split_id
         WHERE p.user_id = $1 AND NOT p.is_host
           AND (s.status = 'claiming'
                OR (s.status = 'confirmed' AND p.payment_status IN ('pending', 'failed', 'requires_action')))`,
        [userId])
    return rows.map((r) => r.id)
}

async function removeCard(user, paymentMethodId) {
    const card = await ownedCard(user, paymentMethodId)
    const others = (await listCards(user)).filter((c) => c.id !== card.id && !c.expired)
    if (others.length === 0 && (await openBillsToPay(user.id)).length > 0) {
        throw new HttpError(409, "You're in a bill that still needs paying. Add another card before removing this one.",
            'card_in_use')
    }
    if (isStripeConfigured()) {
        try {
            await getStripe().paymentMethods.detach(card.id)
        } catch (error) {
            // Already gone from Stripe (or never there, e.g. seeded test data).
            if (error.code !== 'resource_missing' && error.statusCode !== 404) throw error
        }
    }
    await withTransaction(async (client) => {
        await client.query('DELETE FROM user_cards WHERE stripe_payment_method_id = $1 AND user_id = $2', [card.id, user.id])
        // Bills that would have used it fall back to the default.
        await client.query(
            'UPDATE split_participants SET payment_method_id = NULL WHERE user_id = $1 AND payment_method_id = $2',
            [user.id, card.id])
    })
    if (card.isDefault) {
        if (others[0]) {
            await makeDefault(user, others[0])
        } else {
            await pool.query(
                `UPDATE users SET default_payment_method_id = NULL, card_brand = NULL, card_last4 = NULL,
                     card_exp_month = NULL, card_exp_year = NULL
                 WHERE id = $1`, [user.id])
        }
    }
    return listCards(await profile.GetProfileById(user.id))
}

/**
 * Checks a card someone picked for a bill belongs to them and still works.
 * `null` means "use my default". A picked card stays picked even if the
 * default changes later.
 */
async function checkChoice(user, paymentMethodId) {
    if (paymentMethodId === null) return null
    if (typeof paymentMethodId !== 'string') throw new HttpError(400, 'Choose one of your cards.', 'invalid_card')
    const card = await ownedCard(user, paymentMethodId)
    if (card.expired) throw new HttpError(409, 'That card has expired. Choose another.', 'card_expired')
    return card.id
}

module.exports = { listCards, rememberCard, setDefault, removeCard, checkChoice, openBillsToPay }

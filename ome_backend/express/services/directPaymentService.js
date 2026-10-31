// "Pay back": one person pays another back for a stated expense, outside any
// group (e.g. concert tickets). Deliberately narrow, so it stays reimbursement
// rather than open-ended money sending:
//   - a note saying what it's for is required;
//   - $1 to $1,000 per payment, and at most $2,000 sent in any 24 hours;
//   - the payer needs the same setup as for groups (card + verified payouts).
// The charge, the payout to the recipient, refunds and disputes all go
// through paymentService, the same way as a share of a bill.
const config = require('../config')
const { withTransaction, pool } = require('../db')
const { HttpError } = require('../auth')
const { profile, Profile } = require('../models/Profile')
const { getStripe, isStripeConfigured } = require('./stripeClient')
const payments = require('./paymentService')

const MIN_CENTS = 100
const MAX_CENTS = 100_000
const DAILY_CENTS = 200_000
const NOTE_MAX = 140
// Payments that count towards the daily limit (failed ones don't).
const COUNTED = ['processing', 'requires_action', 'succeeded', 'disputed']

function validate({ recipientId, amountCents, note, idempotencyKey }) {
    if (!Number.isInteger(recipientId) || recipientId <= 0) {
        throw new HttpError(400, 'Choose who to pay.', 'invalid_recipient')
    }
    if (!Number.isInteger(amountCents) || amountCents < MIN_CENTS || amountCents > MAX_CENTS) {
        throw new HttpError(400, 'Payments are between $1 and $1,000.', 'invalid_amount')
    }
    const cleanNote = typeof note === 'string' ? note.trim() : ''
    if (!cleanNote) throw new HttpError(400, "Say what you're paying them back for.", 'note_required')
    if (cleanNote.length > NOTE_MAX) throw new HttpError(400, `Keep the note under ${NOTE_MAX} characters.`, 'invalid_note')
    if (typeof idempotencyKey !== 'string' || !/^[A-Za-z0-9_-]{8,64}$/.test(idempotencyKey)) {
        throw new HttpError(400, 'Something went wrong. Please try again.', 'invalid_idempotency_key')
    }
    return cleanNote
}

function toJson(payment, recipient) {
    return {
        id: payment.id,
        status: payment.status,
        amountCents: payment.amount_cents,
        note: payment.note,
        errorCode: payment.payment_error_code,
        recipient: recipient ? { id: String(recipient.id), username: recipient.username } : undefined,
        createdAt: payment.created_at,
    }
}

async function sendPayment(payerId, body) {
    const note = validate(body)
    const { recipientId, amountCents, idempotencyKey } = body
    if (recipientId === payerId) throw new HttpError(400, "You can't pay yourself.", 'invalid_recipient')
    if (!isStripeConfigured()) throw new HttpError(503, 'Payments are not set up yet.', 'payments_unavailable')

    const payer = await profile.GetProfileById(payerId)
    if (!Profile.HasValidCard(payer)) {
        throw new HttpError(402, 'Add a valid card before paying someone.', 'card_required')
    }
    if (!Profile.HasVerifiedPayouts(await payments.refreshConnectStatus(payer))) {
        throw new HttpError(402, 'Finish payment verification before paying someone.', 'payment_verification_required')
    }
    const recipient = await profile.GetProfileById(recipientId)
    if (!recipient) throw new HttpError(404, "We couldn't find that person.", 'recipient_not_found')

    const { payment, isNew } = await withTransaction(async (client) => {
        // One payment at a time per payer, so two quick sends can't both slip
        // under the daily limit.
        await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [payerId])
        const existing = await client.query(
            'SELECT * FROM direct_payments WHERE payer_id = $1 AND idempotency_key = $2', [payerId, idempotencyKey])
        if (existing.rows[0]) return { payment: existing.rows[0], isNew: false }

        const sent = await client.query(
            `SELECT COALESCE(sum(amount_cents), 0)::int AS total FROM direct_payments
             WHERE payer_id = $1 AND created_at > now() - interval '24 hours' AND status = ANY($2)`,
            [payerId, COUNTED])
        if (sent.rows[0].total + amountCents > DAILY_CENTS) {
            const left = Math.max(0, DAILY_CENTS - sent.rows[0].total)
            throw new HttpError(409,
                `You can send up to $2,000 a day. You have $${(left / 100).toFixed(2)} left today.`, 'daily_limit')
        }
        const inserted = await client.query(
            `INSERT INTO direct_payments (payer_id, recipient_id, amount_cents, currency, note, idempotency_key)
             VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
            [payerId, recipientId, amountCents, config.stripe.currency, note, idempotencyKey])
        return { payment: inserted.rows[0], isNew: true }
    })
    // A repeated tap returns the first attempt instead of charging again.
    if (!isNew) return toJson(payment, recipient)

    try {
        const intent = await getStripe().paymentIntents.create({
            amount: amountCents,
            currency: config.stripe.currency,
            customer: payer.stripe_customer_id,
            payment_method: payer.default_payment_method_id,
            // Saved cards only, charged without the cardholder present: no redirects.
            // (Stripe no longer accepts payment_method_types here.)
            automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
            off_session: true,
            confirm: true,
            transfer_group: `direct_${payment.id}`,
            description: `Yuwo payment #${payment.id}: ${note}`.slice(0, 1000),
            metadata: { direct_payment_id: String(payment.id), user_id: String(payerId) },
        }, { idempotencyKey: `direct-${payment.id}` })
        if (intent.status === 'succeeded') {
            await payments.handlePaymentSucceeded(intent)
        } else {
            await payments.handlePaymentFailed(intent, intent.status === 'requires_action' ? 'requires_action' : 'processing')
        }
    } catch (error) {
        // Declined, or the bank wants the cardholder to authenticate (3DS).
        const status = error.code === 'authentication_required' ? 'requires_action' : 'failed'
        const reason = error.decline_code || error.code || null
        console.error(`Direct payment ${payment.id} failed:`, reason || error.message)
        await pool.query(
            `UPDATE direct_payments SET status = $2, stripe_payment_intent_id = $3, payment_error_code = $4
             WHERE id = $1`, [payment.id, status, error.raw?.payment_intent?.id || null, reason])
    }
    const { rows } = await pool.query('SELECT * FROM direct_payments WHERE id = $1', [payment.id])
    return toJson(rows[0], recipient)
}

// The recipient gives a payment back in full (e.g. they were paid twice).
// The payer can't refund their own payment; their bank handles that.
async function refundPayment(userId, paymentId) {
    const { rows } = await pool.query('SELECT * FROM direct_payments WHERE id = $1', [paymentId])
    const payment = rows[0]
    // Same answer whether it doesn't exist or isn't theirs.
    if (!payment || payment.recipient_id !== userId) {
        throw new HttpError(404, "We couldn't find that payment.", 'not_found')
    }
    if (payment.status === 'refunded') throw new HttpError(409, 'That payment was already refunded.', 'already_refunded')
    if (payment.status === 'disputed') {
        throw new HttpError(409, "That payment is being disputed with the bank, so it can't be refunded here.",
            'not_refundable')
    }
    if (payment.status !== 'succeeded') throw new HttpError(409, 'Only a completed payment can be refunded.', 'not_refundable')
    if (!isStripeConfigured()) throw new HttpError(503, 'Payments are not set up yet.', 'payments_unavailable')
    await payments.refundIntent(payment.stripe_payment_intent_id,
        { direct_payment_id: String(payment.id), refunded_by: String(userId) })
    const after = await pool.query('SELECT * FROM direct_payments WHERE id = $1', [paymentId])
    return toJson(after.rows[0])
}

module.exports = { sendPayment, refundPayment, MIN_CENTS, MAX_CENTS, DAILY_CENTS }

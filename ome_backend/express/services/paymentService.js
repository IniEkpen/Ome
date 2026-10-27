// Stripe money movement. Flow:
//   1. Card on file: SetupIntent (off_session) -> saved as the user's default card.
//   2. Host confirms a split: each non-host is charged off_session on the platform
//      account with transfer_group = split_<id>.
//   3. When a charge succeeds, its amount is transferred to the host(s)' Connect
//      accounts (separate charges and transfers). Hosts who haven't finished
//      Connect onboarding get the payout once they do. Each member -> host share
//      is also written to `transactions`, which the network map and activity feed read.
const { getStripe, isStripeConfigured } = require('./stripeClient')
const { profile } = require('../models/Profile')
const { split: Split } = require('../models/Split')
const { divideEvenly } = require('./splitCalculator')
const { pool } = require('../db')
const { HttpError } = require('../auth')

async function ensureCustomer(user) {
    if (user.stripe_customer_id) return user.stripe_customer_id
    const customer = await getStripe().customers.create(
        { email: user.email || undefined, name: user.username, metadata: { user_id: String(user.id) } },
        { idempotencyKey: `customer-${user.id}` })
    await profile.SetStripeCustomer(user.id, customer.id)
    return customer.id
}

// Step 1: the app confirms this with Stripe's PaymentSheet (setup mode).
async function createCardSetupIntent(user) {
    const customerId = await ensureCustomer(user)
    const setupIntent = await getStripe().setupIntents.create({
        customer: customerId,
        usage: 'off_session',
        // Stripe dropped payment_method_types; which methods show is set in the
        // Dashboard. No redirects: saved cards are charged later, off-session.
        automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
        metadata: { user_id: String(user.id) },
    })
    return { setupIntentId: setupIntent.id, clientSecret: setupIntent.client_secret }
}

// Called from the app right after the sheet closes, and again by the webhook.
// Both paths are idempotent. `expectedCustomerId` stops one user saving
// another user's SetupIntent.
async function saveCardFromSetupIntent(setupIntentId, expectedCustomerId) {
    const stripe = getStripe()
    const setupIntent = await stripe.setupIntents.retrieve(setupIntentId, { expand: ['payment_method'] })
    if (expectedCustomerId && setupIntent.customer !== expectedCustomerId) {
        throw new HttpError(403, 'That card setup belongs to another account.', 'forbidden')
    }
    if (setupIntent.status !== 'succeeded') {
        throw new HttpError(409, 'The card has not been confirmed yet.', 'setup_incomplete')
    }
    const method = setupIntent.payment_method
    await stripe.customers.update(setupIntent.customer, {
        invoice_settings: { default_payment_method: method.id },
    })
    return profile.SetDefaultCard(setupIntent.customer, {
        paymentMethodId: method.id,
        brand: method.card?.brand || null,
        last4: method.card?.last4 || null,
        expMonth: method.card?.exp_month || null,
        expYear: method.card?.exp_year || null,
    })
}

// Embedded Connect onboarding (flutter_stripe_connect) so hosts can receive payouts.
async function createConnectAccountSession(user) {
    const stripe = getStripe()
    let accountId = user.stripe_connect_account_id
    if (!accountId) {
        const account = await stripe.accounts.create({
            type: 'express',
            email: user.email || undefined,
            capabilities: { transfers: { requested: true } },
            metadata: { user_id: String(user.id) },
        }, { idempotencyKey: `connect-${user.id}` })
        accountId = account.id
        await profile.SetConnectAccount(user.id, accountId)
    }
    const session = await stripe.accountSessions.create({
        account: accountId,
        components: { account_onboarding: { enabled: true } },
    })
    return { clientSecret: session.client_secret }
}

// Step 2: charge everyone whose share is frozen as 'processing'.
// `attempt` changes the idempotency key so a host-triggered retry is a new charge attempt.
async function chargeSplit(splitId, attempt = 'initial') {
    if (!isStripeConfigured()) {
        // Leave shares as 'pending' so a host can retry once keys are configured.
        await pool.query(
            `UPDATE split_participants SET payment_status = 'pending'
             WHERE split_id = $1 AND payment_status = 'processing'`, [splitId])
        return { charged: false, reason: 'payments_unavailable' }
    }
    const stripe = getStripe()
    const payers = await Split.ParticipantsToCharge(splitId)
    for (const payer of payers) {
        if (!payer.stripe_customer_id || !payer.default_payment_method_id) {
            await Split.SetPaymentStatus(splitId, payer.user_id, 'failed')
            continue
        }
        try {
            const intent = await stripe.paymentIntents.create({
                amount: payer.charge_cents,
                currency: payer.currency,
                customer: payer.stripe_customer_id,
                payment_method: payer.default_payment_method_id,
                off_session: true,
                confirm: true,
                transfer_group: `split_${splitId}`,
                description: `Yuwo split #${splitId}`,
                metadata: { split_id: String(splitId), user_id: String(payer.user_id) },
            }, { idempotencyKey: `split-${splitId}-user-${payer.user_id}-${attempt}` })
            if (intent.status === 'succeeded') {
                await handlePaymentSucceeded(intent)
            } else {
                const status = intent.status === 'requires_action' ? 'requires_action' : 'processing'
                await Split.SetPaymentStatus(splitId, payer.user_id, status, intent.id)
            }
        } catch (error) {
            // Card declined or needs the cardholder (3DS) to authenticate.
            const intentId = error.raw?.payment_intent?.id
            const status = error.code === 'authentication_required' ? 'requires_action' : 'failed'
            const reason = error.decline_code || error.code
            console.error(`Charge failed for split ${splitId}, user ${payer.user_id}:`, reason || error.message)
            await Split.SetPaymentStatus(splitId, payer.user_id, status, intentId, reason)
        }
    }
    await Split.SettleIfComplete(splitId)
    return { charged: true }
}

// Step 3: record the payment and pay the host(s).
async function handlePaymentSucceeded(intent) {
    const splitId = Number(intent.metadata?.split_id)
    const userId = Number(intent.metadata?.user_id)
    if (!splitId || !userId) return null
    await Split.SetPaymentStatus(splitId, userId, 'succeeded', intent.id)
    await payoutToHosts(splitId, userId, intent)
    await Split.SettleIfComplete(splitId)
    return splitId
}

async function handlePaymentFailed(intent, status = 'failed') {
    const splitId = Number(intent.metadata?.split_id)
    const userId = Number(intent.metadata?.user_id)
    if (!splitId || !userId) return null
    const error = intent.last_payment_error
    await Split.SetPaymentStatus(splitId, userId, status, intent.id, error?.decline_code || error?.code)
    return splitId
}

// Co-hosts share each incoming payment evenly.
async function payoutToHosts(splitId, payerId, intent) {
    const hosts = await Split.Hosts(splitId)
    const amount = intent.amount_received ?? intent.amount
    const shares = divideEvenly(amount, hosts.map((h) => h.id))
    for (const host of hosts) {
        await recordTransaction(splitId, payerId, host.id, shares.get(host.id), intent.id)
        const inserted = await pool.query(
            `INSERT INTO split_payouts (split_id, host_user_id, source_payment_intent_id, amount_cents)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (source_payment_intent_id, host_user_id) DO NOTHING RETURNING id`,
            [splitId, host.id, intent.id, shares.get(host.id)])
        const payoutId = inserted.rows[0]?.id
        if (payoutId && host.payouts_enabled && host.stripe_connect_account_id) {
            await sendPayout(payoutId)
        }
    }
}

async function sendPayout(payoutId) {
    const { rows } = await pool.query(
        `SELECT p.*, u.stripe_connect_account_id, s.currency
         FROM split_payouts p JOIN users u ON u.id = p.host_user_id JOIN splits s ON s.id = p.split_id
         WHERE p.id = $1 AND p.status = 'awaiting_host_onboarding'`, [payoutId])
    const payout = rows[0]
    if (!payout || payout.amount_cents === 0) return
    const stripe = getStripe()
    try {
        const intent = await stripe.paymentIntents.retrieve(payout.source_payment_intent_id)
        const transfer = await stripe.transfers.create({
            amount: payout.amount_cents,
            currency: payout.currency,
            destination: payout.stripe_connect_account_id,
            transfer_group: `split_${payout.split_id}`,
            // Ties the transfer to the charge so it waits for those funds to be available.
            source_transaction: intent.latest_charge,
        }, { idempotencyKey: `payout-${payout.id}` })
        await pool.query(
            `UPDATE split_payouts SET status = 'paid', stripe_transfer_id = $2, paid_at = now() WHERE id = $1`,
            [payout.id, transfer.id])
    } catch (error) {
        console.error(`Payout ${payout.id} failed:`, error.code || error.message)
        await pool.query(`UPDATE split_payouts SET status = 'failed' WHERE id = $1`, [payout.id])
    }
}

// Payer -> host history. Privacy follows the payer's setting at the time.
// The unique (payment intent, recipient) key makes webhook retries harmless.
async function recordTransaction(splitId, payerId, hostId, amountCents, paymentIntentId) {
    if (!amountCents || payerId === hostId) return
    await pool.query(
        `INSERT INTO transactions (sender_id, recipient_id, amount_cents, currency, split_id, group_id,
                                   stripe_payment_intent_id, is_private, note)
         SELECT payer.id, $2, $3, s.currency, s.id, s.group_id, $4, payer.transactions_private, s.title
         FROM splits s JOIN users payer ON payer.id = $1
         WHERE s.id = $5
         ON CONFLICT (stripe_payment_intent_id, recipient_id) DO NOTHING`,
        [payerId, hostId, amountCents, paymentIntentId, splitId])
}

// Stripe delivers events at least once. Returns false when this event was
// already handled; one that failed half way has no processed_at and runs again.
async function beginWebhookEvent(event) {
    const { rows } = await pool.query(
        `INSERT INTO stripe_webhook_events (id, type) VALUES ($1, $2)
         ON CONFLICT (id) DO UPDATE SET received_at = now()
         RETURNING processed_at`, [event.id, event.type])
    return rows[0].processed_at === null
}

async function finishWebhookEvent(event) {
    await pool.query('UPDATE stripe_webhook_events SET processed_at = now() WHERE id = $1', [event.id])
}

// When a host finishes Connect onboarding, send anything that was waiting for them.
async function releasePendingPayouts(hostUserId) {
    const { rows } = await pool.query(
        `SELECT id FROM split_payouts WHERE host_user_id = $1 AND status = 'awaiting_host_onboarding'`,
        [hostUserId])
    for (const { id } of rows) await sendPayout(id)
}

module.exports = {
    createCardSetupIntent,
    saveCardFromSetupIntent,
    createConnectAccountSession,
    chargeSplit,
    handlePaymentSucceeded,
    handlePaymentFailed,
    releasePendingPayouts,
    beginWebhookEvent,
    finishWebhookEvent,
}

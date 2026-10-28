// Stripe money movement (USD only, no currency conversion). Flow:
//   1. Card on file: SetupIntent (off_session) -> saved as the user's default card.
//   2. Host confirms a split: each non-host is charged off_session on the platform
//      account with transfer_group = split_<id>.
//   3. When a charge succeeds, its amount is transferred to the host(s)' Connect
//      accounts (separate charges and transfers, tied to the charge with
//      source_transaction). Hosts who haven't finished onboarding get the
//      transfer once they do. Each member -> host share is also written to
//      `transactions`, which the network map and activity feed read.
//   4. Refunds and disputes come out of the platform balance, because the
//      platform is liable for losses. A refund pulls the host's transfer back
//      first; a lost dispute does too when STRIPE_RECOVER_LOST_DISPUTES_FROM_HOSTS=true.
//
// Hosts' connected accounts use Accounts v2: US individuals with the recipient
// configuration (receive transfers, pay out to their bank), no Stripe-hosted
// dashboard, and the platform as fees and losses collector. Hosts onboard and
// update their details only through Stripe's embedded component inside the app.
const config = require('../config')
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
        payment_method_types: ['card'],
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

// ---------------------------------------------------------------------------
// Host payout accounts (Stripe Connect, Accounts v2)
// ---------------------------------------------------------------------------

const ACCOUNT_INCLUDE = ['configuration.recipient', 'requirements']

async function ensureConnectAccount(user) {
    if (user.stripe_connect_account_id) return user.stripe_connect_account_id
    const name = [user.first_name, user.last_name].filter(Boolean).join(' ') || user.username
    const account = await getStripe().v2.core.accounts.create({
        contact_email: user.email || undefined,
        display_name: name,
        // No Stripe dashboard: everything happens in the app. With the platform
        // carrying losses this also makes the platform the requirements
        // collector, which lets onboarding skip the Stripe sign-in popup.
        dashboard: 'none',
        identity: { country: config.stripe.country, entity_type: 'individual' },
        configuration: {
            recipient: {
                capabilities: { stripe_balance: { stripe_transfers: { requested: true } } },
            },
        },
        defaults: {
            currency: config.stripe.currency,
            locales: ['en-US'],
            responsibilities: { fees_collector: 'application', losses_collector: 'application' },
        },
        metadata: { user_id: String(user.id) },
        include: ACCOUNT_INCLUDE,
    }, { idempotencyKey: `connect-v2-embedded-${user.id}` })
    await profile.SetConnectAccount(user.id, account.id)
    await applyConnectStatus(account)
    return account.id
}

function connectStatusFrom(account) {
    const balance = account.configuration?.recipient?.capabilities?.stripe_balance
    const entries = account.requirements?.entries || []
    return {
        transfersStatus: balance?.stripe_transfers?.status || null,
        payoutsStatus: balance?.payouts?.status || null,
        requirementsDue: entries.some((entry) => entry.awaiting_action_from === 'user'),
    }
}

async function applyConnectStatus(account) {
    const host = await profile.SyncConnectStatus(account.id, connectStatusFrom(account))
    // Anything paid to this host while they were onboarding goes out now.
    if (host?.payoutsEnabled) await releasePendingPayouts(host.id)
    return host
}

// Called by the accounts webhook and whenever a host checks their payout status,
// so status stays correct even before webhooks are configured.
async function syncConnectAccount(accountId) {
    const account = await getStripe().v2.core.accounts.retrieve(accountId, { include: ACCOUNT_INCLUDE })
    return applyConnectStatus(account)
}

// Stripe's embedded onboarding inside the app (flutter_stripe_connect). Hosts
// also come back through it to fix or update details and bank accounts.
async function createConnectAccountSession(user) {
    const accountId = await ensureConnectAccount(user)
    const stripe = getStripe()
    // Stripe only allows skipping its sign-in popup when the platform collects
    // requirements; checked rather than assumed, since Stripe derives it.
    const account = await stripe.v2.core.accounts.retrieve(accountId, { include: ['defaults'] })
    const platformCollects = account.defaults?.responsibilities?.requirements_collector === 'application'
    const features = {
        external_account_collection: true,
        ...(platformCollects ? { disable_stripe_user_authentication: true } : {}),
    }
    const session = await stripe.accountSessions.create({
        account: accountId,
        components: {
            account_onboarding: { enabled: true, features },
            account_management: { enabled: true, features },
            payouts: { enabled: true, features },
        },
    })
    return { clientSecret: session.client_secret }
}

// ---------------------------------------------------------------------------
// Charging members and paying hosts
// ---------------------------------------------------------------------------

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
        if (payer.currency !== config.stripe.currency) {
            await Split.SetPaymentStatus(splitId, payer.user_id, 'failed', null, 'unsupported_currency')
            continue
        }
        try {
            const intent = await stripe.paymentIntents.create({
                amount: payer.charge_cents,
                currency: config.stripe.currency,
                customer: payer.stripe_customer_id,
                payment_method: payer.default_payment_method_id,
                payment_method_types: ['card'],
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
    // A late or repeated event must not undo a refund or dispute.
    const current = await paymentStatusOf(intent.id)
    if (current === 'refunded' || current === 'disputed') return splitId
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

async function paymentStatusOf(paymentIntentId) {
    const { rows } = await pool.query(
        'SELECT payment_status FROM split_participants WHERE stripe_payment_intent_id = $1', [paymentIntentId])
    return rows[0]?.payment_status ?? null
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
        if (payoutId) await sendPayout(payoutId)
    }
}

// Sends one host's share once they can receive transfers. Held while the
// member's payment is disputed; cancelled if it was refunded.
async function sendPayout(payoutId) {
    const { rows } = await pool.query(
        `SELECT p.*, u.stripe_connect_account_id, u.payouts_enabled, sp.payment_status AS payer_status
         FROM split_payouts p
         JOIN users u ON u.id = p.host_user_id
         LEFT JOIN split_participants sp ON sp.stripe_payment_intent_id = p.source_payment_intent_id
         WHERE p.id = $1 AND p.status IN ('awaiting_host_onboarding', 'failed')`, [payoutId])
    const payout = rows[0]
    if (!payout) return
    if (payout.payer_status === 'refunded') {
        await pool.query(`UPDATE split_payouts SET status = 'cancelled' WHERE id = $1`, [payout.id])
        return
    }
    if (payout.payer_status !== 'succeeded') return
    if (payout.amount_cents === 0) {
        await pool.query(`UPDATE split_payouts SET status = 'paid', paid_at = now() WHERE id = $1`, [payout.id])
        return
    }
    if (!payout.payouts_enabled || !payout.stripe_connect_account_id) return

    const stripe = getStripe()
    // A retry after Stripe refused the first attempt needs a fresh key; Stripe
    // replays the original error for a reused one.
    const idempotencyKey = payout.status === 'failed' ? `payout-${payout.id}-retry-${Date.now()}` : `payout-${payout.id}`
    try {
        const intent = await stripe.paymentIntents.retrieve(payout.source_payment_intent_id)
        const transfer = await stripe.transfers.create({
            amount: payout.amount_cents,
            currency: config.stripe.currency,
            destination: payout.stripe_connect_account_id,
            // Ties the transfer to the charge so it waits for those funds to be
            // available; Stripe copies the charge's transfer_group (split_<id>).
            source_transaction: intent.latest_charge,
            description: `Yuwo split #${payout.split_id}`,
            metadata: { split_id: String(payout.split_id), payout_id: String(payout.id) },
        }, { idempotencyKey })
        await pool.query(
            `UPDATE split_payouts SET status = 'paid', stripe_transfer_id = $2, paid_at = now(), last_error_code = NULL
             WHERE id = $1`, [payout.id, transfer.id])
    } catch (error) {
        console.error(`Payout ${payout.id} failed:`, error.code || error.message)
        await pool.query(
            `UPDATE split_payouts SET status = 'failed', last_error_code = $2 WHERE id = $1`,
            [payout.id, error.code || 'transfer_failed'])
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

// When a host finishes onboarding, send anything that was waiting for them
// (and retry transfers Stripe refused earlier).
async function releasePendingPayouts(hostUserId) {
    const { rows } = await pool.query(
        `SELECT id FROM split_payouts WHERE host_user_id = $1 AND status IN ('awaiting_host_onboarding', 'failed')`,
        [hostUserId])
    for (const { id } of rows) await sendPayout(id)
}

async function releasePayoutsForPayment(paymentIntentId) {
    const { rows } = await pool.query(
        `SELECT id FROM split_payouts WHERE source_payment_intent_id = $1 AND status IN ('awaiting_host_onboarding', 'failed')`,
        [paymentIntentId])
    for (const { id } of rows) await sendPayout(id)
}

// ---------------------------------------------------------------------------
// Refunds and disputes (the platform is liable for both)
// ---------------------------------------------------------------------------

// Cancels a payment's unsent host payouts and, with `reverseSent`, pulls back
// the ones already sent. Returns the payouts that couldn't be reversed
// (usually because the host already moved the money to their bank).
async function reverseHostPayouts(paymentIntentId, reason, { reverseSent = true } = {}) {
    await pool.query(
        `UPDATE split_payouts SET status = 'cancelled'
         WHERE source_payment_intent_id = $1 AND status IN ('awaiting_host_onboarding', 'failed')`,
        [paymentIntentId])
    if (!reverseSent) return []
    const { rows } = await pool.query(
        `SELECT id, stripe_transfer_id FROM split_payouts
         WHERE source_payment_intent_id = $1 AND status = 'paid' AND stripe_transfer_id IS NOT NULL`,
        [paymentIntentId])
    const unrecovered = []
    for (const payout of rows) {
        try {
            // No amount: reverses whatever is left of the transfer. A repeat
            // call fails harmlessly because nothing is left.
            const reversal = await getStripe().transfers.createReversal(payout.stripe_transfer_id, {
                metadata: { reason, payout_id: String(payout.id) },
            })
            await pool.query(
                `UPDATE split_payouts SET status = 'reversed', stripe_transfer_reversal_id = $2,
                    reversed_at = now(), last_error_code = NULL
                 WHERE id = $1`, [payout.id, reversal.id])
        } catch (error) {
            console.error(`Reversing payout ${payout.id} (${reason}) failed:`, error.code || error.message)
            await pool.query('UPDATE split_payouts SET last_error_code = $2 WHERE id = $1',
                [payout.id, error.code || 'reversal_failed'])
            unrecovered.push(payout.id)
        }
    }
    return unrecovered
}

// The money went back to the member: mark it and take it off the network map.
async function markRefunded(paymentIntentId) {
    const { rows } = await pool.query(
        `UPDATE split_participants SET payment_status = 'refunded'
         WHERE stripe_payment_intent_id = $1 RETURNING split_id`, [paymentIntentId])
    await pool.query('DELETE FROM transactions WHERE stripe_payment_intent_id = $1', [paymentIntentId])
    if (rows[0]) await Split.BumpVersion(rows[0].split_id)
    return rows[0]?.split_id ?? null
}

// A host gives a member their money back. Their transfer is pulled back first
// so the platform isn't left paying for it; if that fails, nothing is refunded
// and the platform can decide in the Stripe Dashboard.
async function refundPayment(splitId, payerUserId) {
    const { rows } = await pool.query(
        `SELECT stripe_payment_intent_id, payment_status FROM split_participants
         WHERE split_id = $1 AND user_id = $2`, [splitId, payerUserId])
    const participant = rows[0]
    if (!participant?.stripe_payment_intent_id || participant.payment_status !== 'succeeded') {
        throw new HttpError(409, 'Only a completed payment can be refunded.', 'not_refundable')
    }
    const intentId = participant.stripe_payment_intent_id
    const unrecovered = await reverseHostPayouts(intentId, 'refund')
    if (unrecovered.length > 0) {
        throw new HttpError(409,
            "This payment was already paid out to the host's bank, so it can't be refunded in the app. Contact support.",
            'refund_needs_support')
    }
    await getStripe().refunds.create({
        payment_intent: intentId,
        reason: 'requested_by_customer',
        metadata: { split_id: String(splitId), user_id: String(payerUserId) },
    }, { idempotencyKey: `refund-${intentId}` })
    await markRefunded(intentId)
    return splitId
}

// Also covers refunds made from the Stripe Dashboard.
async function handleChargeRefunded(charge) {
    const intentId = typeof charge.payment_intent === 'string' ? charge.payment_intent : charge.payment_intent?.id
    if (!intentId) return null
    if (!charge.refunded) {
        // Partial refunds aren't modelled; the platform covers the difference.
        console.warn(`Charge ${charge.id} partially refunded (${charge.amount_refunded} of ${charge.amount} cents); host payouts left as is.`)
        return null
    }
    await reverseHostPayouts(intentId, 'refund')
    return markRefunded(intentId)
}

// charge.dispute.created / updated / closed. The dispute is answered from the
// Stripe Dashboard; this keeps the bill and host payouts in step with it.
async function handleDispute(dispute) {
    const intentId = typeof dispute.payment_intent === 'string' ? dispute.payment_intent : dispute.payment_intent?.id
    const { rows } = await pool.query(
        'SELECT split_id, user_id, payment_status FROM split_participants WHERE stripe_payment_intent_id = $1',
        [intentId])
    const participant = rows[0]
    const dueBy = dispute.evidence_details?.due_by ? new Date(dispute.evidence_details.due_by * 1000) : null
    await pool.query(
        `INSERT INTO stripe_disputes (id, stripe_payment_intent_id, split_id, payer_user_id, amount_cents,
                                      reason, status, evidence_due_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, amount_cents = EXCLUDED.amount_cents,
             reason = EXCLUDED.reason, evidence_due_by = EXCLUDED.evidence_due_by, updated_at = now()`,
        [dispute.id, intentId || null, participant?.split_id ?? null, participant?.user_id ?? null,
            dispute.amount, dispute.reason || null, dispute.status, dueBy])
    if (!participant) return null
    const splitId = participant.split_id

    if (dispute.status === 'won' || dispute.status === 'warning_closed') {
        // Back to a normal payment; payouts held during the dispute go out.
        await pool.query(
            `UPDATE split_participants SET payment_status = 'succeeded'
             WHERE stripe_payment_intent_id = $1 AND payment_status = 'disputed'`, [intentId])
        await releasePayoutsForPayment(intentId)
    } else if (dispute.status === 'lost') {
        await reverseHostPayouts(intentId, 'dispute_lost', { reverseSent: config.stripe.recoverLostDisputesFromHosts })
        await pool.query('DELETE FROM transactions WHERE stripe_payment_intent_id = $1', [intentId])
    } else if (participant.payment_status === 'succeeded') {
        // Open dispute: hold anything not yet sent to the host (see sendPayout).
        await pool.query(
            `UPDATE split_participants SET payment_status = 'disputed' WHERE stripe_payment_intent_id = $1`, [intentId])
    }
    await Split.BumpVersion(splitId)
    return splitId
}

// ---------------------------------------------------------------------------
// Webhook bookkeeping
// ---------------------------------------------------------------------------

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

module.exports = {
    createCardSetupIntent,
    saveCardFromSetupIntent,
    createConnectAccountSession,
    syncConnectAccount,
    chargeSplit,
    handlePaymentSucceeded,
    handlePaymentFailed,
    handleChargeRefunded,
    handleDispute,
    refundPayment,
    releasePendingPayouts,
    beginWebhookEvent,
    finishWebhookEvent,
}

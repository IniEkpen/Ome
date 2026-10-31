const express = require('express')
const router = express.Router()
const config = require('../config')
const { requireUser, HttpError } = require('../auth')
const { profile, Profile } = require('../models/Profile')
const { getStripe, isStripeConfigured } = require('../services/stripeClient')
const payments = require('../services/paymentService')
const splits = require('../services/splitService')
const direct = require('../services/directPaymentService')

// Stripe signs each endpoint with its own secret; the platform endpoint and a
// Connect endpoint may both point here, so any configured secret is accepted.
function verifiedSnapshotEvent(req) {
    for (const secret of config.stripe.webhookSecrets) {
        try {
            return getStripe().webhooks.constructEvent(req.body, req.get('stripe-signature'), secret)
        } catch (error) {
            // Try the next secret.
        }
    }
    return null
}

// Stripe calls this directly (snapshot events). It must see the raw body to
// verify the signature, so app.js mounts it before express.json().
async function webhook(req, res) {
    if (!isStripeConfigured() || config.stripe.webhookSecrets.length === 0) {
        return res.status(503).json({ error: 'Payments are not set up yet.' })
    }
    const event = verifiedSnapshotEvent(req)
    if (!event) return res.status(400).json({ error: 'Invalid signature' })
    if (!(await payments.beginWebhookEvent(event))) return res.json({ received: true, duplicate: true })

    const object = event.data.object
    let splitId = null
    switch (event.type) {
        case 'setup_intent.succeeded':
            await payments.saveCardFromSetupIntent(object.id)
            break
        case 'payment_intent.succeeded':
            splitId = await payments.handlePaymentSucceeded(object)
            break
        case 'payment_intent.payment_failed':
            splitId = await payments.handlePaymentFailed(object, 'failed')
            break
        case 'payment_intent.requires_action':
            splitId = await payments.handlePaymentFailed(object, 'requires_action')
            break
        case 'charge.refunded':
            splitId = await payments.handleChargeRefunded(object)
            break
        case 'charge.dispute.created':
        case 'charge.dispute.updated':
        case 'charge.dispute.closed':
            splitId = await payments.handleDispute(object)
            break
        // Sent to a Connect endpoint for connected accounts (v1 view of a v2 account).
        case 'account.updated':
            await payments.syncConnectAccount(object.id)
            break
        default:
            break
    }
    await payments.finishWebhookEvent(event)
    // Push payment status changes to anyone with the popup open.
    if (splitId) await splits.broadcast(splitId)
    return res.json({ received: true })
}

// Thin events from an event destination for v2 accounts, e.g.
// v2.core.account[configuration.recipient].capability_status_updated.
// The payload only names the account, so its current state is fetched.
async function accountsWebhook(req, res) {
    if (!isStripeConfigured() || !config.stripe.accountsWebhookSecret) {
        return res.status(503).json({ error: 'Payments are not set up yet.' })
    }
    let notification
    try {
        notification = getStripe().parseEventNotification(
            req.body, req.get('stripe-signature'), config.stripe.accountsWebhookSecret)
    } catch (error) {
        return res.status(400).json({ error: 'Invalid signature' })
    }
    if (!(await payments.beginWebhookEvent(notification))) return res.json({ received: true, duplicate: true })
    const accountId = notification.related_object?.id
    if (notification.type.startsWith('v2.core.account') && accountId?.startsWith('acct_')) {
        await payments.syncConnectAccount(accountId)
    }
    await payments.finishWebhookEvent(notification)
    return res.json({ received: true })
}

// What the app needs to start Stripe: the publishable key is public by design,
// so a build doesn't have to bake it in.
router.get('/config', (req, res) => {
    return res.json({
        paymentsEnabled: isStripeConfigured(),
        publishableKey: config.stripe.publishableKey,
        currency: config.stripe.currency,
    })
})

router.use(requireUser)

async function currentUser(req) {
    const user = await profile.GetProfileById(req.user.id)
    if (!user) throw new HttpError(401, 'Please sign in again.', 'unauthenticated')
    return user
}

// The user with their payment verification status re-read from Stripe.
async function currentUserWithFreshConnect(req, options) {
    return payments.refreshConnectStatus(await currentUser(req), options)
}

// "Pay back": pay one person for a stated expense, outside any group.
// A declined card answers 402 so the app can say why; anything else returns
// the payment (status 'succeeded', or 'processing' while the bank decides).
router.post('/direct', async (req, res) => {
    const body = req.body || {}
    const payment = await direct.sendPayment(req.user.id, {
        recipientId: Number(body.recipientId),
        amountCents: body.amountCents,
        note: body.note,
        idempotencyKey: body.idempotencyKey,
    })
    if (payment.status === 'failed') {
        throw new HttpError(402,
            payment.errorCode === 'insufficient_funds'
                ? 'Your card was declined for insufficient funds. Try another card.'
                : 'Your card was declined. Try another card from Profile.',
            'payment_declined')
    }
    if (payment.status === 'requires_action') {
        throw new HttpError(402, 'Your bank needs to approve this payment. Try another card from Profile.',
            'authentication_required')
    }
    return res.status(201).json({ payment })
})

router.get('/card', async (req, res) => {
    const user = await currentUserWithFreshConnect(req)
    return res.json({ card: Profile.CardSummary(user), paymentsEnabled: isStripeConfigured() })
})

// Step 1 of adding a card: the app confirms the returned client secret with Stripe.
router.post('/card/setup-intent', async (req, res) => {
    return res.json(await payments.createCardSetupIntent(await currentUser(req)))
})

// Step 2: once Stripe confirms the card, save it as the default.
router.post('/card/confirm', async (req, res) => {
    const user = await currentUser(req)
    const setupIntentId = req.body?.setupIntentId
    if (typeof setupIntentId !== 'string' || !setupIntentId.startsWith('seti_')) {
        throw new HttpError(400, 'Missing card setup id.', 'invalid_setup_intent')
    }
    if (!user.stripe_customer_id) throw new HttpError(409, 'Start adding a card first.', 'no_customer')
    await payments.saveCardFromSetupIntent(setupIntentId, user.stripe_customer_id)
    return res.json({ card: Profile.CardSummary(await currentUser(req)) })
})

// The user's payment verification (Connect account) status, refreshed from Stripe.
router.get('/connect', async (req, res) => {
    const user = await currentUserWithFreshConnect(req, { always: true })
    return res.json({ connect: Profile.ConnectSummary(user), paymentsEnabled: isStripeConfigured() })
})

// Everyone onboards to Stripe Connect inside the app (embedded component),
// since anyone may host a bill and be paid back.
router.post('/connect/account-session', async (req, res) => {
    return res.json(await payments.createConnectAccountSession(await currentUser(req)))
})

module.exports = { router, webhook, accountsWebhook }

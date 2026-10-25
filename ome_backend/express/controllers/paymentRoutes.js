const express = require('express')
const router = express.Router()
const config = require('../config')
const { requireUser, HttpError } = require('../auth')
const { profile, Profile } = require('../models/Profile')
const { getStripe, isStripeConfigured } = require('../services/stripeClient')
const payments = require('../services/paymentService')
const splits = require('../services/splitService')

// Stripe calls this directly. It must see the raw body to verify the
// signature, so app.js mounts it before express.json().
async function webhook(req, res) {
    if (!isStripeConfigured() || !config.stripe.webhookSecret) {
        return res.status(503).json({ error: 'Payments are not set up yet.' })
    }
    let event
    try {
        event = getStripe().webhooks.constructEvent(req.body, req.get('stripe-signature'), config.stripe.webhookSecret)
    } catch (error) {
        return res.status(400).json({ error: 'Invalid signature' })
    }
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
        case 'account.updated': {
            const host = await profile.SetPayoutsEnabled(object.id, Boolean(object.payouts_enabled))
            if (host && object.payouts_enabled) await payments.releasePendingPayouts(host.id)
            break
        }
        default:
            break
    }
    await payments.finishWebhookEvent(event)
    // Push payment status changes to anyone with the popup open.
    if (splitId) await splits.broadcast(splitId)
    return res.json({ received: true })
}

router.use(requireUser)

async function currentUser(req) {
    const user = await profile.GetProfileById(req.user.id)
    if (!user) throw new HttpError(401, 'Please sign in again.', 'unauthenticated')
    return user
}

router.get('/card', async (req, res) => {
    return res.json({ card: Profile.CardSummary(await currentUser(req)), paymentsEnabled: isStripeConfigured() })
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

// Hosts onboard to Stripe Connect so the money people pay them can be paid out.
router.post('/connect/account-session', async (req, res) => {
    return res.json(await payments.createConnectAccountSession(await currentUser(req)))
})

module.exports = { router, webhook }

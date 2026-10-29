const Stripe = require('stripe')
const config = require('../config')
const { HttpError } = require('../auth')

// Created lazily so the API still boots (and card-free routes still work)
// before Stripe keys are configured. The API version is the one this SDK
// release is pinned to, which supports Accounts v2.
let client = null

function isStripeConfigured() {
    return Boolean(config.stripe.secretKey)
}

function isTestMode() {
    return /^(sk|rk)_test_/.test(config.stripe.secretKey || '')
}

function getStripe() {
    if (!isStripeConfigured()) {
        throw new HttpError(503, 'Payments are not set up yet.', 'payments_unavailable')
    }
    if (!client) {
        client = new Stripe(config.stripe.secretKey, {
            maxNetworkRetries: 2,
            appInfo: { name: 'Yuwo' },
        })
    }
    return client
}

// Logged once on boot so a missing or mismatched key is obvious.
function describeStripeSetup() {
    const notes = []
    if (!isStripeConfigured()) {
        notes.push('STRIPE_SECRET_KEY is not set: card and payment routes will return 503.')
        return notes
    }
    if (!isTestMode() && process.env.NODE_ENV !== 'production') {
        notes.push('STRIPE_SECRET_KEY is a LIVE key but NODE_ENV is not production. Real cards will be charged.')
    }
    const publishable = config.stripe.publishableKey
    if (publishable && publishable.startsWith('pk_test_') !== isTestMode()) {
        notes.push('STRIPE_PUBLISHABLE_KEY and STRIPE_SECRET_KEY are from different modes (test vs live).')
    }
    if (config.stripe.webhookSecrets.length === 0) {
        notes.push('STRIPE_WEBHOOK_SECRET is not set: payment results only update when the app confirms them.')
    }
    if (!config.stripe.accountsWebhookSecret) {
        notes.push('STRIPE_ACCOUNTS_WEBHOOK_SECRET is not set: host payout status updates when they open payout setup.')
    }
    return notes
}

module.exports = { getStripe, isStripeConfigured, isTestMode, describeStripeSetup }

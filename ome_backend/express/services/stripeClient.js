const Stripe = require('stripe')
const config = require('../config')
const { HttpError } = require('../auth')

// Created lazily so the API still boots (and card-free routes still work)
// before Stripe keys are configured.
let client = null

function isStripeConfigured() {
    return Boolean(config.stripe.secretKey)
}

function getStripe() {
    if (!isStripeConfigured()) {
        throw new HttpError(503, 'Payments are not set up yet.', 'payments_unavailable')
    }
    if (!client) client = new Stripe(config.stripe.secretKey)
    return client
}

module.exports = { getStripe, isStripeConfigured }

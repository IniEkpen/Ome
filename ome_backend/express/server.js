const config = require('./config')
const app = require('./app')
const { isStripeConfigured } = require('./services/stripeClient')
const { pool } = require('./db')

const server = app.listen(config.port, () => {
    console.log(`The server is running on port ${config.port}`)
    if (!isStripeConfigured()) {
        console.warn('STRIPE_SECRET_KEY is not set: card and payment routes will return 503.')
    }
})

// Hosts send SIGTERM on deploy: stop taking requests, then close the pool.
// Open live-update streams never finish on their own, so don't wait forever.
function shutdown(signal) {
    console.log(`${signal} received, shutting down.`)
    server.close(() => pool.end().finally(() => process.exit(0)))
    setTimeout(() => process.exit(0), 10_000).unref()
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)

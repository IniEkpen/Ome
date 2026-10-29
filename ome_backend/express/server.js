const config = require('./config')
const app = require('./app')
const { describeStripeSetup } = require('./services/stripeClient')
const { pool } = require('./db')

const server = app.listen(config.port, config.host, () => {
    console.log(`The server is running on ${config.host}:${server.address().port}`)
    for (const note of describeStripeSetup()) console.warn(note)
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

const config = require('./config')
const app = require('./app')
const { isStripeConfigured } = require('./services/stripeClient')

app.listen(config.port, () => {
    console.log(`The server is running on port ${config.port}`)
    if (!isStripeConfigured()) {
        console.warn('STRIPE_SECRET_KEY is not set: card and payment routes will return 503.')
    }
})

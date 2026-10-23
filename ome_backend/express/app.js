const express = require('express')
const cors = require('cors')
const config = require('./config')
const { HttpError } = require('./auth')
const userRoutes = require('./controllers/userRoutes')
const groupRoutes = require('./controllers/groupRoutes')
const splitRoutes = require('./controllers/splitRoutes')
const payments = require('./controllers/paymentRoutes')

const app = express()

// The mobile app doesn't need CORS; only listed browser origins are allowed.
app.use(cors({ origin: config.corsOrigins.length > 0 ? config.corsOrigins : false }))

// Stripe webhook needs the raw body, so it's registered before express.json().
app.post('/payments/webhook', express.raw({ type: 'application/json' }), payments.webhook)

app.use(express.json({ limit: '100kb' }))

app.get('/', (req, res) => res.json({ ok: true }))
app.use('/users', userRoutes)
app.use('/groups', groupRoutes)
app.use('/splits', splitRoutes)
app.use('/payments', payments.router)

app.use((req, res) => res.status(404).json({ error: 'Not found' }))

// Known errors carry a safe message and a code the app can branch on
// (e.g. 'card_required'). Anything else is logged and hidden from the client.
app.use((error, req, res, next) => {
    if (error instanceof HttpError) {
        return res.status(error.status).json({ error: error.message, code: error.code })
    }
    if (error.type === 'entity.parse.failed') {
        return res.status(400).json({ error: 'Invalid JSON body', code: 'invalid_json' })
    }
    console.error(error)
    return res.status(500).json({ error: 'Something went wrong. Please try again.', code: 'server_error' })
})

module.exports = app

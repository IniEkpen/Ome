const express = require('express')
const cors = require('cors')
const config = require('./config')
const { HttpError } = require('./auth')
const userRoutes = require('./controllers/userRoutes')
const groupRoutes = require('./controllers/groupRoutes')
const splitRoutes = require('./controllers/splitRoutes')
const payments = require('./controllers/paymentRoutes')
const networkRoutes = require('./controllers/networkRoutes')
const receiptRoutes = require('./controllers/receiptRoutes')
const { pool } = require('./db')

const app = express()


app.set('trust proxy', 1)
app.disable('x-powered-by')


app.use(cors({
    origin: (origin, callback) => callback(null, Boolean(origin) && (
        config.allowAnyOrigin || config.corsOrigins.includes(origin)
    )),
}))

// Stripe webhooks need the raw body to verify signatures, so they're registered before express.json().
app.post('/payments/webhook', express.raw({ type: 'application/json' }), payments.webhook)
app.post('/payments/webhook/accounts', express.raw({ type: 'application/json' }), payments.accountsWebhook)

app.use(express.json({ limit: '100kb' }))

app.get('/', (req, res) => res.json({ ok: true }))
// For the host's health check: also confirms the database answers.
app.get('/health', async (req, res) => {
    try {
        await pool.query('SELECT 1')
        return res.json({ ok: true, database: 'up' })
    } catch (error) {
        return res.status(503).json({ ok: false, database: 'down' })
    }
})
app.use('/users', userRoutes)
app.use('/groups', groupRoutes)
app.use('/splits', splitRoutes)
app.use('/payments', payments.router)
app.use('/network', networkRoutes)
// Receipt photos arrive as raw image bodies, which express.json() leaves alone.
app.use('/receipts', receiptRoutes)

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
    if (error.type === 'entity.too.large') {
        return res.status(413).json({ error: 'That upload is too large.', code: 'too_large' })
    }
    console.error(error)
    return res.status(500).json({ error: 'Something went wrong. Please try again.', code: 'server_error' })
})

module.exports = app

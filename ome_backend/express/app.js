const express = require('express')
const cors = require('cors')
const config = require('./config')
const { HttpError } = require('./auth')
const userRoutes = require('./controllers/userRoutes')
const groupRoutes = require('./controllers/groupRoutes')
const splitRoutes = require('./controllers/splitRoutes')
const payments = require('./controllers/paymentRoutes')
const networkRoutes = require('./controllers/networkRoutes')
const { pool } = require('./db')

const app = express()

// Render (and most hosts) sit behind one proxy; this makes req.ip the
// client's address, which the login rate limit keys on.
app.set('trust proxy', 1)
app.disable('x-powered-by')

// The mobile app doesn't need CORS; only listed browser origins are allowed,
// plus any localhost port outside production (`flutter run -d chrome` picks
// a new port each run). Login uses bearer tokens, not cookies, so a page
// can't borrow someone's session through this.
const LOCALHOST = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/
app.use(cors({
    origin: (origin, callback) => callback(null, Boolean(origin) && (
        config.corsOrigins.includes(origin) || (config.allowLocalhostOrigins && LOCALHOST.test(origin))
    )),
}))

// Stripe webhook needs the raw body, so it's registered before express.json().
app.post('/payments/webhook', express.raw({ type: 'application/json' }), payments.webhook)

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

const path = require('path')
// ome_backend/.env, whichever folder the command is run from (npm scripts run from the repo root).
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true })

// Every secret comes from the environment (.env locally, the host's dashboard
// in production). Nothing sensitive is ever hardcoded or sent to the client.
const config = {
    // PORT=0 lets the OS pick any free port (the chosen one is logged on start).
    port: process.env.PORT === undefined || process.env.PORT.trim() === '' ? 3000 : Number(process.env.PORT),
    // 0.0.0.0 accepts connections on every network interface, so phones and
    // emulators on the same network can reach the server, not just localhost.
    host: process.env.HOST || '0.0.0.0',
    databaseUrl: process.env.DATABASE_URL,

    // Signs login tokens. Must be a long random string in production.
    authTokenSecret: process.env.AUTH_TOKEN_SECRET,
    authTokenTtlSeconds: 60 * 60 * 24 * 7,

    stripe: {
        // sk_test_... / sk_live_... (server only, never shipped to the app)
        secretKey: process.env.STRIPE_SECRET_KEY,
        // pk_test_... / pk_live_... Public by design; the app can fetch it from GET /payments/config.
        publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || null,
        // whsec_... for the snapshot-event endpoint (POST /payments/webhook). Comma separate
        // several when both a platform endpoint and a Connect endpoint send there.
        webhookSecrets: (process.env.STRIPE_WEBHOOK_SECRET || '').split(',').map((s) => s.trim()).filter(Boolean),
        // whsec_... for the thin-event destination (POST /payments/webhook/accounts)
        // that reports changes to hosts' v2 connected accounts.
        accountsWebhookSecret: process.env.STRIPE_ACCOUNTS_WEBHOOK_SECRET || null,
        // US only, no currency conversion: every charge, transfer and account is USD.
        currency: 'usd',
        country: 'us',
        // The platform carries dispute losses. Set to true to also pull a lost
        // dispute's amount back from the host(s) it was paid out to.
        recoverLostDisputesFromHosts: process.env.STRIPE_RECOVER_LOST_DISPUTES_FROM_HOSTS === 'true',
    },

    // Comma separated list of origins allowed to call the API from a browser.
    corsOrigins: (process.env.CORS_ORIGINS || '').split(',').map((o) => o.trim()).filter(Boolean),
    // Lets a browser on any host and port call the API. Off when NODE_ENV=production.
    allowAnyOrigin: process.env.NODE_ENV !== 'production',
}

module.exports = config

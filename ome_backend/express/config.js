const path = require('path')
// ome_backend/.env, whichever folder the command is run from (npm scripts run from the repo root).
require('dotenv').config({ path: path.join(__dirname, '..', '.env'), quiet: true })

const list = (value) => (value || '').split(',').map((v) => v.trim()).filter(Boolean)

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
        // whsec_... from the Stripe dashboard / `stripe listen`
        webhookSecret: process.env.STRIPE_WEBHOOK_SECRET,
        currency: process.env.STRIPE_CURRENCY || 'usd',
    },

    // "Continue with Google". Comma separated OAuth client ids whose ID tokens
    // we accept: the iOS client id and the Web client id from Google Cloud.
    google: {
        clientIds: list(process.env.GOOGLE_CLIENT_IDS),
    },

    // "Sign in with Apple".
    apple: {
        // Accepted token audiences: the app's bundle id (and a Services ID if
        // you add Apple sign-in on the web).
        clientIds: list(process.env.APPLE_CLIENT_IDS),
        // For revoking Apple access when an account is deleted. From
        // developer.apple.com > Keys (a key with Sign in with Apple enabled).
        teamId: process.env.APPLE_TEAM_ID,
        keyId: process.env.APPLE_KEY_ID,
        // Contents of the .p8 file; "\n" escapes are turned into newlines.
        privateKey: (process.env.APPLE_PRIVATE_KEY || '').replace(/\\n/g, '\n'),
    },

    // Comma separated list of origins allowed to call the API from a browser.
    corsOrigins: list(process.env.CORS_ORIGINS),
    // Lets a browser on any host and port call the API. Off when NODE_ENV=production.
    allowAnyOrigin: process.env.NODE_ENV !== 'production',
}

module.exports = config

// "Continue with Google" and "Sign in with Apple".
//
// The app signs in with the provider and sends us the provider's ID token (a
// JWT). We check its signature against the provider's published keys, its
// issuer, audience (our client ids) and expiry, then find or create the user:
//   1. someone already linked to this Google/Apple account, else
//   2. an existing account with the same *verified* email (linked now), else
//   3. a new account, with a username made from their email or name.
const crypto = require('crypto')
const { createRemoteJWKSet, jwtVerify, SignJWT, importPKCS8 } = require('jose')
const config = require('../config')
const { withTransaction } = require('../db')
const { HttpError } = require('../auth')
const { usernameProblem, USERNAME_MAX } = require('../credentials')

const GOOGLE_ISSUERS = ['https://accounts.google.com', 'accounts.google.com']
const APPLE_ISSUER = 'https://appleid.apple.com'

// Fetched once and cached (jose refreshes them when Google/Apple rotate keys).
let keySets = {
    google: createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs')),
    apple: createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys')),
}

const invalid = () => new HttpError(401, "We couldn't sign you in. Please try again.", 'invalid_oauth_token')

function requireConfigured(provider) {
    if (config[provider].clientIds.length === 0) {
        throw new HttpError(503, `Signing in with ${provider === 'google' ? 'Google' : 'Apple'} isn't set up yet.`,
            'oauth_unavailable')
    }
}

async function verify(provider, token, issuer) {
    if (typeof token !== 'string' || token.length > 10_000) throw invalid()
    try {
        const { payload } = await jwtVerify(token, keySets[provider], {
            issuer, audience: config[provider].clientIds, clockTolerance: 60,
        })
        if (typeof payload.sub !== 'string' || !payload.sub) throw invalid()
        return payload
    } catch (error) {
        if (error instanceof HttpError) throw error
        throw invalid()
    }
}

// Both providers send email_verified as a boolean or the string "true".
const verifiedEmail = (payload) =>
    (payload.email_verified === true || payload.email_verified === 'true') && typeof payload.email === 'string'
        ? payload.email.toLowerCase()
        : null

async function verifyGoogle(idToken) {
    requireConfigured('google')
    const payload = await verify('google', idToken, GOOGLE_ISSUERS)
    return {
        provider: 'google',
        sub: payload.sub,
        email: verifiedEmail(payload),
        firstName: payload.given_name || null,
        lastName: payload.family_name || null,
    }
}

// `rawNonce` is the random string the app generated; the token carries its
// SHA-256, which stops a stolen token being replayed.
async function verifyApple(identityToken, rawNonce) {
    requireConfigured('apple')
    const payload = await verify('apple', identityToken, APPLE_ISSUER)
    if (rawNonce !== undefined && rawNonce !== null) {
        const expected = crypto.createHash('sha256').update(String(rawNonce)).digest('hex')
        if (payload.nonce !== expected) throw invalid()
    }
    return { provider: 'apple', sub: payload.sub, email: verifiedEmail(payload) }
}

// --- Apple token exchange and revocation -----------------------------------
// Needed so deleting an account can revoke Sign in with Apple (App Review
// checks this). Skipped, with a warning, until the Apple key is configured.

function appleKeyConfigured() {
    const { teamId, keyId, privateKey } = config.apple
    return Boolean(teamId && keyId && privateKey && config.apple.clientIds.length)
}

async function appleClientSecret(clientId) {
    const { teamId, keyId, privateKey } = config.apple
    return new SignJWT({})
        .setProtectedHeader({ alg: 'ES256', kid: keyId })
        .setIssuer(teamId)
        .setIssuedAt()
        .setExpirationTime('5m')
        .setAudience(APPLE_ISSUER)
        .setSubject(clientId)
        .sign(await importPKCS8(privateKey, 'ES256'))
}

async function appleRequest(path, params) {
    const clientId = config.apple.clientIds[0]
    const body = new URLSearchParams({ client_id: clientId, client_secret: await appleClientSecret(clientId), ...params })
    const response = await fetch(`${APPLE_ISSUER}/auth/${path}`, {
        method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body,
    })
    if (!response.ok) throw new Error(`Apple ${path} failed: ${response.status} ${await response.text()}`)
    return path === 'token' ? response.json() : null
}

// Turns the one-time authorization code from the app into a refresh token.
async function exchangeAppleCode(authorizationCode) {
    if (!authorizationCode || !appleKeyConfigured()) return null
    try {
        const tokens = await appleRequest('token', { code: authorizationCode, grant_type: 'authorization_code' })
        return tokens.refresh_token || null
    } catch (error) {
        console.error(error.message)
        return null
    }
}

async function revokeApple(refreshToken) {
    if (!refreshToken) return
    if (!appleKeyConfigured()) {
        console.warn('Apple key not configured: could not revoke Sign in with Apple for a deleted account.')
        return
    }
    await appleRequest('revoke', { token: refreshToken, token_type_hint: 'refresh_token' })
}

// --- Finding or creating the user ------------------------------------------

const USER_COLUMNS = `id, username, first_name, last_name, email, phone, transactions_private,
    stripe_customer_id, default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year,
    stripe_connect_account_id, payouts_enabled, created_at`

// "Ada.Lovelace+test@x.io" -> "Ada.Lovelacetest". Follows the same rules as
// signup (see credentials.js), leaving room for a 5-digit suffix if taken.
function usernameBase(identity) {
    const fromEmail = identity.email?.split('@')[0]
    const fromName = [identity.firstName, identity.lastName].filter(Boolean).join('')
    const base = (fromEmail || fromName || '')
        .replace(/[^A-Za-z0-9_.]/g, '')
        .replace(/^[^A-Za-z]+/, '') // must start with a letter
        .replace(/\.{2,}/g, '.')
        .slice(0, USERNAME_MAX - 5)
        .replace(/\.+$/, '')
    return base.length >= 3 && !usernameProblem(base) ? base : 'user'
}

async function freeUsername(client, base) {
    for (let attempt = 0; attempt < 20; attempt++) {
        const candidate = attempt === 0 ? base : `${base}${crypto.randomInt(10, 100_000)}`
        // Includes deleted accounts: the unique index covers every row.
        const taken = await client.query('SELECT 1 FROM users WHERE lower(username) = lower($1)', [candidate])
        if (taken.rowCount === 0) return candidate
    }
    return `user${crypto.randomInt(1_000_000, 10_000_000)}`
}

// Returns { user, isNew }.
async function signIn(identity, { firstName, lastName, appleRefreshToken } = {}) {
    const column = identity.provider === 'google' ? 'google_sub' : 'apple_sub'
    return withTransaction(async (client) => {
        const linked = await client.query(
            `SELECT ${USER_COLUMNS} FROM users WHERE ${column} = $1 AND deleted_at IS NULL`, [identity.sub])
        let user = linked.rows[0]
        let isNew = false

        if (!user && identity.email) {
            const sameEmail = await client.query(
                `UPDATE users SET ${column} = $2 WHERE lower(email) = $1 AND deleted_at IS NULL AND ${column} IS NULL
                 RETURNING ${USER_COLUMNS}`, [identity.email, identity.sub])
            user = sameEmail.rows[0]
        }

        if (!user) {
            // Apple only sends the person's name to the app, and only the first time.
            const first = identity.firstName || firstName || null
            const last = identity.lastName || lastName || null
            const username = await freeUsername(client, usernameBase({ ...identity, firstName: first, lastName: last }))
            const created = await client.query(
                `INSERT INTO users (username, first_name, last_name, email, ${column})
                 VALUES ($1, $2, $3, $4, $5) RETURNING ${USER_COLUMNS}`,
                [username, first?.slice(0, 100) || null, last?.slice(0, 100) || null, identity.email, identity.sub])
            user = created.rows[0]
            isNew = true
        }

        if (appleRefreshToken) {
            await client.query('UPDATE users SET apple_refresh_token = $2 WHERE id = $1', [user.id, appleRefreshToken])
        }
        await client.query('UPDATE users SET last_login_at = now() WHERE id = $1', [user.id])
        return { user, isNew }
    })
}

// Tests sign their own tokens; this points verification at their keys.
function setKeySetsForTests(sets) {
    keySets = { ...keySets, ...sets }
}

module.exports = {
    verifyGoogle, verifyApple, exchangeAppleCode, revokeApple, signIn, usernameBase, setKeySetsForTests,
}

const crypto = require('crypto')
const config = require('./config')

// Without a configured secret, tokens only last until the server restarts.
let tokenSecret = config.authTokenSecret
if (!tokenSecret) {
    console.warn('AUTH_TOKEN_SECRET is not set; using a temporary secret for this process.')
    tokenSecret = crypto.randomBytes(32).toString('hex')
}

class HttpError extends Error {
    constructor(status, message, code) {
        super(message)
        this.status = status
        this.code = code
    }
}

// Passwords are stored as scrypt$<salt>$<hash>.
function hashPassword(password) {
    const salt = crypto.randomBytes(16).toString('hex')
    const hash = crypto.scryptSync(password, salt, 64).toString('hex')
    return `scrypt$${salt}$${hash}`
}

// Returns { ok, needsRehash }. Rows created before hashing was added hold the
// plain password; those still log in once and are upgraded by the caller.
function verifyPassword(password, stored) {
    if (!stored || typeof password !== 'string') return { ok: false }
    if (stored.startsWith('scrypt$')) {
        const [, salt, hash] = stored.split('$')
        const expected = Buffer.from(hash, 'hex')
        const actual = crypto.scryptSync(password, salt, expected.length)
        return { ok: crypto.timingSafeEqual(expected, actual), needsRehash: false }
    }
    const a = Buffer.from(password)
    const b = Buffer.from(stored)
    const ok = a.length === b.length && crypto.timingSafeEqual(a, b)
    return { ok, needsRehash: ok }
}

function sign(data) {
    return crypto.createHmac('sha256', tokenSecret).update(data).digest('base64url')
}

function issueToken(user) {
    const payload = Buffer.from(JSON.stringify({
        uid: user.id,
        username: user.username,
        exp: Math.floor(Date.now() / 1000) + config.authTokenTtlSeconds,
    })).toString('base64url')
    return `${payload}.${sign(payload)}`
}

function verifyToken(token) {
    const [payload, signature] = String(token).split('.')
    if (!payload || !signature) return null
    const expected = Buffer.from(sign(payload))
    const actual = Buffer.from(signature)
    if (expected.length !== actual.length || !crypto.timingSafeEqual(expected, actual)) return null
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString())
    if (data.exp < Date.now() / 1000) return null
    return { id: data.uid, username: data.username }
}

// The acting user always comes from the bearer token, never the request body.
function requireUser(req, res, next) {
    const header = req.get('Authorization') || ''
    const user = header.startsWith('Bearer ') ? verifyToken(header.slice(7)) : null
    if (!user) return next(new HttpError(401, 'Please sign in again.', 'unauthenticated'))
    req.user = user
    return next()
}

module.exports = { HttpError, hashPassword, verifyPassword, issueToken, requireUser }

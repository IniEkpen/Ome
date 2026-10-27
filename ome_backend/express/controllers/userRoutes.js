const router = require('express').Router()
const { profile, Profile } = require('../models/Profile')
const { HttpError, hashPassword, verifyPassword, issueToken, requireUser } = require('../auth')
const { rateLimit } = require('../rateLimit')
const home = require('../services/homeService')
const account = require('../services/accountService')
const oauth = require('../services/oauthService')

const USERNAME = /^[A-Za-z0-9_.]{3,30}$/
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

// 10 tries a minute per IP is plenty for a person and slows password guessing.
const authLimit = rateLimit({ windowMs: 60_000, max: 10 })

// Optional text field: trimmed, null when blank, rejected when too long.
function optionalText(value, max, message, code) {
    if (value === undefined || value === null) return null
    if (typeof value !== 'string' || value.trim().length > max) throw new HttpError(400, message, code)
    return value.trim() || null
}

function publicProfile(user) {
    return {
        id: user.id,
        username: user.username,
        firstName: user.first_name,
        lastName: user.last_name,
        email: user.email,
        phone: user.phone,
        transactionsPrivate: user.transactions_private,
        card: Profile.CardSummary(user),
    }
}

// User signup
router.post('/signup', authLimit, async (req, res) => {
    const { username, email, phone, password } = req.body || {}
    if (typeof username !== 'string' || !USERNAME.test(username)) {
        throw new HttpError(400, 'Choose a username of 3-30 letters, numbers, _ or .', 'invalid_username')
    }
    if (typeof password !== 'string' || password.length < 8) {
        throw new HttpError(400, 'Use a password of at least 8 characters.', 'invalid_password')
    }
    const cleanEmail = optionalText(email, 255, 'Enter a valid email.', 'invalid_email')
    if (cleanEmail && !EMAIL.test(cleanEmail)) throw new HttpError(400, 'Enter a valid email.', 'invalid_email')
    const fields = {
        username,
        email: cleanEmail,
        phone: optionalText(phone, 32, 'Enter a valid phone number.', 'invalid_phone'),
        firstName: optionalText(req.body.firstName, 100, 'That first name is too long.', 'invalid_name'),
        lastName: optionalText(req.body.lastName, 100, 'That last name is too long.', 'invalid_name'),
        passwordHash: hashPassword(password),
    }
    if (await profile.UsernameOrEmailTaken(username, cleanEmail)) {
        throw new HttpError(409, 'That username or email is already in use.', 'taken')
    }
    let user
    try {
        user = await profile.CreateProfile(fields)
    } catch (error) {
        // Someone else took it between the check and the insert.
        if (error.code === '23505') throw new HttpError(409, 'That username or email is already in use.', 'taken')
        throw error
    }
    // New accounts have no card yet; the app sends them to add one before joining groups.
    return res.status(201).json({
        token: issueToken(user),
        id: user.id,
        username: user.username,
        card: Profile.CardSummary(null),
    })
})

// User login
router.post('/login', authLimit, async (req, res) => {
    const { username, password } = req.body || {}
    const user = typeof username === 'string' ? await profile.GetProfileWithPassword(username) : null
    const check = verifyPassword(password, user?.password)
    // Same answer for unknown user and wrong password.
    if (!user || !check.ok) throw new HttpError(401, 'Incorrect username or password.', 'invalid_credentials')
    if (check.needsRehash) await profile.UpdatePasswordHash(user.id, hashPassword(password))
    await profile.RecordLogin(user.id)
    return res.json({
        token: issueToken(user),
        id: user.id,
        username: user.username,
        UserExists: true,
        card: Profile.CardSummary(user),
    })
})

// Same shape as /login, plus isNewUser so the app can welcome first-timers.
function signedIn(res, { user, isNew }) {
    return res.json({
        token: issueToken(user),
        id: user.id,
        username: user.username,
        UserExists: true,
        isNewUser: isNew,
        card: Profile.CardSummary(user),
    })
}

// "Continue with Google": the app sends the Google ID token.
router.post('/oauth/google', authLimit, async (req, res) => {
    const identity = await oauth.verifyGoogle(req.body?.idToken)
    return signedIn(res, await oauth.signIn(identity))
})

// "Sign in with Apple": the identity token, the nonce the app generated, and
// on first sign-in the name Apple shares only with the app.
router.post('/oauth/apple', authLimit, async (req, res) => {
    const body = req.body || {}
    const identity = await oauth.verifyApple(body.identityToken, body.nonce)
    const name = (value) => (typeof value === 'string' && value.trim() ? value.trim() : null)
    return signedIn(res, await oauth.signIn(identity, {
        firstName: name(body.firstName),
        lastName: name(body.lastName),
        appleRefreshToken: await oauth.exchangeAppleCode(body.authorizationCode),
    }))
})

router.get('/me', requireUser, async (req, res) => {
    const user = await profile.GetProfileById(req.user.id)
    if (!user) throw new HttpError(401, 'Please sign in again.', 'unauthenticated')
    return res.json(publicProfile(user))
})

// Edit your own name, phone and default payment privacy.
router.patch('/me', requireUser, async (req, res) => {
    const body = req.body || {}
    const changes = {}
    if ('firstName' in body) {
        changes.firstName = optionalText(body.firstName, 100, 'That first name is too long.', 'invalid_name')
    }
    if ('lastName' in body) {
        changes.lastName = optionalText(body.lastName, 100, 'That last name is too long.', 'invalid_name')
    }
    if ('phone' in body) changes.phone = optionalText(body.phone, 32, 'Enter a valid phone number.', 'invalid_phone')
    if ('transactionsPrivate' in body) {
        if (typeof body.transactionsPrivate !== 'boolean') {
            throw new HttpError(400, 'Choose public or private.', 'invalid_privacy')
        }
        changes.transactionsPrivate = body.transactionsPrivate
    }
    const user = await profile.UpdateProfile(req.user.id, changes)
    if (!user) throw new HttpError(401, 'Please sign in again.', 'unauthenticated')
    return res.json(publicProfile(user))
})

// Permanently deletes the signed-in account (409 'money_pending' while money is moving).
router.delete('/me', requireUser, async (req, res) => {
    await account.deleteAccount(req.user.id)
    return res.status(204).send()
})

// Everything the home page shows: open bills and recent activity.
router.get('/me/home', requireUser, async (req, res) => {
    return res.json(await home.homeFor(req.user))
})

module.exports = router

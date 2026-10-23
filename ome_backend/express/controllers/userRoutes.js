const router = require('express').Router()
const { profile, Profile } = require('../models/Profile')
const { HttpError, hashPassword, verifyPassword, issueToken, requireUser } = require('../auth')

const USERNAME = /^[A-Za-z0-9_.]{3,30}$/

// User signup
router.post('/signup', async (req, res) => {
    const { username, email, phone, password } = req.body || {}
    if (typeof username !== 'string' || !USERNAME.test(username)) {
        throw new HttpError(400, 'Choose a username of 3-30 letters, numbers, _ or .', 'invalid_username')
    }
    if (typeof password !== 'string' || password.length < 8) {
        throw new HttpError(400, 'Use a password of at least 8 characters.', 'invalid_password')
    }
    if (await profile.UsernameOrEmailTaken(username, email || null)) {
        throw new HttpError(409, 'That username or email is already in use.', 'taken')
    }
    const user = await profile.CreateProfile(username, email || null, phone || null, hashPassword(password))
    // New accounts have no card yet; the app sends them to add one before joining groups.
    return res.status(201).json({ token: issueToken(user), username: user.username, card: Profile.CardSummary(null) })
})

// User login
router.post('/login', async (req, res) => {
    const { username, password } = req.body || {}
    const user = typeof username === 'string' ? await profile.GetProfileWithPassword(username) : null
    const check = verifyPassword(password, user?.password)
    // Same answer for unknown user and wrong password.
    if (!user || !check.ok) throw new HttpError(401, 'Incorrect username or password.', 'invalid_credentials')
    if (check.needsRehash) await profile.UpdatePasswordHash(user.id, hashPassword(password))
    return res.json({
        token: issueToken(user),
        username: user.username,
        UserExists: true,
        card: Profile.CardSummary(user),
    })
})

router.get('/me', requireUser, async (req, res) => {
    const user = await profile.GetProfileById(req.user.id)
    if (!user) throw new HttpError(401, 'Please sign in again.', 'unauthenticated')
    return res.json({ id: user.id, username: user.username, email: user.email, card: Profile.CardSummary(user) })
})

module.exports = router

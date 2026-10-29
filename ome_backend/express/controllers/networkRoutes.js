const router = require('express').Router()
const { requireUser, HttpError } = require('../auth')
const { profile } = require('../models/Profile')
const network = require('../services/networkService')

router.use(requireUser)

// Everyone within `depth` public payments of you (1 = people you've paid or been paid by).
router.get('/', async (req, res) => {
    const depth = Number(req.query.depth ?? 1)
    if (!Number.isInteger(depth) || depth < 1 || depth > network.MAX_DEPTH) {
        throw new HttpError(400, `Choose a depth from 1 to ${network.MAX_DEPTH}.`, 'invalid_depth')
    }
    return res.json(await network.layer(req.user.id, depth))
})

// Your private payments, which never appear in anyone else's map.
router.get('/private', async (req, res) => {
    return res.json(await network.myPrivate(req.user.id))
})

router.get('/search', async (req, res) => {
    const q = typeof req.query.q === 'string' ? req.query.q.trim() : ''
    if (q.length === 0 || q.length > 30) return res.json({ users: [] })
    const users = await profile.SearchByUsername(q, req.user.id)
    return res.json({
        users: users.map((u) => ({
            id: String(u.id),
            label: u.username,
            name: [u.first_name, u.last_name].filter(Boolean).join(' ') || null,
        })),
    })
})

// How you're connected to someone, through public payments only.
router.get('/path/:userId', async (req, res) => {
    const targetId = Number(req.params.userId)
    if (!Number.isInteger(targetId) || targetId <= 0) throw new HttpError(400, 'Invalid id.', 'invalid_id')
    return res.json({ path: await network.path(req.user.id, targetId) })
})

module.exports = router

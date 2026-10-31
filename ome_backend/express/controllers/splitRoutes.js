const router = require('express').Router()
const { profile } = require('../models/Profile')
const { requireUser, HttpError } = require('../auth')
const splits = require('../services/splitService')

router.use(requireUser)

function idParam(req, name) {
    const id = Number(req.params[name])
    if (!Number.isInteger(id) || id <= 0) throw new HttpError(400, 'Invalid id.', 'invalid_id')
    return id
}

router.get('/:splitId', async (req, res) => {
    return res.json({ split: await splits.getSplit(req.user, idParam(req, 'splitId')) })
})

// Anyone in the bill: tap the receipt icon to say "I had this".
router.put('/:splitId/items/:itemId/claim', async (req, res) => {
    const split = await splits.setClaim(
        req.user, idParam(req, 'splitId'), idParam(req, 'itemId'), req.body?.claimed === true)
    return res.json({ split })
})

// Anyone being charged: which of their own cards pays their share.
router.put('/:splitId/card', async (req, res) => {
    const user = await profile.GetProfileById(req.user.id)
    if (!user) throw new HttpError(401, 'Please sign in again.', 'unauthenticated')
    const choice = req.body?.paymentMethodId ?? null
    return res.json({ split: await splits.chooseCard(user, idParam(req, 'splitId'), choice) })
})

// Host only from here down.
router.put('/:splitId/mode', async (req, res) => {
    return res.json({ split: await splits.setMode(req.user, idParam(req, 'splitId'), req.body?.mode) })
})

router.put('/:splitId/participants/:userId/waiver', async (req, res) => {
    const split = await splits.setWaiver(
        req.user, idParam(req, 'splitId'), idParam(req, 'userId'), req.body?.waivedCents)
    return res.json({ split })
})

router.post('/:splitId/confirm', async (req, res) => {
    return res.json(await splits.confirmSplit(req.user, idParam(req, 'splitId')))
})

router.post('/:splitId/cancel', async (req, res) => {
    return res.json({ split: await splits.cancelSplit(req.user, idParam(req, 'splitId')) })
})

router.post('/:splitId/retry-charges', async (req, res) => {
    return res.json(await splits.retryCharges(req.user, idParam(req, 'splitId')))
})

router.post('/:splitId/participants/:userId/refund', async (req, res) => {
    const split = await splits.refundParticipant(req.user, idParam(req, 'splitId'), idParam(req, 'userId'))
    return res.json({ split })
})

module.exports = router

const express = require('express')
const router = express.Router()
const { requireUser, HttpError } = require('../auth')
const { rateLimit } = require('../rateLimit')
const receipts = require('../services/receiptService')

router.use(requireUser)

// Reading a receipt costs money per page, so keep it to normal use.
const scanLimit = rateLimit({ windowMs: 10 * 60_000, max: 30 })

// Body: the photo itself (Content-Type image/jpeg etc.). ?scan=1 also reads
// it into a draft bill. Returns { receiptId, draft, scanError }.
router.post('/', scanLimit, express.raw({ type: receipts.TYPES, limit: receipts.MAX_BYTES }), async (req, res) => {
    const result = await receipts.upload(req.user.id, req.body, req.get('content-type'), {
        scan: req.query.scan === '1' || req.query.scan === 'true',
    })
    return res.status(201).json(result)
})

router.get('/:receiptId', async (req, res) => {
    const receiptId = Number(req.params.receiptId)
    if (!Number.isInteger(receiptId) || receiptId <= 0) throw new HttpError(400, 'Invalid id.', 'invalid_id')
    const { contentType, image } = await receipts.image(req.user.id, receiptId)
    res.set('Cache-Control', 'private, max-age=3600')
    return res.type(contentType).send(image)
})

module.exports = router

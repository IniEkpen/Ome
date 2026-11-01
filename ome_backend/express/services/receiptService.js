// Receipt photos: uploaded (and optionally read) when a host starts a bill,
// then attached to that bill for everyone in the group to see.
const { pool } = require('../db')
const { HttpError } = require('../auth')
const reader = require('./receiptReader')

const TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic']
const MAX_BYTES = 5 * 1024 * 1024

/**
 * Saves a receipt photo. With `scan`, also reads it into a draft bill.
 * Reading problems never lose the photo: the draft is just null, with a
 * message saying why, and the host types the items instead.
 */
async function upload(userId, image, contentType, { scan = false } = {}) {
    const type = String(contentType || '').split(';')[0].trim().toLowerCase()
    if (!TYPES.includes(type)) throw new HttpError(415, 'Use a JPEG, PNG, WebP or HEIC photo.', 'invalid_image_type')
    if (!Buffer.isBuffer(image) || image.length === 0) throw new HttpError(400, 'No photo was sent.', 'no_image')
    if (image.length > MAX_BYTES) throw new HttpError(413, 'That photo is too large (5 MB at most).', 'image_too_large')

    // Photos from bills that were never started don't need keeping.
    await pool.query(
        `DELETE FROM receipts r WHERE uploaded_by = $1 AND created_at < now() - interval '1 day'
           AND NOT EXISTS (SELECT 1 FROM splits s WHERE s.receipt_id = r.id)`, [userId])
    const { rows } = await pool.query(
        `INSERT INTO receipts (uploaded_by, content_type, image, size_bytes) VALUES ($1, $2, $3, $4) RETURNING id`,
        [userId, type, image, image.length])
    const receiptId = rows[0].id

    if (!scan) return { receiptId, draft: null, scanError: null }
    if (!reader.isConfigured()) {
        return { receiptId, draft: null, scanError: "Receipt reading isn't set up yet. Add the items yourself." }
    }
    try {
        const result = await reader.extract(image, type)
        await pool.query('UPDATE receipts SET extracted = $2 WHERE id = $1', [receiptId, JSON.stringify(result)])
        const draft = reader.toBillDraft(result)
        if (draft.items.length === 0) {
            return { receiptId, draft, scanError: "We couldn't read the items. Add them yourself, or try a clearer photo." }
        }
        return { receiptId, draft, scanError: null }
    } catch (error) {
        console.error(`Reading receipt ${receiptId} failed:`, error.message)
        return { receiptId, draft: null, scanError: "We couldn't read that receipt. Add the items yourself." }
    }
}

/** A receipt the host uploaded and hasn't attached to another bill, or null. */
async function claimForBill(userId, receiptId) {
    if (receiptId === undefined || receiptId === null) return null
    if (!Number.isInteger(receiptId) || receiptId <= 0) throw new HttpError(400, 'Invalid receipt.', 'invalid_receipt')
    const { rows } = await pool.query(
        `SELECT 1 FROM receipts r WHERE r.id = $1 AND r.uploaded_by = $2
           AND NOT EXISTS (SELECT 1 FROM splits s WHERE s.receipt_id = r.id)`, [receiptId, userId])
    if (rows.length === 0) throw new HttpError(400, "That receipt can't be used for this bill.", 'invalid_receipt')
    return receiptId
}

/** The photo, for whoever uploaded it or anyone in the group of its bill. */
async function image(userId, receiptId) {
    const { rows } = await pool.query(
        `SELECT r.content_type, r.image FROM receipts r
         WHERE r.id = $1 AND (r.uploaded_by = $2 OR EXISTS (
             SELECT 1 FROM splits s JOIN groupmembers m ON m.group_id = s.group_id
             WHERE s.receipt_id = r.id AND m.user_id = $2 AND m.status = 'accepted'))`, [receiptId, userId])
    // Same answer whether it doesn't exist or isn't theirs to see.
    if (rows.length === 0) throw new HttpError(404, "We couldn't find that receipt.", 'not_found')
    return { contentType: rows[0].content_type, image: rows[0].image }
}

module.exports = { upload, claimForBill, image, TYPES, MAX_BYTES }

// Reads a receipt photo with LlamaCloud's extraction API (the same calls as
// ome_backend/fast_app/api/user.py): upload the file, start an extraction
// with our receipt schema, then poll until it's done.
const config = require('../config')

const POLL_MS = 1500
const TIMEOUT_MS = 90_000
const MAX_ITEMS = 100
const MAX_CENTS = 10_000_00

// What we ask for. `price` is the line total, so "2 × Sandwich $34" reads
// as two at $17, and the tip is asked for too (restaurant receipts).
const RECEIPT_SCHEMA = {
    type: 'object',
    additionalProperties: false,
    properties: {
        merchant_name: { type: 'string', description: 'Store or restaurant name' },
        date: { type: 'string', description: 'Transaction date (YYYY-MM-DD)' },
        items: {
            type: 'array',
            description: 'Purchased items, one per line on the receipt',
            items: {
                type: 'object',
                properties: {
                    name: { type: 'string', description: 'Item name' },
                    quantity: { type: 'number', description: 'Quantity purchased' },
                    price: { type: 'number', description: 'Total price for this line (quantity times unit price)' },
                },
                required: ['name', 'quantity', 'price'],
            },
        },
        subtotal: { anyOf: [{ type: 'number' }, { type: 'null' }], description: 'Subtotal before tax and tip' },
        tax: { anyOf: [{ type: 'number' }, { type: 'null' }], description: 'Tax amount' },
        tip: { anyOf: [{ type: 'number' }, { type: 'null' }], description: 'Tip or gratuity amount' },
        total: { type: 'number', description: 'Total amount paid' },
    },
    required: ['merchant_name', 'date', 'items', 'subtotal', 'tax', 'tip', 'total'],
}

// Tests swap in a fake LlamaCloud.
let fetchImpl = (...args) => fetch(...args)
let pollMs = POLL_MS
function setForTests({ fetch: f, pollMs: p } = {}) {
    if (f) fetchImpl = f
    if (p !== undefined) pollMs = p
}

const isConfigured = () => Boolean(config.llama.apiKey)

async function call(method, path, { json, form } = {}) {
    const response = await fetchImpl(`${config.llama.baseUrl}${path}`, {
        method,
        headers: {
            Authorization: `Bearer ${config.llama.apiKey}`,
            ...(json ? { 'Content-Type': 'application/json' } : {}),
        },
        body: json ? JSON.stringify(json) : form,
    })
    if (!response.ok) throw new Error(`LlamaCloud ${method} ${path} failed: ${response.status} ${await response.text()}`)
    return response.json()
}

/** Raw extraction result for an image, as LlamaCloud returns it. */
async function extract(image, contentType) {
    const form = new FormData()
    const extension = contentType.split('/')[1] || 'jpg'
    form.append('file', new Blob([image], { type: contentType }), `receipt.${extension}`)
    form.append('purpose', 'parse')
    const file = await call('POST', '/api/v1/beta/files', { form })

    let job = await call('POST', '/api/v2/extract', {
        json: {
            file_input: file.id,
            configuration: {
                data_schema: RECEIPT_SCHEMA,
                tier: config.llama.tier,
                parse_tier: config.llama.tier,
                extraction_target: 'per_doc',
            },
        },
    })
    const deadline = Date.now() + TIMEOUT_MS
    while (!['COMPLETED', 'FAILED', 'CANCELLED'].includes(job.status)) {
        if (Date.now() > deadline) throw new Error(`LlamaCloud extract ${job.id} timed out`)
        await new Promise((resolve) => setTimeout(resolve, pollMs))
        job = await call('GET', `/api/v2/extract/${job.id}`)
    }
    if (job.status !== 'COMPLETED') throw new Error(`LlamaCloud extract ${job.id} ${job.status}: ${job.error_message}`)
    return job.extract_result
}

const cents = (dollars) =>
    typeof dollars === 'number' && Number.isFinite(dollars) && dollars >= 0 ? Math.round(dollars * 100) : null

/**
 * Turns what was read into a draft bill for the host to check:
 * { merchantName, receiptDate, items: [{ name, quantity, unitPriceCents }],
 *   taxCents, tipCents, totalCents }. Anything unreadable is left out.
 */
function toBillDraft(result) {
    const items = []
    for (const line of Array.isArray(result?.items) ? result.items : []) {
        const name = typeof line?.name === 'string' ? line.name.trim().slice(0, 255) : ''
        const lineCents = cents(line?.price)
        // Discounts (negative lines) and unreadable lines are skipped.
        if (!name || lineCents === null || lineCents > MAX_CENTS) continue
        const quantity = Number(line.quantity)
        // Whole quantities split the line total; "0.5 lb" and the like stay one line.
        if (Number.isInteger(quantity) && quantity >= 1 && quantity <= 99) {
            items.push({ name, quantity, unitPriceCents: Math.round(lineCents / quantity) })
        } else {
            items.push({ name, quantity: 1, unitPriceCents: lineCents })
        }
        if (items.length === MAX_ITEMS) break
    }
    const date = typeof result?.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(result.date)
        && !Number.isNaN(Date.parse(result.date)) ? result.date : null
    const capped = (value) => (value !== null && value <= MAX_CENTS ? value : null)
    return {
        merchantName: typeof result?.merchant_name === 'string' ? result.merchant_name.trim().slice(0, 255) || null : null,
        receiptDate: date,
        items,
        taxCents: capped(cents(result?.tax)),
        tipCents: capped(cents(result?.tip)),
        totalCents: cents(result?.total),
    }
}

module.exports = { extract, toBillDraft, isConfigured, setForTests, RECEIPT_SCHEMA }

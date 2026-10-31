const test = require('node:test')
const assert = require('node:assert/strict')
const config = require('../config')
const reader = require('../services/receiptReader')

// What LlamaCloud read from the Tack Room receipt (ome_backend/extracted.json).
const TACK_ROOM = {
    merchant_name: 'The Tack Room',
    date: '2024-04-08',
    items: [
        { name: 'BBQ Potato Chips', quantity: 1, price: 7 },
        { name: 'Fried Chicken Sandwich', quantity: 2, price: 34 },
        { name: 'Wings', quantity: 0.5, price: 9.5 },
        { name: 'Happy hour discount', quantity: 1, price: -5 },
        { name: '', quantity: 1, price: 3 },
    ],
    subtotal: 50.5,
    tax: 3.54,
    tip: null,
    total: 54.04,
}

test('turns a reading into a draft bill', () => {
    assert.deepEqual(reader.toBillDraft(TACK_ROOM), {
        merchantName: 'The Tack Room',
        receiptDate: '2024-04-08',
        items: [
            { name: 'BBQ Potato Chips', quantity: 1, unitPriceCents: 700 },
            // The price is the line total: two sandwiches at $17.
            { name: 'Fried Chicken Sandwich', quantity: 2, unitPriceCents: 1700 },
            // Fractional quantities stay one line at the line price.
            { name: 'Wings', quantity: 1, unitPriceCents: 950 },
            // Discounts and nameless lines are left for the host.
        ],
        taxCents: 354,
        tipCents: null,
        totalCents: 5404,
    })
})

test('ignores anything unreadable', () => {
    const draft = reader.toBillDraft({ date: '08/04/2024', items: 'nope', tax: 'x', total: -1 })
    assert.deepEqual(draft, { merchantName: null, receiptDate: null, items: [], taxCents: null, tipCents: null, totalCents: null })
    assert.deepEqual(reader.toBillDraft(null).items, [])
})

test('uploads, starts the extraction and polls until it completes', async () => {
    config.llama.apiKey = 'llx-test'
    const calls = []
    let polls = 0
    reader.setForTests({
        pollMs: 0,
        fetch: async (url, init) => {
            calls.push({ url, method: init.method, auth: init.headers.Authorization, body: init.body })
            const reply = (json) => ({ ok: true, json: async () => json, text: async () => '' })
            if (url.endsWith('/api/v1/beta/files')) return reply({ id: 'dfl-1' })
            if (url.endsWith('/api/v2/extract')) return reply({ id: 'job-1', status: 'PENDING' })
            polls += 1
            return reply(polls < 2 ? { id: 'job-1', status: 'RUNNING' } : { id: 'job-1', status: 'COMPLETED', extract_result: TACK_ROOM })
        },
    })
    const result = await reader.extract(Buffer.from('fake jpeg'), 'image/jpeg')
    assert.equal(result.merchant_name, 'The Tack Room')
    assert.deepEqual(calls.map((c) => `${c.method} ${new URL(c.url).pathname}`), [
        'POST /api/v1/beta/files', 'POST /api/v2/extract', 'GET /api/v2/extract/job-1', 'GET /api/v2/extract/job-1',
    ])
    assert.ok(calls.every((c) => c.auth === 'Bearer llx-test'))
    const upload = calls[0].body
    assert.equal(upload.get('purpose'), 'parse')
    assert.equal(upload.get('file').type, 'image/jpeg')
    const start = JSON.parse(calls[1].body)
    assert.equal(start.file_input, 'dfl-1')
    assert.equal(start.configuration.extraction_target, 'per_doc')
    assert.deepEqual(start.configuration.data_schema, reader.RECEIPT_SCHEMA)
})

test('a failed extraction is reported, not returned as empty', async () => {
    reader.setForTests({
        pollMs: 0,
        fetch: async (url) => ({
            ok: true,
            text: async () => '',
            json: async () => (url.endsWith('/files') ? { id: 'dfl-2' }
                : { id: 'job-2', status: 'FAILED', error_message: 'unreadable' }),
        }),
    })
    await assert.rejects(reader.extract(Buffer.from('x'), 'image/png'), /FAILED: unreadable/)
})

test('LlamaCloud errors surface with their status', async () => {
    reader.setForTests({ fetch: async () => ({ ok: false, status: 401, text: async () => 'bad key' }) })
    await assert.rejects(reader.extract(Buffer.from('x'), 'image/png'), /401 bad key/)
})

const { HttpError } = require('./auth')

// Fixed-window limiter keyed by client IP, for routes worth guessing at
// (login, signup). In-process like splitEvents: fine for one instance.
function rateLimit({ windowMs, max }) {
    const hits = new Map()

    // Forget old windows so the map can't grow without bound.
    setInterval(() => {
        const now = Date.now()
        for (const [key, entry] of hits) if (entry.resetAt <= now) hits.delete(key)
    }, windowMs).unref()

    return (req, res, next) => {
        const now = Date.now()
        const key = req.ip
        let entry = hits.get(key)
        if (!entry || entry.resetAt <= now) {
            entry = { count: 0, resetAt: now + windowMs }
            hits.set(key, entry)
        }
        entry.count += 1
        if (entry.count > max) {
            res.set('Retry-After', String(Math.ceil((entry.resetAt - now) / 1000)))
            return next(new HttpError(429, 'Too many attempts. Please wait a minute and try again.', 'rate_limited'))
        }
        return next()
    }
}

module.exports = { rateLimit }

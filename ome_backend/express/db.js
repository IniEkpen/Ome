const { Pool, types } = require('pg')
const config = require('./config')

// DATE columns stay 'YYYY-MM-DD' strings. The default turns them into a Date
// at local midnight, which can shift the day when serialised as UTC.
types.setTypeParser(types.builtins.DATE, (value) => value)

console.log('Database URL Exists:', !!config.databaseUrl)

// Connecting to database
const pool = new Pool({
    connectionString: config.databaseUrl,
    ssl: config.databaseUrl && !/localhost|127\.0\.0\.1/.test(config.databaseUrl)
        ? { rejectUnauthorized: false }
        : false,
    max: 20,
    idleTimeoutMillis: 10000, // close idle clients(nothing being sent through)
    connectionTimeoutMillis: 5000, // give up connecting after 5 sec
    maxUses: 7500, // close connection, replace connection
})

// Runs fn inside BEGIN/COMMIT, rolling back if it throws.
async function withTransaction(fn) {
    const client = await pool.connect()
    try {
        await client.query('BEGIN')
        const result = await fn(client)
        await client.query('COMMIT')
        return result
    } catch (error) {
        await client.query('ROLLBACK')
        throw error
    } finally {
        client.release()
    }
}

module.exports = { pool, withTransaction }

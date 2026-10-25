// Applies db/schema.sql to DATABASE_URL in a single transaction.
// The schema is idempotent, so this is safe to run on every deploy:
//   npm run migrate
const fs = require('fs')
const path = require('path')
const { pool, withTransaction } = require('../express/db')

async function main() {
    const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8')
    await withTransaction((client) => client.query(sql))
    console.log('Database schema is up to date.')
}

main()
    .catch((error) => {
        console.error('Migration failed:', error.message)
        process.exitCode = 1
    })
    .finally(() => pool.end())

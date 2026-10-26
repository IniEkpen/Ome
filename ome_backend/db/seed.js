// Applies db/schema.sql and then db/seed.sql (mock users, groups, bills and
// payments) to DATABASE_URL in a single transaction:
//   npm run seed
// Refuses to run when NODE_ENV=production unless given --force, e.g. to
// create the App Review demo account on the live database.
const fs = require('fs')
const path = require('path')
const { pool, withTransaction } = require('../express/db')

async function main() {
    if (process.env.NODE_ENV === 'production' && !process.argv.includes('--force')) {
        throw new Error('NODE_ENV is production. Re-run with --force to seed anyway.')
    }
    const read = (file) => fs.readFileSync(path.join(__dirname, file), 'utf8')
    const notices = []
    await withTransaction(async (client) => {
        client.on('notice', (notice) => notices.push(notice.message))
        await client.query(read('schema.sql'))
        await client.query(read('seed.sql'))
    })
    console.log(notices.find((n) => n.startsWith('Seeded')) || 'Mock data seeded.')
}

main()
    .catch((error) => {
        console.error('Seeding failed:', error.message || error)
        process.exitCode = 1
    })
    .finally(() => pool.end())

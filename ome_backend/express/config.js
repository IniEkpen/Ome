require('dotenv').config()

const port = 3000
app.listen(process.env.PORT || 3000, () => {
    console.log('The server is running')
});

const Pool = require('pg-pool')
const express = require('express')
const Stripe = require('stripe')
const stripe = new Stripe(process.env.STRIPE_KEY)
console.log("Database URL Exists:", !!process.env.DATABASE_URL);

// Connecting to database
const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    port: process.env.PORT,
    ssl: {
        require: true,
        rejectUnauthorized: false
    },
    max: 20,
    idleTimeoutMillis: 1000, // close idle clients(nothing being sent through)
    connectionTimeoutMillis: 5000, //after 1 sec connection unable send error
    maxUses: 7500, //close connection, replace connection
})
module.exports = { pool };
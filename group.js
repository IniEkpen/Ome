/*const Pool = require('pg')*/
const express = require('express')
const app = express()
const port= 3000

app.get('/', (req, res) => {
    res.send('Hello from Express')
})

app.listen(3000,()=>{
    console.log('The server is running')
})
/*const pool = new Pool({
    database: 'postgres',
    user:'',
    password:'secret',
    port: 5432,
    ssl:true,
    max:20,
    idleTimeoutMillis:1000, // close idle clients(nothing being sent through)
    connectionTimeoutMillis:1000, //after 1 sec connection unable send error
    maxUses: 7500, //close connection, replace connection
})





await pool.connect()
let email = 'johndoe@gmail.com'
const user_result = await pool.query('SELECT email FROM users WHERE EXISTS email = email')

if (user_result !)

app.get('', async (req,res)=> {
    

})*/
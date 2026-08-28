const dotenv = require('dotenv')
dotenv.config()
/*

const Pool = require('pg-pool')
const express = require('express')
const app = express()
const port= 3000
const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    port: 5432,
    ssl:true,
    max:20,
    idleTimeoutMillis:1000, // close idle clients(nothing being sent through)
    connectionTimeoutMillis:5000, //after 1 sec connection unable send error
    maxUses: 7500, //close connection, replace connection
})

*/
console.log(process.env.DATABASE_URL)


//async = amkes fucntion return promise
//await = makes an async fucntion wait for a promise
console.log('check')
const connected = async() => {
    console.log('check')
    //let email = 'johndoe@gmail.com'
    try{
        const poolResult = await pool.connect()
        console.log("Connected to Database",poolResult)
        return poolResult
    } catch(error){
        console.error(error)
    }
};
console.log('check')
//hardcoded email rn as a placeholder for when a user is logged in
let email = 'johndoe@gmail.com'
var hasFilledOut = true;




app.get('/group', async(req, res) => {
    console.log("check")
    const data = await connected()
    console.log(data)
    try {
        const user_result = await pool.query('SELECT email, card_info FROM users WHERE email =$1', [email]);
        console.log("Retrived items:",user_result)
         //so if user exist in our database and we dont
        if (user_result.rows[0] != null)
            if (user_result.rows[1] == 'no') {
                hasFilledOut = false;
            }
            else {
                hasFilledOut = true;
            }
        //techincally this shoudltn be possible and cause an error because how a nonexistent user adding a group
        //FIX LATER
        else{
            hasFilledOut = false;
        }
        console.log("VALUE",hasFilledOut)
    }catch(userError){
        console.error(userError)
    }


    try{
        res.json({'hasSubmitted': hasFilledOut});
        console.log("it worked");
    }catch(formError){
        console.error("Error form status:", formError);
    }
   
});






/*


app.get('', async (req,res)=> {
   


})*/


/*app.get('/', (req, res) => {
    res.send('Hello from Express')
})
*/



import 'groupie.js'


const dotenv = require('dotenv')
dotenv.config()
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

let UserExists = false

//checking if a user already exist in the system
app.get('/users/signin/:id', async(req, res) => {
    userId = req.params.id
    const {username} = req.body
    const exist = await GetProfile(username);
    if (exist) {
        return res.status(200).json({'UserExists': true})
    }
    else {
        return res.status(200).json({'UserExists': false})
    }
})

app.get('/users/createaccount', async(req,res)=>{
    accountInfo = req.params.account
    exist = await CreateProfile(accountInfo)
    username = exist.rows
    return res.json(exist.rows)

})

app.get('/group/create', async (req, res) => {
    await createDiffieHellmanGroup()

}) 


app.get('/group/join', async(req, res) => {
    await CardInfo()
    await JoinGroup()




    
});
app.get('/group/add', async (req, res)=>{
    await AddUserGroup()
})
//check if they want to delete group
app.get('/group/deletegroup', async(req, res) => { 
    return res.json({ message: "Are you sure?"})

});

app.get('/group/deletegroup/:choice', async(req, res) => { 
    choice = req.params.choice
    if ( choice == 'no')
        return res.json({message: "Chill"})
    else {
        await DeleteGroup()
        return res.json({message: "Delete"})

    }

});

app.get('/users/delete', async(req, res) => {


});

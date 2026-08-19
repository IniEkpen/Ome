const dotenv = require('dotenv')
dotenv.config()
const port= 3000
const Pool = require('pg-pool')
const express = require('express')
const app = express()
console.log("Database URL Exists:", !!process.env.DATABASE_URL);
const pool = new Pool({
    connectionString:process.env.DATABASE_URL,
    port:5432,
    ssl:{
        require: true,
        rejectUnauthorized:false
    },
    max:20,
    idleTimeoutMillis:1000, // close idle clients(nothing being sent through)
    connectionTimeoutMillis:5000, //after 1 sec connection unable send error
    maxUses: 7500, //close connection, replace connection
})
module.exports = {pool};
const {profile} = require('./userfunctions.js')
let UserExists = false
app.use(express.json())

//checking if a user already exist in the system
app.post('/users/signin/:id', async(req, res) => {
    try{
        const userId = req.params.id;
        console.log(req.body)
        const {username} = req.body;
        console.log(username)
        const exist = await profile.GetProfile(username);
        console.log("What Route Received:", exist, "Type:", typeof exist);
        if (exist) {
            return res.status(200).json({'UserExists': true})
        }
        else {
            return res.status(200).json({'UserExists': false})
        }

        }catch(error){
            return res.status(500).json({error: error.message})
        }
   
})


app.post('/users/createaccount/:id', async(req,res)=>{
    console.log("HIT")
    try{
        const userId = req.params.id;
        console.log(req.body)
        const {username, email, phone, password, stripe_customer_id} = req.body;
        const card_info = 'no'
        const recorded = await profile.CreateProfile(username, email, phone, password, stripe_customer_id, card_info)
        if (recorded) {
            return res.status(204).send();
        }
    }catch(error){
        return res.status(500).json({eror:error.message})
     }


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


app.listen(3000,()=>{
    console.log('The server is running')
})

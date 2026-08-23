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
const {profile, group} = require('./userfunctions.js')
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
            return res.status(204).send()
        }
    }catch(error){
        return res.status(500).json({error:error.message})
     }


})

// to check if user has filled out payment info before making any other request
app.post('/users/group/payment/:id', async(req,res)=>{
    try{
        console.log('ENTERED the post')
        const userId = req.params.id
        console.log(req.body)
        const {username} = req.body
        const exist = await profile.CardInfo(username)
        console.log(exist)
        if (exist) {
            return res.status(200).json({'CardFilled': true})
        }
        else {
            return res.status(200).json({'CardFilled': false})
        }
        
    }catch(error){
        return res.status(500).json({error:error.message})
    }

})


app.post('/users/group/create/:id', async (req, res) => {
    console.log("ENTERED FUNCTION")
    
    try{
        const userId = req.params.id;
        const{username,groupName, userList} = req.body
        console.log("VARIABLES", username, groupName, userList)
        console.log('Creating group with:', { groupName, username })
        const groupie = await group.CreateGroup(groupName, username)
        console.log('Group created successfully:', groupie)
        console.log(!userList.isEmpty())
        if (groupie){
            console.log("CHECK1")
            //WORKS UP TO HERE NOW
            if (!userList.isEmpty()){
                 console.log("CHECK2")
                const role = 'member'
                const check = await group.AddUsertoGroup(groupName,userList, role)
                return res.status(200).json({'Group Created':true, 'Users Added':check})
            }
            //if there are users but they werent added//
            else{
                console.log("should reached this")
                return res.status(200).json({'Group Created': true, 'Users Added': 'None'
                })
            }
         
        }
        else{
            //if group didnt have card info payment filled
            return res.status(200).json({'Group Created': false})
        }
    }catch(error){
        return res.status(500).json({error:error.message})

    }


})




app.get('/users/group/join/:id', async(req, res) => {
    await JoinGroup()








   
});
app.get('/group/addusers/:id', async (req, res)=>{
    await AddUserGroup()
})
//check if they want to delete group
app.get('/group/deletegroup/:id', async(req, res) => {
    return res.status(200).json({ message: "Are you sure?"})


});


app.post('/group/deletegroup/choice/:id', async(req, res) => {
    const userId = req.params.id;
    const {username, groupName, choice} = req.body
    if ( choice == 'no')
        return res.json({message: "Chill"})
    else {
        const check = await DeleteGroup(username, groupName)
        if (check){
            return res.status(200).json({message: "Deleted"})

        }

        else{
            return res.status(500).json({message:"Unable to delete"})
        }
        


    }


});


app.get('/users/delete', async(req, res) => {




});


app.listen(3000,()=>{
    console.log('The server is running')
})

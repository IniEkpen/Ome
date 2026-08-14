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



class Profile {
    constructor(username) {
        this.username = username
    }
    
    //keep track of user thats logged in at the moment 
    async GetProfile(username){
        try{
            var  exist = await pool.query('SELECT username FROM users WHERE username =$1', [username])
            console.log(exist)
            if (exist != null)
                return true
            else{
                return false
            }
        }catch(profileError){
            console.log(profileError)
        }
       

    }
    //creating profile card_info initialized to no because haven't gone to oayment window
    async CreateProfile (username,email, role ,phone,password, stripe_customer_id, card_info){
        await pool.query('INSERT INTO users (*) ')
        

    }
    //check if cards info filled out if not returns has not submitted and doesn't create/join group
    async CardInfo() {
        var  card = await pool.query('SELECT card_info FROM users WHERE username =$1', [username])


    }
    DeleteProfile(username){
        await Pool.query('')
        



    }
}


//Groups only have to apply to people that are owners of a group or want to join a group

class Group {
    constructor(groupId, username){
        this.groupId = groupId
        this.username = username


    }
    async checkGroups (username){
        //send back groups that this username is apart of and what role
            const check = await pool.query('SELECT user_id, group_id FROM groupmembers WHERE role =$1', "owner")
            console.log(check)
            if (check != null)
                return check
            else {
                return null
            }
        }catch(checkError){
            console.log(checkError)
        }



    CreateGroup() {
        //creates new group, making the person who created it the owner
        try {


        }catch(createError){
            console.log(createError)
        }
    }
    LeaveGroup(){

    }

    JoinGroup(){

    }


    AddUsertoGroup(username){
        //Add new user to existing Group?? might have to call checkgroups??
        //user has to be owner add user to group
        await this.checkGroups(username)
         try {



        }catch(createError){
            console.log(createError)
        }


    }

    DeleteUserFromGroup(username){
        //Delete user from group?? check if user is the owner
         try {



        }catch(createError){
            console.log(createError)
        }


    }

    DeleteGroup(){
        //can only delete group if you are owner of the group


    }




    
}
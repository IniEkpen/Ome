
/*const connected = async() => {
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


connected();
*/
class Profile {
    constructor(username,pool) {
        this.pool = 
        this.username = username
    }
   
    //keep track of user thats logged in at the moment
    async GetProfile(username){
        console.log(username)
        try{
            const {pool} = require('./groups.js');
            const exist = await pool.query('SELECT username FROM users WHERE username =$1', [username])
            console.log("EXIST VALUE",exist)
            if (exist.rowCount > 0)
                return true
            else{
                return false
            }
        }catch(profileError){
            console.log(profileError)
            throw profileError
        }


    }
    //creating profile card_info initialized to no because haven't gone to oayment window
   async CreateProfile (username,email,phone,password, stripe_customer_id, card_info){

        try{
            const {pool} = require('./groups.js');
            const values = [username, email, phone, password, stripe_customer_id, card_info]
            const query = 'INSERT INTO users  (username, email, phone, password, stripe_customer_id, card_info) VALUES ($1, $2, $3, $4, $5, $6)';
            recorded = await pool.query(query, values)
            if (recorded.rowCount > 0)
                return true
            else{
                throw new Error ("no user records were updated")
            }
        }
        catch(Accounterror){
            console.log(Accounterror)
            throw Accounterror

        }
        

    }
    //check if cards info filled out if not returns has not submitted and doesn't create/join group
    
    /*async CardInfo() {
        var  card = await pool.query('SELECT card_info FROM users WHERE username =$1', [username])




    }
    DeleteProfile(username){
       
       






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







*/   
}
const profile = new Profile()
module.exports = {profile}
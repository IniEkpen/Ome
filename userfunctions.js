
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
        console.log(username)
        try{
            const {pool} = require('./groups.js');
            const values = [username, email, phone, password, stripe_customer_id, card_info]
            const query = 'INSERT INTO users (username, email, phone, password, stripe_customer_id, card_info) VALUES ($1, $2, $3, $4, $5, $6)'
            const recorded = await pool.query(query, values)
            console.log(recorded)
            console.log(recorded.rowCount)
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
    
    async CardInfo(username) {
        console.log('reached function')
        try{
            const {pool} = require('./groups.js');
            const card = await pool.query('SELECT card_info FROM users WHERE username =$1', [username])
            if (card)
                return true
            else{
                //card info doesnt exist or hasnt been filled out
                return false
            }
        }catch(error){
            console.log(Carderror)
             throw Carderror
        }
        


    }
    async DeleteProfile(username){
       
       






    }
    
}




//Groups only have to apply to people that are owners of a group or want to join a group


class Group {
    constructor(username){
        this.username = username

    }
    async checkGroups (username){
        //send back owner of all groups
        try {
            const {pool} = require('./groups.js');
            const query = `SELECT g.id, g.group_name
            FROM groups g
            JOIN groupmembers gm ON gm.group_id = g.id
            JOIN users u ON u.id = gm.user_id
            WHERE u.username = $1
            AND gm.role = 'owner';
            `;
            const check = await pool.query(query, [username]);
            console.log(check)
            if (check != null)
                return check
            else {
                return null
            }

        }catch(checkError){
            console.log(checkError)
        }
    }

    async isOwner(groupName, username){
        try{
             const query = `
                SELECT EXISTS (
                SELECT 1
                FROM groupmembers gm
                JOIN groups g ON g.id = gm.group_id
                JOIN users u ON u.id = gm.user_id
                WHERE g.group_name = $1
                AND u.username = $2
                AND gm.role = 'owner'
                ) AS is_owner;
                `

            const result = await pool.query(query, [groupName, username]);
            if (result.rows._isowner){
                return true
            }
            else{
                return false
            }
        }catch(error){
            console.log(error)
            
        }
    }






    async CreateGroup(groupName, username) {
        //creates new group, making the person who created it the owner
        try {
            const {pool} = require('./groups.js');
            const cardData = await profile.CardInfo();
            if(cardData){
                //insert a new group
                //lets say you want to add another user or not when group is first created
                const query = `WITH new_group AS (
                INSERT INTO groups (group_name, created_by_user)
                SELECT $1, id FROM users WHERE username = $2
                RETURNING id)
                INSERT INTO groupmembers (group_id, user_id, role)
                SELECT new_group.id, (SELECT id FROM users WHERE username = $2), 'owner'
                FROM new_group
                RETURNING group_id, user_id, role;`;

                const result = await pool.query(query, [groupName, username]);
                if (result.rowCount > 0) {
                    return true
                }  
                else{
                    throw new Error ("no user records were updated")
                }   
            
            }
            else{
                return false
            }
        }catch(createError){
            console.log(createError)
            throw createError
        }
        
    }
    async LeaveGroup(username, groupName){
        try{
            const owner = await this.isOwner()
            if (isOwner){
                const group = await this.DeleteUserFromGroup(username, groupName)
            }
            const deleted = await this.DeleteGroup(username,groupName)
            if (deleted){
                return true
            }
            else{
              return false  
            }
        }catch(LeaveError){
            console.log(LeaveError)
            throw LeaveError 
            
        }
            



    }


    async JoinGroup(username){
        try{
            const {pool} = require('./groups.js');
            const cardData = await profile.CardInfo();
            if(cardData){
                const profile = await GetProfile(username)
                if (profile) {
                    const query = `
                    INSERT INTO groupmembers (group_id, user_id, role)
                    SELECT g.id, u.id, $3
                    FROM groups g, users u
                    WHERE g.group_name = $1
                    AND u.username = $2
                    RETURNING group_id, user_id, role;`
                    result = await pool.query(query, [groupName,username, role]);

                }
            }
        }catch(Joinerror){
            console.log(Joinerror)
            throw Joinerror

        }


    }




    async AddUsertoGroup(groupName, userList, role) {
        //Add new user to existing Group?? might have to call checkgroups??
        //user has to be owner add user to group
        
         try {
            const {pool} = require('./groups.js');
            const check = await this.isOwner(groupName,username)
            const addList = {}
            if (check){
                let result =0
                for (let i = 0; i < userList; i++) {
                    //check if each user is exist first(get profile)
                        const profile = await GetProfile(userList[i])
                        if (profile) {
                            const query = `
                            INSERT INTO groupmembers (group_id, user_id, role)
                            SELECT g.id, u.id, $3
                            FROM groups g, users u
                            WHERE g.group_name = $1
                            AND u.username = $2
                            RETURNING group_id, user_id, role;
                            `
                            result = await pool.query(query, [groupName,userList[i], role]);
          

                        }
                            
                        if (result.rowsCount > 0){
                            addList[userList[i].toString()] = "added"

                        }
                        else{
                            addList[userList[i].toString()] = "null"
                        }

                }
             }
            
        }catch(createError){
            console.log(createError)
        }




    }


    async DeleteUserFromGroup(username){
        //Delete user from group?? check if user is the owner
         try {






        }catch(createError){
            console.log(createError)
        }




    }


    async DeleteGroup(username, groupName){
        //can only delete group if you are owner of the group




    }


}

const profile = new Profile()
const group = new Group();
module.exports = {profile, group}
//Groups only have to apply to people that are owners of a group or want to join a group

class Group {
    constructor(pool) {
        this.pool = pool;
    }
    async checkGroups(username) {
        // Send back owner of all groups
        try {
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

        } catch (checkError) {
            console.log(checkError)
        }
    }

    async isOwner(groupName, username) {
        try {
            console.log("ENTER IS OWNER FUNCTION")
            const { pool } = require('./app.js');
            console.log("ENTERED is OWNER")
            const owner = `
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

            const result = await pool.query(owner, [groupName, username]);
            console.log(result)
            //FIX LATER SO ITS UNABLE TO INSERT NULL VALUE//
            console.log("WHAT HAPPENED", result.rows[0].is_owner)
            if (result.rows[0].is_owner) {
                return true
            }
            else {
                return false
            }
        } catch (error) {
            console.log("FLASE TRUE")
            console.log(error)

        }
    }






    async CreateGroup(groupName, username) {
        //creates new group, making the person who created it the owner
        try {
            const { pool } = require('./app.js');
            const cardData = await profile.CardInfo(username);
            if (cardData) {
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
                console.log("CHECKER", result)
                if (result.rowCount > 0) {
                    console.log('IT WORKED')
                    return true
                }
                else {
                    throw new Error("no user records were updated")
                }

            }
            else {
                return false
            }
        } catch (createError) {
            console.log(createError)
            throw createError
        }

    }
    async LeaveGroup(username, groupName) {
        try {
            const owner = await this.isOwner()
            if (isOwner) {
                const group = await this.DeleteUserFromGroup(username, groupName)
            }
            const deleted = await this.DeleteGroup(username, groupName)
            if (deleted) {
                return true
            }
            else {
                return false
            }
        } catch (LeaveError) {
            console.log(LeaveError)
            throw LeaveError

        }




    }


    async JoinGroup(username) {
        try {
            const { pool } = require('./app.js');
            const cardData = await profile.CardInfo();
            if (cardData) {
                const profile = await GetProfile(username)
                if (profile) {
                    const query = `
                    INSERT INTO groupmembers (group_id, user_id, role)
                    SELECT g.id, u.id, $3
                    FROM groups g, users u
                    WHERE g.group_name = $1
                    AND u.username = $2
                    RETURNING group_id, user_id, role;`
                    result = await pool.query(query, [groupName, username, role]);

                }
            }
        } catch (Joinerror) {
            console.log(Joinerror)
            throw Joinerror

        }


    }




    async AddUsertoGroup(groupName, userList, username, role) {
        //Add new user to existing Group?? might have to call checkgroups??
        //user has to be owner add user to group

        try {
            const { pool } = require('./app.js');
            console.log(username)
            const check = await this.isOwner(groupName, username)
            const addList = {}
            if (check) {
                console.log("ABLE TO ENTER CHECK THE OWNER WORKED")
                let result = 0
                for (let i = 0; i < userList.length; i++) {
                    //check if each user is exist first(get profile)
                    console.log("PRINTING USERS", userList[i])
                    const person = await profile.GetProfile(userList[i])
                    if (person) {
                        const query = `
                            INSERT INTO groupmembers (group_id, user_id, role)
                            SELECT g.id, u.id, $3
                            FROM groups g, users u
                            WHERE g.group_name = $1
                            AND u.username = $2
                            RETURNING group_id, user_id, role;
                            `
                        console.log("TRUE PERSONS", person)
                        result = await pool.query(query, [groupName, userList[i], role]);
                        console.log("FIXING", result)
                        if (result.rowCount > 0) {
                            addList[userList[i].toString()] = "added"
                            console.log("Is IT WORKING")
                        }

                    }

                    else {
                        addList[userList[i].toString()] = "null"
                    }

                }
                return addList
            }

        } catch (createError) {
            console.log(createError)
            throw createError
        }

    }


    async DeleteUserFromGroup(username) {
        //Delete user from group?? check if user is the owner
        try {



        } catch (createError) {
            console.log(createError)
        }




    }


    async DeleteGroup(username, groupName) {
        //can only delete group if you are owner of the group




    }

}

const { pool } = require('../app.js');
const group = Group();
module.exports = { group };
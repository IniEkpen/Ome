class Profile {
    constructor(pool) {
        this.pool = pool;
    }

    // Get profile of user with the name
    async GetProfile(username) {
        console.log(username);
        try {
            const exist = await pool.query('SELECT username FROM users WHERE username =$1', [username])
            if (exist.rowCount > 0) {
                return true;
            }
            else {
                return false;
            }
        } catch (profileError) {
            console.log(profileError);
            throw profileError;
        }
    }

    // Initialize card_info to zero
    async CreateProfile(username, email, phone, password, stripe_customer_id, card_info) {
        console.log(username)
        try {
            const values = [username, email, phone, password, stripe_customer_id, card_info];
            const query = 'INSERT INTO users (username, email, phone, password, stripe_customer_id, card_info) VALUES ($1, $2, $3, $4, $5, $6)';
            const recorded = await pool.query(query, values);
            console.log(recorded);
            console.log(recorded.rowCount);

            if (recorded.rowCount > 0)
                return true;
            else {
                throw new Error("No user records were updated");
            }
        }
        catch (Accounterror) {
            console.log(Accounterror)
            throw Accounterror
        }
    }

    // Check if card is info filled out if not returns has not submitted and doesn't create/join group
    async GetCardInfo(username) {
        console.log('Reached function')
        try {
            const card = await pool.query('SELECT card_info FROM users WHERE username =$1', [username])
            if (card) {
                console.log("AcTUALLY HIT A TRUE")
                return true;
            }
            else {
                //card info doesnt exist or hasnt been filled out
                return false
            }
        } catch (error) {
            console.log("PRINTING OUT ERROR", Carderror)
            throw Carderror
        }
    }

    async GetStripe(username) {
        try {

        } catch (getError) {

        }

    }

    // MIGHT NEED TO CHANGE LATER BUT FOR NOW IT ALTERS TABLE AFTERWARDS
    async AddStripe(username, stripe_customer_id) {
        try {
            const query = 'UPDATE users SET stripe_customer_id = $1 WHERE username = $2 RETURNING  stripe_customer_id;'
            const check = await pool.query(query, [stripe_customer_id, username])
            if (check.rowCount > 0) {
                return true
            }
            else {
                return false
            }
        } catch (error) {
            console.error()

        }

    }

    async DeleteProfile(username) {

    }

}

const { pool } = require('../app.js');
const profile = Profile(pool);
module.exports = { profile };
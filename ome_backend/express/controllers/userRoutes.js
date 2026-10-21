const userService = require('../services/userService')
const router = require('express').Router()

// User login
router.get('/login', async (req, res, next) => {
    try {
        console.log(req.body)
        const { username } = req.body;
        console.log(username)
        const userExists = await userService.checkUser(username)
        return res.status(200).json(userExists);
    } catch (error) {
        return next(error);
    }
});

// User signup
router.post('/signup', async (req, res, next) => {
    console.log("HIT");
    try {
        const userId = req.params.id;
        console.log(req.body)
        const { username, email, phone, password, stripe_customer_id } = req.body;
        const card_info = 'no'
        const recorded = await profile.CreateProfile(username, email, phone, password, stripe_customer_id, card_info)
        if (recorded) {
            return res.status(204).send()
        }
    } catch (error) {
        return res.status(500).json({ error: error.message })
    }
});

// Create 
router.post('/groups/create', async (req, res) => {
    try {
        const { username, groupName, userList } = req.body
        const groupie = await group.CreateGroup(groupName, username)
        if (groupie) {
            console.log("CHECK1")
            //WORKS UP TO HERE NOW
            if (userList.length > 0) {
                console.log("CHECK2")
                const role = 'member'
                try {
                    const check = await group.AddUsertoGroup(groupName, userList, username, role)
                    return res.status(200).json({ 'Group Created': true, 'Users Added': check })
                } catch (userError) {
                    return res.status(500).json({ error: error.message, 'ERO': 'error' })
                }

            }
            //if there are users but they werent added//
            else {
                console.log("should reached this")
                return res.status(200).json({ 'Group Created': true, 'Users Added': 'None' })
            }

        }
        else {
            //if group didnt have card info payment filled
            return res.status(200).json({ 'Group Created': false })
        }
    } catch (error) {
        return res.status(500).json({ error: error.message, 'ERO': 'error' })
    }


});

router.get('/users/groups/join', async (req, res) => {
    await JoinGroup();
});


router.get('/groups/addUser', async (req, res) => {
    try {
        const userId = req.params.id;
        const { username, groupName, userList } = req.body
        const add = await group.AddUserGroup()
        return res.status(200).json({ 'Users Added': add })
    } catch (addError) {
        console.log(addError)
        return res.status(500).json({ error: error.message, 'ERO': 'error' })

    }

});


router.post('/groups/delete', async (req, res) => {
    const userId = req.params.id;
    const { username, groupName, choice } = req.body;
    if (choice == 'no')
        return res.json({ message: "return" })
    else {
        const check = await DeleteGroup(username, groupName)
        if (check) {
            return res.status(200).json({ message: "Deleted" })

        }
        else {
            return res.status(500).json({ message: "Unable to delete" })
        }
    }
});


/*
app.post('/get/stripe', async (req, res) => {
    try {
        const userId = req.params.id
        const { username, email } = req.body
        const accountSession = await stripe.accountSessions.create({
            account: '{{CONNECTED_ACCOUNT_ID}}',
            components: {
                account_onboarding: {
                    enabled: true,
                },
            },
        });
        res.json({ client_secret: accountSession.client_secret })

    } catch (stripeError) {
        console.error()

    }



})

app.post('/create/stripe', async (req, res) => {
    try {
        const userId = req.params.id
        const { username, email } = req.body
        const stripe_customer_id = await stripe.v2.core.accounts.create({
            contact_email: email,
            display_name: username,
            identity: {
                country: 'us',
                entity_type: 'individual',

            },
            configuration: {
                customer: {
                    capabilities: {
                        automatic_indirect_tax: {
                            requested: true,
                        },
                    },
                },

                recipient: {
                    capabilities: {
                        bank_accounts: {
                            local: {
                                requested: true,
                            },
                        },
                    },
                },
                dashboard: 'express',
                include: ['identity', 'configuration.recipient', 'requirements', 'configuration.customer', 'defaults'],
            },


        }

        )
        const stripe = await profile.AddStripe(username, stripe_customer_id)


    } catch (stripeError) {

    }



})

*/

module.exports = router;
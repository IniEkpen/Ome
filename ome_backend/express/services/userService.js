const Profile = require('../models/Profile.js');
const Group = require('../models/Group.js');

exports.checkUser = async (username) => {
    const exists = await Profile.GetProfile(username);
    console.log("What Route Received:", exist, "Type:", typeof exist);
    if (!exists) {
        throw new Error('No matching profile exists. Try again or create an account.');
    }
    return { 'UserExists': exists };
};

exports.addGroup


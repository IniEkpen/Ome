// Deleting your own account (App Store guideline 5.1.1(v) requires it in-app).
//
// Blocked while money is still moving for you: an open bill you're part of,
// or payouts held for you because payouts aren't set up. Otherwise:
// - groups you own pass to the longest-standing member, or are deleted when
//   nobody else is in them;
// - your memberships and invites go;
// - your user row is scrubbed (see Profile.Scrub), your saved card is
//   removed from Stripe and Sign in with Apple is revoked.
const { withTransaction } = require('../db')
const { HttpError } = require('../auth')
const { profile } = require('../models/Profile')
const { getStripe, isStripeConfigured } = require('./stripeClient')
const oauth = require('./oauthService')

async function deleteAccount(userId) {
    const stripeIds = await withTransaction(async (client) => {
        const user = await client.query(
            `SELECT stripe_customer_id, stripe_connect_account_id, apple_refresh_token FROM users
             WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`, [userId])
        if (user.rowCount === 0) throw new HttpError(401, 'Please sign in again.', 'unauthenticated')

        const openBill = await client.query(
            `SELECT 1 FROM split_participants p JOIN splits s ON s.id = p.split_id
             WHERE p.user_id = $1 AND s.status IN ('claiming', 'confirmed') LIMIT 1`, [userId])
        if (openBill.rowCount > 0) {
            throw new HttpError(409,
                'You have a bill that is still open. Finish or cancel it before deleting your account.',
                'money_pending')
        }
        const heldPayout = await client.query(
            `SELECT 1 FROM split_payouts WHERE host_user_id = $1 AND status <> 'paid' LIMIT 1`, [userId])
        if (heldPayout.rowCount > 0) {
            throw new HttpError(409,
                'Money is waiting to be paid out to you. Set up payouts from Profile first.',
                'money_pending')
        }

        const owned = await client.query(
            `SELECT group_id FROM groupmembers WHERE user_id = $1 AND role = 'owner'`, [userId])
        for (const { group_id: groupId } of owned.rows) {
            const heir = await client.query(
                `SELECT user_id FROM groupmembers
                 WHERE group_id = $1 AND user_id <> $2 AND status = 'accepted'
                 ORDER BY joined_at NULLS LAST, created_at LIMIT 1`, [groupId, userId])
            if (heir.rowCount === 0) {
                await client.query('DELETE FROM groups WHERE id = $1', [groupId])
                continue
            }
            // Drop the old owner first: only one owner per group is allowed.
            await client.query('DELETE FROM groupmembers WHERE group_id = $1 AND user_id = $2', [groupId, userId])
            await client.query(
                `UPDATE groupmembers SET role = 'owner' WHERE group_id = $1 AND user_id = $2`,
                [groupId, heir.rows[0].user_id])
            await client.query('UPDATE groups SET created_by_user = $2 WHERE id = $1', [groupId, heir.rows[0].user_id])
        }
        await client.query('DELETE FROM groupmembers WHERE user_id = $1', [userId])
        await client.query('DELETE FROM notifications WHERE user_id = $1', [userId])
        await profile.Scrub(client, userId)
        return user.rows[0]
    })

    // After the commit, so an Apple or Stripe outage can't block deletion.
    await oauth.revokeApple(stripeIds.apple_refresh_token).catch((error) => {
        console.error(`Revoking Sign in with Apple for deleted user ${userId} failed:`, error.message)
    })
    // Deleting the Stripe customer also removes their saved cards.
    if (isStripeConfigured()) {
        const stripe = getStripe()
        await Promise.all([
            stripeIds.stripe_customer_id && stripe.customers.del(stripeIds.stripe_customer_id),
            stripeIds.stripe_connect_account_id && stripe.accounts.del(stripeIds.stripe_connect_account_id),
        ].map((call) => Promise.resolve(call).catch((error) => {
            console.error(`Stripe cleanup for deleted user ${userId} failed:`, error.message)
        })))
    }
}

module.exports = { deleteAccount }

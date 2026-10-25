// Groups are addressed by id (names aren't unique). Membership rows carry a
// role ('owner' | 'member') and a status ('pending' invite | 'accepted').
const { pool, withTransaction } = require('../db')

class Group {
    constructor(pool) {
        this.pool = pool
    }

    // Every group the user owns, joined or was invited to, with member names.
    async ListForUser(userId) {
        const query = `
            SELECT g.id, g.group_name, me.role, me.status, inviter.username AS invited_by,
                   COALESCE(array_agg(u.username ORDER BY u.username)
                            FILTER (WHERE other.status = 'accepted'), '{}') AS people,
                   EXISTS (SELECT 1 FROM splits s WHERE s.group_id = g.id AND s.status = 'claiming') AS has_open_split
            FROM groupmembers me
            JOIN groups g ON g.id = me.group_id
            JOIN groupmembers other ON other.group_id = g.id
            JOIN users u ON u.id = other.user_id
            LEFT JOIN users inviter ON inviter.id = me.invited_by
            WHERE me.user_id = $1
            GROUP BY g.id, g.group_name, me.role, me.status, inviter.username
            ORDER BY g.id DESC;`
        const result = await this.pool.query(query, [userId])
        return result.rows
    }

    async GetMembership(groupId, userId) {
        const result = await this.pool.query(
            'SELECT role, status FROM groupmembers WHERE group_id = $1 AND user_id = $2', [groupId, userId])
        return result.rows[0] || null
    }

    async AcceptedMembers(groupId, client = this.pool) {
        const result = await client.query(
            `SELECT u.id, u.username, gm.role
             FROM groupmembers gm JOIN users u ON u.id = gm.user_id
             WHERE gm.group_id = $1 AND gm.status = 'accepted'
             ORDER BY u.username`, [groupId])
        return result.rows
    }

    // Creates the group with the creator as accepted owner and invites the rest.
    async CreateGroup(ownerId, groupName, inviteeIds) {
        return withTransaction(async (client) => {
            const created = await client.query(
                'INSERT INTO groups (group_name, created_by_user) VALUES ($1, $2) RETURNING id', [groupName, ownerId])
            const groupId = created.rows[0].id
            await client.query(
                `INSERT INTO groupmembers (group_id, user_id, role, status, joined_at)
                 VALUES ($1, $2, 'owner', 'accepted', now())`,
                [groupId, ownerId])
            await this.#invite(client, groupId, ownerId, inviteeIds.filter((id) => id !== ownerId))
            return groupId
        })
    }

    async InviteMembers(groupId, invitedBy, inviteeIds) {
        return this.#invite(this.pool, groupId, invitedBy, inviteeIds)
    }

    async #invite(client, groupId, invitedBy, userIds) {
        if (userIds.length === 0) return 0
        const result = await client.query(
            `INSERT INTO groupmembers (group_id, user_id, role, status, invited_by)
             SELECT $1, unnest($2::int[]), 'member', 'pending', $3
             ON CONFLICT ON CONSTRAINT unique_group_user DO NOTHING`, [groupId, userIds, invitedBy])
        return result.rowCount
    }

    // Accepting flips the invite to accepted; declining removes it.
    async RespondToInvite(groupId, userId, accept) {
        const result = accept
            ? await this.pool.query(
                `UPDATE groupmembers SET status = 'accepted', joined_at = now()
                 WHERE group_id = $1 AND user_id = $2 AND status = 'pending'`, [groupId, userId])
            : await this.pool.query(
                `DELETE FROM groupmembers WHERE group_id = $1 AND user_id = $2 AND status = 'pending'`,
                [groupId, userId])
        return result.rowCount > 0
    }

    async LeaveGroup(groupId, userId) {
        const result = await this.pool.query(
            `DELETE FROM groupmembers WHERE group_id = $1 AND user_id = $2 AND role <> 'owner'`, [groupId, userId])
        return result.rowCount > 0
    }

    // Only the owner can delete, and not while money is still moving: members
    // and bills go with the group (ON DELETE CASCADE), and so would any payout
    // a host hasn't received yet. Payment history (transactions) is kept.
    // Returns 'deleted' | 'not_owner' | 'money_pending'.
    async DeleteGroup(groupId, ownerId) {
        return withTransaction(async (client) => {
            const owner = await client.query(
                `SELECT 1 FROM groupmembers WHERE group_id = $1 AND user_id = $2 AND role = 'owner'`,
                [groupId, ownerId])
            if (owner.rowCount === 0) return 'not_owner'
            const busy = await client.query(
                `SELECT 1 FROM splits s
                 WHERE s.group_id = $1
                   AND (s.status IN ('claiming', 'confirmed')
                        OR EXISTS (SELECT 1 FROM split_payouts p WHERE p.split_id = s.id AND p.status <> 'paid'))
                 LIMIT 1`, [groupId])
            if (busy.rowCount > 0) return 'money_pending'
            await client.query('DELETE FROM groups WHERE id = $1', [groupId])
            return 'deleted'
        })
    }
}

const group = new Group(pool)
module.exports = { group }

const router = require('express').Router()
const { requireUser, HttpError } = require('../auth')
const { group: Group } = require('../models/Group')
const { profile, Profile } = require('../models/Profile')
const splits = require('../services/splitService')
const { subscribe } = require('../services/splitEvents')

router.use(requireUser)

function idParam(req, name) {
    const id = Number(req.params[name])
    if (!Number.isInteger(id) || id <= 0) throw new HttpError(400, 'Invalid id.', 'invalid_id')
    return id
}

// You can't create or join a group without a valid card on file.
async function requireValidCard(userId) {
    const user = await profile.GetProfileById(userId)
    if (!Profile.HasValidCard(user)) {
        throw new HttpError(402, 'Add a valid card before creating or joining a group.', 'card_required')
    }
}

router.get('/', async (req, res) => {
    const rows = await Group.ListForUser(req.user.id)
    return res.json(rows.map((row) => ({
        id: row.id,
        groupname: row.group_name,
        people: row.people,
        status: row.status,
        role: row.role,
        invitedBy: row.invited_by,
        hasOpenSplit: row.has_open_split,
    })))
})

// Create
router.post('/', async (req, res) => {
    const groupName = typeof req.body?.groupName === 'string' ? req.body.groupName.trim() : ''
    if (!groupName || groupName.length > 255) throw new HttpError(400, 'Give the group a name.', 'invalid_name')
    await requireValidCard(req.user.id)

    const requested = Array.isArray(req.body.members) ? req.body.members.filter((m) => typeof m === 'string') : []
    const found = await profile.GetProfilesByUsernames(requested)
    const groupId = await Group.CreateGroup(req.user.id, groupName, found.map((u) => u.id))
    // Usernames match ignoring case, so compare lowercased.
    const foundNames = new Set(found.map((u) => u.username.toLowerCase()))
    return res.status(201).json({
        groupId,
        invited: found.filter((u) => u.id !== req.user.id).map((u) => u.username),
        notFound: requested.filter((name) => !foundNames.has(name.toLowerCase())),
    })
})

// Accept (needs a valid card) or decline an invite.
router.post('/:groupId/invites/respond', async (req, res) => {
    const groupId = idParam(req, 'groupId')
    const accept = req.body?.accept === true
    if (accept) await requireValidCard(req.user.id)
    if (!(await Group.RespondToInvite(groupId, req.user.id, accept))) {
        throw new HttpError(404, 'That invite is no longer open.', 'not_found')
    }
    return res.status(204).send()
})

router.post('/:groupId/members', async (req, res) => {
    const groupId = idParam(req, 'groupId')
    const membership = await splits.requireAcceptedMember(groupId, req.user.id)
    if (membership.role !== 'owner') throw new HttpError(403, 'Only the owner can invite people.', 'owner_only')
    const requested = Array.isArray(req.body?.members) ? req.body.members.filter((m) => typeof m === 'string') : []
    const found = await profile.GetProfilesByUsernames(requested)
    const invited = await Group.InviteMembers(groupId, req.user.id, found.map((u) => u.id))
    return res.json({ invited })
})

router.post('/:groupId/leave', async (req, res) => {
    if (!(await Group.LeaveGroup(idParam(req, 'groupId'), req.user.id))) {
        throw new HttpError(400, "Owners can't leave their own group. Delete it instead.", 'cannot_leave')
    }
    return res.status(204).send()
})

router.delete('/:groupId', async (req, res) => {
    const outcome = await Group.DeleteGroup(idParam(req, 'groupId'), req.user.id)
    if (outcome === 'not_owner') throw new HttpError(403, 'Only the owner can delete this group.', 'owner_only')
    if (outcome === 'money_pending') {
        throw new HttpError(409, 'Finish or cancel the open bill, and wait for payouts, before deleting.', 'money_pending')
    }
    return res.status(204).send()
})

// The bill currently open (or awaiting payment) in this group, or null.
router.get('/:groupId/split', async (req, res) => {
    return res.json({ split: await splits.getActiveSplit(req.user, idParam(req, 'groupId')) })
})

// Owner opens a bill: everyone in the group gets the payment popup.
router.post('/:groupId/splits', async (req, res) => {
    return res.status(201).json({ split: await splits.startSplit(req.user, idParam(req, 'groupId'), req.body || {}) })
})

// Server-Sent Events: pushes the full split snapshot whenever anything changes.
router.get('/:groupId/events', async (req, res) => {
    const groupId = idParam(req, 'groupId')
    const initial = await splits.getActiveSplit(req.user, groupId)

    res.set({
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'X-Accel-Buffering': 'no',
    })
    res.flushHeaders()
    const send = (payload) => res.write(`data: ${JSON.stringify(payload)}\n\n`)
    send({ type: 'split', split: initial })

    const unsubscribe = subscribe(groupId, send)
    // Keeps proxies (e.g. Render) from closing an idle connection.
    const heartbeat = setInterval(() => res.write(': ping\n\n'), 25000)
    req.on('close', () => {
        clearInterval(heartbeat)
        unsubscribe()
    })
})

module.exports = router

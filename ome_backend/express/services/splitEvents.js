// Pushes split changes to everyone looking at a group, so the payment popup
// opens and updates on every phone at the same time.
//
// In-process only: fine for a single server instance. When running more than
// one instance, swap the emitter for Postgres LISTEN/NOTIFY or Redis pub/sub;
// publish/subscribe keep the same signatures.
const { EventEmitter } = require('events')

const emitter = new EventEmitter()
emitter.setMaxListeners(0)

const channel = (groupId) => `group:${groupId}`

// `split` is the full snapshot (or null when the group has no active bill).
function publishSplit(groupId, split) {
    emitter.emit(channel(groupId), { type: 'split', split })
}

function subscribe(groupId, listener) {
    emitter.on(channel(groupId), listener)
    return () => emitter.off(channel(groupId), listener)
}

module.exports = { publishSplit, subscribe }

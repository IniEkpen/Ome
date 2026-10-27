// Rules for new usernames and passwords. The app checks the same rules
// (yuwo/lib/utils/validators.dart) so people see problems as they type; the
// server enforces them so the API can't be used to get around them.
// Existing accounts keep working: these apply when creating, not signing in.

const USERNAME_MIN = 3
const USERNAME_MAX = 20
const PASSWORD_MIN = 8
const PASSWORD_MAX = 128

// Starts with a letter; then letters, numbers, _ or .; no ".." and no
// trailing "." (both look like typos and break @mentions).
const USERNAME = /^[A-Za-z][A-Za-z0-9_.]*$/

// Names that could be mistaken for staff, or that the system uses itself.
// Deleted accounts are renamed to deleted_<id>, so that prefix must never
// be taken, or deleting that account would fail.
const RESERVED = new Set([
    'admin', 'administrator', 'api', 'billing', 'help', 'me', 'mod', 'moderator', 'null', 'official',
    'root', 'security', 'staff', 'support', 'system', 'undefined', 'yuwo', 'yuwoapp', 'yuwo_support',
])
const RESERVED_PREFIX = 'deleted_'

// The word under passwords people pick most, e.g. "Password1!" -> "password".
// See commonCore for how a password is reduced to its word.
const COMMON = new Set([
    'password', 'passw', 'pass', 'qwerty', 'qwertyuiop', 'asdf', 'asdfgh', 'zxcvbnm', 'letmein', 'welcome',
    'iloveyou', 'admin', 'abc', 'abcd', 'abcdef', 'monkey', 'dragon', 'football', 'baseball', 'soccer',
    'sunshine', 'princess', 'trustno', 'master', 'shadow', 'superman', 'batman', 'starwars', 'login',
    'secret', 'changeme', 'hello', 'freedom', 'whatever', 'yuwo', 'money',
])

/** Returns an error message for an unusable new username, or null. */
function usernameProblem(username) {
    if (typeof username !== 'string' || username.length === 0) return 'Choose a username.'
    if (username.length < USERNAME_MIN || username.length > USERNAME_MAX) {
        return `Usernames are ${USERNAME_MIN}-${USERNAME_MAX} characters.`
    }
    if (!USERNAME.test(username)) {
        return 'Usernames start with a letter and use only letters, numbers, _ or .'
    }
    if (username.includes('..') || username.endsWith('.')) return "Usernames can't have '..' or end with '.'"
    const lower = username.toLowerCase()
    if (RESERVED.has(lower) || lower.startsWith(RESERVED_PREFIX)) return 'That username is reserved. Try another.'
    return null
}

/** Returns an error message for a weak or unusable new password, or null. */
function passwordProblem(password, { username, email } = {}) {
    if (typeof password !== 'string' || password.length === 0) return 'Choose a password.'
    if (password.length < PASSWORD_MIN) return `Use at least ${PASSWORD_MIN} characters.`
    if (password.length > PASSWORD_MAX) return `Use at most ${PASSWORD_MAX} characters.`
    if (password !== password.trim()) return "Passwords can't start or end with a space."
    if (!/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/\d/.test(password) || !/[^A-Za-z\d]/.test(password)) {
        return 'Use upper and lower case letters, a number and a symbol.'
    }
    const lower = password.toLowerCase()
    const personal = [username, typeof email === 'string' ? email.split('@')[0] : null]
        .filter((part) => typeof part === 'string' && part.length >= 3)
        .map((part) => part.toLowerCase())
    if (personal.some((part) => lower.includes(part))) return "Your password can't contain your username or email."
    if (COMMON.has(commonCore(lower))) return 'That password is too easy to guess. Try another.'
    return null
}

// "P@ssw0rd2026" -> "password": drop the numbers and symbols people add at
// the ends, undo common letter swaps, then keep only the letters.
const SWAPS = { '@': 'a', 4: 'a', 3: 'e', 1: 'i', '!': 'i', 0: 'o', $: 's', 5: 's', 7: 't' }
function commonCore(lowerPassword) {
    return lowerPassword
        .replace(/^[^a-z]+|[^a-z]+$/g, '')
        .replace(/[@4310!$57]/g, (c) => SWAPS[c])
        .replace(/[^a-z]/g, '')
}

module.exports = { usernameProblem, passwordProblem, USERNAME_MAX }

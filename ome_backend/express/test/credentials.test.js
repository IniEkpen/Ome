const test = require('node:test')
const assert = require('node:assert/strict')
const { usernameProblem, passwordProblem } = require('../credentials')

test('accepts ordinary usernames', () => {
    for (const name of ['ada', 'Ada_Lovelace', 'bob.smith', 'cleo2026', 'a'.repeat(20)]) {
        assert.equal(usernameProblem(name), null, name)
    }
})

test('rejects bad usernames', () => {
    for (const name of [
        undefined, '', 'ab', 'a'.repeat(21), // length
        '1ada', '_ada', '.ada', 'ada smith', 'ada-smith', 'adá', 'ada@x', // characters
        'ada..smith', 'ada.', // typos
        'admin', 'Support', 'YUWO', 'deleted_5', 'Deleted_anything', // reserved
    ]) {
        assert.notEqual(usernameProblem(name), null, String(name))
    }
})

test('accepts strong passwords, including iOS suggested ones', () => {
    for (const password of ['Fexkut-3pyxco-dobqib', 'Correct Horse 9 battery', 'Tr0ub4dor&3', 'Yuwo-test-2026x']) {
        assert.equal(passwordProblem(password, { username: 'ada', email: 'ada@x.io' }), null, password)
    }
})

test('rejects weak passwords', () => {
    const cases = {
        'Sh0rt!': /at least 8/,
        [`Aa1!${'x'.repeat(130)}`]: /at most 128/,
        ' Secret12!': /space/,
        'Secret12! ': /space/,
        'alllower1!': /upper and lower/,
        'NoNumbers!': /upper and lower/,
        'NoSymbols123': /upper and lower/,
        'Password1!': /too easy/,
        'P@ssw0rd2026': /too easy/,
        'Pa$$word1!': /too easy/,
        'Pass_word9!': /too easy/,
        'Qwerty123!': /too easy/,
        'Ada_lovelace1!': /username or email/,
        'xxADA_LOVELACE1!': /username or email/, // any capitalisation
        'Cleo.Park99!': /username or email/, // email name
    }
    for (const [password, expected] of Object.entries(cases)) {
        assert.match(passwordProblem(password, { username: 'ada_lovelace', email: 'cleo.park@x.io' }) || '', expected, password)
    }
    assert.match(passwordProblem('Ada12345!', { username: 'ada' }), /username/)
    assert.equal(passwordProblem(undefined), 'Choose a password.')
})

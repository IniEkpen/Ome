const test = require('node:test')
const assert = require('node:assert/strict')
const crypto = require('crypto')
const { generateKeyPair, exportJWK, createLocalJWKSet, SignJWT } = require('jose')
const config = require('../config')
const oauth = require('../services/oauthService')

const GOOGLE_CLIENT = 'ios-client.apps.googleusercontent.com'
const APPLE_CLIENT = 'app.yuwo'

let key, otherKey
test.before(async () => {
    key = await generateKeyPair('RS256')
    otherKey = await generateKeyPair('RS256')
    const jwk = { ...(await exportJWK(key.publicKey)), kid: 'k1', alg: 'RS256' }
    const jwks = createLocalJWKSet({ keys: [jwk] })
    oauth.setKeySetsForTests({ google: jwks, apple: jwks })
    config.google.clientIds = [GOOGLE_CLIENT, 'web-client.apps.googleusercontent.com']
    config.apple.clientIds = [APPLE_CLIENT]
})

function token(claims, { issuer, audience, expires = '10m', signWith = key.privateKey } = {}) {
    return new SignJWT(claims)
        .setProtectedHeader({ alg: 'RS256', kid: 'k1' })
        .setIssuer(issuer)
        .setAudience(audience)
        .setSubject(claims.sub ?? '123')
        .setIssuedAt()
        .setExpirationTime(expires)
        .sign(signWith)
}
const google = (claims = {}, options = {}) =>
    token({ sub: 'g-1', ...claims }, { issuer: 'https://accounts.google.com', audience: GOOGLE_CLIENT, ...options })
const apple = (claims = {}, options = {}) =>
    token({ sub: 'a-1', ...claims }, { issuer: 'https://appleid.apple.com', audience: APPLE_CLIENT, ...options })
const rejects = (promise) => assert.rejects(promise, (e) => e.code === 'invalid_oauth_token')

test('accepts a genuine Google token and reads the verified email and name', async () => {
    const identity = await oauth.verifyGoogle(await google({
        email: 'Ada@Example.com', email_verified: true, given_name: 'Ada', family_name: 'Lovelace',
    }))
    assert.deepEqual(identity, { provider: 'google', sub: 'g-1', email: 'ada@example.com', firstName: 'Ada', lastName: 'Lovelace' })
})

test('accepts tokens for any configured Google client id (iOS or web)', async () => {
    const identity = await oauth.verifyGoogle(await google({}, { audience: 'web-client.apps.googleusercontent.com' }))
    assert.equal(identity.sub, 'g-1')
})

test('ignores an unverified email so it cannot be used to take over an account', async () => {
    const identity = await oauth.verifyGoogle(await google({ email: 'victim@example.com', email_verified: false }))
    assert.equal(identity.email, null)
})

test('rejects tokens for another app, from another issuer, expired, or signed with another key', async () => {
    await rejects(oauth.verifyGoogle(await google({}, { audience: 'someone-else' })))
    await rejects(oauth.verifyGoogle(await google({}, { issuer: 'https://evil.example.com' })))
    await rejects(oauth.verifyGoogle(await google({}, { expires: Math.floor(Date.now() / 1000) - 3600 })))
    await rejects(oauth.verifyGoogle(await google({}, { signWith: otherKey.privateKey })))
    await rejects(oauth.verifyGoogle('not-a-token'))
    await rejects(oauth.verifyGoogle(undefined))
})

test('an Apple token can not be used as a Google one', async () => {
    await rejects(oauth.verifyGoogle(await apple()))
})

test('Apple: checks the nonce the app generated', async () => {
    const rawNonce = 'r4nd0m'
    const hashed = crypto.createHash('sha256').update(rawNonce).digest('hex')
    const signed = await apple({ nonce: hashed, email: 'x@privaterelay.appleid.com', email_verified: 'true' })
    const identity = await oauth.verifyApple(signed, rawNonce)
    assert.deepEqual(identity, { provider: 'apple', sub: 'a-1', email: 'x@privaterelay.appleid.com' })
    await rejects(oauth.verifyApple(signed, 'a-different-nonce'))
})

test('a provider without client ids is reported as not set up', async () => {
    const saved = config.apple.clientIds
    config.apple.clientIds = []
    await assert.rejects(oauth.verifyApple('x'), (e) => e.code === 'oauth_unavailable' && e.status === 503)
    config.apple.clientIds = saved
})

test('usernames are made from the email or name and always valid', () => {
    assert.equal(oauth.usernameBase({ email: 'ada.lovelace+test@x.io' }), 'ada.lovelacetest')
    assert.equal(oauth.usernameBase({ firstName: 'Zoë', lastName: "O'Neil" }), 'ZoONeil')
    assert.equal(oauth.usernameBase({ email: 'é@x.io' }), 'user')
    assert.equal(oauth.usernameBase({}), 'user')
    assert.match(oauth.usernameBase({ email: `${'a'.repeat(60)}@x.io` }), /^[A-Za-z0-9_.]{3,30}$/)
})

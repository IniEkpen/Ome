const test = require('node:test')
const assert = require('node:assert/strict')
const { Profile } = require('../models/Profile')

const card = { default_payment_method_id: 'pm_1', card_exp_month: 12, card_exp_year: 2999 }
const verified = { payouts_enabled: true, connect_payouts_status: 'active', connect_requirements_due: false }

test('payment setup needs both a valid card and a verified Stripe account', () => {
    assert.equal(Profile.HasCompletedPaymentSetup({ ...card, ...verified }), true)
    assert.equal(Profile.HasCompletedPaymentSetup(card), false)
    assert.equal(Profile.HasCompletedPaymentSetup(verified), false)
})

test('an account is only verified once onboarding is fully finished', () => {
    assert.equal(Profile.HasVerifiedPayouts(verified), true)
    // Transfers active but no bank payouts yet (e.g. bank account not added).
    assert.equal(Profile.HasVerifiedPayouts({ ...verified, connect_payouts_status: 'pending' }), false)
    // Stripe still needs something from the user.
    assert.equal(Profile.HasVerifiedPayouts({ ...verified, connect_requirements_due: true }), false)
    assert.equal(Profile.HasVerifiedPayouts({ ...verified, payouts_enabled: false }), false)
    assert.equal(Profile.HasVerifiedPayouts(null), false)
})

test('the card summary tells the app whether payments are verified', () => {
    assert.equal(Profile.CardSummary({ ...card, ...verified }).paymentsVerified, true)
    assert.equal(Profile.CardSummary(card).paymentsVerified, false)
})

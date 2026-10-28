# Stripe setup

How money moves (US dollars only, no currency conversion):

1. Members save a card (SetupIntent, PaymentSheet in the app).
2. When a host confirms a bill, each member's card is charged on the **platform** account.
3. Each successful charge is **transferred** to the host's connected account
   (separate charges and transfers, linked with `source_transaction`). Co-hosts split it evenly.
   Hosts who haven't finished payout setup get the transfer as soon as they do.
4. Refunds and disputes come out of the platform balance: the platform is liable for losses.
   A host-initiated refund pulls the host's transfer back first. A lost dispute is absorbed by the
   platform unless `STRIPE_RECOVER_LOST_DISPUTES_FROM_HOSTS=true`.

Host accounts are created with the **Accounts v2 API**: US individuals, `recipient` configuration
(`stripe_balance.stripe_transfers`), no Stripe-hosted dashboard (`dashboard: none`), and
`fees_collector` / `losses_collector` set to `application`. That makes the platform responsible
for collecting host information, so hosts onboard entirely inside the app with Stripe's embedded
onboarding component and never sign in to Stripe or open a browser. They come back to the same
screen to update details or bank accounts when Stripe needs more.

## 1. Stripe Dashboard (test mode)

1. **Connect → Get started**: choose a marketplace, and say that the platform is responsible
   for negative balances, pricing and collecting requirements (onboarding). Complete the
   platform profile and accept the acknowledgements. Until you do, account creation fails with
   `account_creation_liability_unacknowledged` or
   `account_creation_requirement_collection_unacknowledged`.
2. **Settings → Connect → Branding**: optionally add your name, color and icon.
3. **Developers → API keys**: copy the test publishable and secret keys.

## 2. `ome_backend/.env`

```
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
```

That's enough to save cards, charge bills, onboard hosts and pay them. The server keeps host
payout status current by asking Stripe when the app loads the card or payout screen.

## 3. Webhooks (recommended)

With the [Stripe CLI](https://docs.stripe.com/stripe-cli), locally:

```
# Snapshot events for the platform and connected accounts -> STRIPE_WEBHOOK_SECRET
stripe listen --forward-to localhost:3000/payments/webhook \
  --forward-connect-to localhost:3000/payments/webhook

# Thin events for v2 host accounts -> STRIPE_ACCOUNTS_WEBHOOK_SECRET
stripe listen --forward-thin-to localhost:3000/payments/webhook/accounts \
  --thin-events 'v2.core.account[configuration.recipient].capability_status_updated,v2.core.account[requirements].updated,v2.core.account.updated'
```

Each `stripe listen` prints a `whsec_...`; put it in the matching variable.

In a deployed environment, create these in **Workbench → Webhooks** instead:

| Destination | URL | Events |
| --- | --- | --- |
| Your account, snapshot | `/payments/webhook` | `setup_intent.succeeded`, `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.requires_action`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.updated`, `charge.dispute.closed` |
| Connected accounts, thin | `/payments/webhook/accounts` | `v2.core.account[configuration.recipient].capability_status_updated`, `v2.core.account[requirements].updated`, `v2.core.account.updated` |

If you add a separate snapshot destination for connected accounts (`account.updated`) pointing at
`/payments/webhook`, put both secrets in `STRIPE_WEBHOOK_SECRET`, comma separated.

## 4. Test it

- Cards: `4242 4242 4242 4242` succeeds, `4000 0000 0000 9995` is declined,
  `4000 0000 0000 0259` opens a dispute after payment.
- Host onboarding (test mode): use test data, e.g. SSN `000-00-0000`, phone code `000-000`,
  routing `110000000`, account `000123456789`.
- Transfers wait for the charge's funds to become available. In test mode, charge with
  `4000 0000 0000 0077` to make funds available immediately.

## API

| Route | Who | What |
| --- | --- | --- |
| `GET /payments/config` | anyone | publishable key, currency |
| `GET /payments/card` | user | saved card (also refreshes pending payout status) |
| `POST /payments/card/setup-intent`, `/card/confirm` | user | save a card |
| `GET /payments/connect` | host | payout account status, refreshed from Stripe |
| `POST /payments/connect/account-session` | host | session for in-app onboarding, account management and payouts components |
| `POST /splits/:id/participants/:userId/refund` | host | refund a member's payment |
| `POST /payments/webhook`, `/payments/webhook/accounts` | Stripe | events |

Disputes are answered from the Stripe Dashboard. They are tracked in the `stripe_disputes` table.

After pulling these changes, run `npm run migrate`.

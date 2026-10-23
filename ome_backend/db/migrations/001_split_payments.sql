-- Group bill splitting + Stripe structure.
-- Builds on the tables in groupies.session.sql. Safe to run more than once.

-- Cards: a user "has a valid card" when a Stripe PaymentMethod is saved and
-- not expired. Only Stripe ids and display details are stored, never card numbers.
ALTER TABLE users ADD COLUMN IF NOT EXISTS default_payment_method_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_brand VARCHAR(32);
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_last4 VARCHAR(4);
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_exp_month INT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_exp_year INT;
-- Stripe Connect account that receives payouts when this user hosts a bill.
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_connect_account_id TEXT UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS payouts_enabled BOOLEAN NOT NULL DEFAULT false;
-- users.card_info is no longer read; card status comes from the columns above.

-- The original ALTER used curly quotes and fails, so the column may be missing.
-- Members default to a pending invite; owners are always in their own group.
ALTER TABLE groupmembers ADD COLUMN IF NOT EXISTS status VARCHAR(50) NOT NULL DEFAULT 'pending';
ALTER TABLE groupmembers ALTER COLUMN status SET DEFAULT 'pending';
UPDATE groupmembers SET status = 'accepted' WHERE role = 'owner';

-- One bill being split inside a group.
CREATE TABLE IF NOT EXISTS splits (
    id            SERIAL PRIMARY KEY,
    group_id      INT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    created_by    INT NOT NULL REFERENCES users(id),
    title         VARCHAR(255) NOT NULL,
    status        VARCHAR(20) NOT NULL DEFAULT 'claiming'
                  CHECK (status IN ('claiming', 'confirmed', 'settled', 'cancelled')),
    split_mode    VARCHAR(10) NOT NULL DEFAULT 'by_item'
                  CHECK (split_mode IN ('by_item', 'even')),
    currency      CHAR(3) NOT NULL DEFAULT 'usd',
    tax_cents     INT NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
    tip_cents     INT NOT NULL DEFAULT 0 CHECK (tip_cents >= 0),
    -- Bumped on every change so clients can ignore stale live updates.
    version       INT NOT NULL DEFAULT 1,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at  TIMESTAMPTZ
);

-- Only one bill can be open for claiming per group at a time.
CREATE UNIQUE INDEX IF NOT EXISTS splits_one_open_per_group
    ON splits (group_id) WHERE status = 'claiming';

CREATE TABLE IF NOT EXISTS split_items (
    id                SERIAL PRIMARY KEY,
    split_id          INT NOT NULL REFERENCES splits(id) ON DELETE CASCADE,
    name              VARCHAR(255) NOT NULL,
    quantity          INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price_cents  INT NOT NULL CHECK (unit_price_cents >= 0),
    position          INT NOT NULL DEFAULT 0
);

-- "I had this": one row per person per item. Shared items have several rows.
CREATE TABLE IF NOT EXISTS split_item_claims (
    item_id  INT NOT NULL REFERENCES split_items(id) ON DELETE CASCADE,
    user_id  INT NOT NULL REFERENCES users(id),
    PRIMARY KEY (item_id, user_id)
);

-- Everyone in the group when the bill was opened. Hosts foot the bill.
CREATE TABLE IF NOT EXISTS split_participants (
    split_id                  INT NOT NULL REFERENCES splits(id) ON DELETE CASCADE,
    user_id                   INT NOT NULL REFERENCES users(id),
    is_host                   BOOLEAN NOT NULL DEFAULT false,
    waived_cents              INT NOT NULL DEFAULT 0 CHECK (waived_cents >= 0),
    -- Frozen when a host confirms.
    owed_cents                INT,
    charge_cents              INT,
    payment_status            VARCHAR(20) NOT NULL DEFAULT 'pending'
                              CHECK (payment_status IN ('pending', 'not_required', 'processing',
                                                        'succeeded', 'failed', 'requires_action')),
    stripe_payment_intent_id  TEXT UNIQUE,
    PRIMARY KEY (split_id, user_id)
);

-- Money moved from the platform to a host's Connect account after a member pays.
CREATE TABLE IF NOT EXISTS split_payouts (
    id                        SERIAL PRIMARY KEY,
    split_id                  INT NOT NULL REFERENCES splits(id) ON DELETE CASCADE,
    host_user_id              INT NOT NULL REFERENCES users(id),
    source_payment_intent_id  TEXT NOT NULL,
    amount_cents              INT NOT NULL CHECK (amount_cents >= 0),
    status                    VARCHAR(30) NOT NULL DEFAULT 'awaiting_host_onboarding'
                              CHECK (status IN ('awaiting_host_onboarding', 'paid', 'failed')),
    stripe_transfer_id        TEXT UNIQUE,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_payment_intent_id, host_user_id)
);

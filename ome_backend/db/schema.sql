-- Ome / Yuwo database schema: every table the app and API use.
--
-- Run it with `npm run migrate` (wraps the whole file in one transaction).
-- Safe to run more than once. It builds an empty database from scratch and
-- also upgrades databases created from the old groupies.session.sql and
-- db/migrations/001_split_payments.sql, which this file replaces.
--
-- Conventions: money is integer cents, times are TIMESTAMPTZ, and only
-- Stripe ids and display details are stored, never card numbers.
--
-- When adding a column, put it in the CREATE TABLE *and* in that table's
-- "upgrade" block (ADD COLUMN IF NOT EXISTS) so existing databases get it too.

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END
$$ LANGUAGE plpgsql;


-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id                          SERIAL PRIMARY KEY,
    username                    VARCHAR(30) NOT NULL
                                CHECK (username ~ '^[A-Za-z0-9_.]{3,30}$'),
    first_name                  VARCHAR(100),
    last_name                   VARCHAR(100),
    email                       VARCHAR(255),
    phone                       VARCHAR(32),
    -- scrypt$<salt>$<hash> (see express/auth.js)
    password                    TEXT,
    -- Default for payments this user makes: private ones stay off the
    -- public network map and are only shown to the two people involved.
    transactions_private        BOOLEAN NOT NULL DEFAULT false,

    -- Card on file. A user "has a valid card" when a PaymentMethod is saved
    -- and not expired; that gates creating and joining groups.
    stripe_customer_id          TEXT UNIQUE,
    default_payment_method_id   TEXT,
    card_brand                  VARCHAR(32),
    card_last4                  VARCHAR(4),
    card_exp_month              INT CHECK (card_exp_month BETWEEN 1 AND 12),
    card_exp_year               INT,

    -- Stripe Connect account that receives payouts when this user hosts.
    stripe_connect_account_id   TEXT UNIQUE,
    payouts_enabled             BOOLEAN NOT NULL DEFAULT false,

    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at               TIMESTAMPTZ,
    -- Set when the person deletes their account. The row stays (scrubbed of
    -- personal details) so other people's payment history still adds up.
    deleted_at                  TIMESTAMPTZ
);

-- upgrade
ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_name VARCHAR(100);
ALTER TABLE users ADD COLUMN IF NOT EXISTS transactions_private BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS default_payment_method_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_brand VARCHAR(32);
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_last4 VARCHAR(4);
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_exp_month INT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS card_exp_year INT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_connect_account_id TEXT UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS payouts_enabled BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
-- Replaced by the card columns above; nothing reads it any more.
ALTER TABLE users DROP COLUMN IF EXISTS card_info;

-- Usernames and emails are unique ignoring case ("Bob" and "bob" are the same
-- person). On an old database this fails if duplicates exist: rename them first.
CREATE UNIQUE INDEX IF NOT EXISTS users_username_lower_key ON users (lower(username));
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_key ON users (lower(email)) WHERE email IS NOT NULL;
-- Prefix search for the network map ("find a person").
CREATE INDEX IF NOT EXISTS users_username_search ON users (lower(username) text_pattern_ops);

DROP TRIGGER IF EXISTS users_set_updated_at ON users;
CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ---------------------------------------------------------------------------
-- groups and groupmembers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS groups (
    id                SERIAL PRIMARY KEY,
    group_name        VARCHAR(255) NOT NULL,
    created_by_user   INT REFERENCES users(id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- upgrade
ALTER TABLE groups ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE groups ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
UPDATE groups SET group_name = 'Untitled group' WHERE group_name IS NULL;
ALTER TABLE groups ALTER COLUMN group_name SET NOT NULL;

DROP TRIGGER IF EXISTS groups_set_updated_at ON groups;
CREATE TRIGGER groups_set_updated_at BEFORE UPDATE ON groups
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- One row per person per group. Owners are always accepted members of their
-- own group; everyone else starts as a pending invite.
CREATE TABLE IF NOT EXISTS groupmembers (
    id            SERIAL PRIMARY KEY,
    group_id      INT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id       INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role          VARCHAR(50) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'member')),
    status        VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
    invited_by    INT REFERENCES users(id) ON DELETE SET NULL,
    -- When the invite was sent (or the group created, for the owner).
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- When they accepted. Drives "X joined" in the home activity feed.
    joined_at     TIMESTAMPTZ,
    CONSTRAINT unique_group_user UNIQUE (group_id, user_id)
);

-- upgrade (the old ALTER for status used curly quotes and failed, so it may be missing)
ALTER TABLE groupmembers ADD COLUMN IF NOT EXISTS role VARCHAR(50) NOT NULL DEFAULT 'member';
ALTER TABLE groupmembers ADD COLUMN IF NOT EXISTS status VARCHAR(50) NOT NULL DEFAULT 'pending';
ALTER TABLE groupmembers ALTER COLUMN status SET DEFAULT 'pending';
ALTER TABLE groupmembers ADD COLUMN IF NOT EXISTS invited_by INT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE groupmembers ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE groupmembers ADD COLUMN IF NOT EXISTS joined_at TIMESTAMPTZ;
DELETE FROM groupmembers WHERE group_id IS NULL OR user_id IS NULL;
ALTER TABLE groupmembers ALTER COLUMN group_id SET NOT NULL;
ALTER TABLE groupmembers ALTER COLUMN user_id SET NOT NULL;
-- The original foreign keys had no ON DELETE, so a group with members couldn't be deleted.
ALTER TABLE groups DROP CONSTRAINT IF EXISTS groups_created_by_user_fkey,
    ADD CONSTRAINT groups_created_by_user_fkey
        FOREIGN KEY (created_by_user) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE groupmembers DROP CONSTRAINT IF EXISTS groupmembers_group_id_fkey,
    ADD CONSTRAINT groupmembers_group_id_fkey FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE;
ALTER TABLE groupmembers DROP CONSTRAINT IF EXISTS groupmembers_user_id_fkey,
    ADD CONSTRAINT groupmembers_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
-- Older rows keep joined_at NULL: the real join time is unknown, and
-- backfilling would flood the activity feed with "joined just now".
UPDATE groupmembers SET status = 'accepted' WHERE role = 'owner';
DO $$ BEGIN
    ALTER TABLE groupmembers ADD CONSTRAINT groupmembers_role_check CHECK (role IN ('owner', 'member'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE groupmembers ADD CONSTRAINT groupmembers_status_check CHECK (status IN ('pending', 'accepted'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER TABLE groupmembers ADD CONSTRAINT unique_group_user UNIQUE (group_id, user_id);
EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;

-- Exactly one owner per group.
CREATE UNIQUE INDEX IF NOT EXISTS groupmembers_one_owner ON groupmembers (group_id) WHERE role = 'owner';
-- "Which groups am I in?" is the most common lookup.
CREATE INDEX IF NOT EXISTS groupmembers_user ON groupmembers (user_id, status);


-- ---------------------------------------------------------------------------
-- splits: one bill being split inside a group
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS splits (
    id              SERIAL PRIMARY KEY,
    group_id        INT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    created_by      INT NOT NULL REFERENCES users(id),
    title           VARCHAR(255) NOT NULL,
    -- Optional details read off the receipt (fast_app OCR).
    merchant_name   VARCHAR(255),
    receipt_date    DATE,
    status          VARCHAR(20) NOT NULL DEFAULT 'claiming'
                    CHECK (status IN ('claiming', 'confirmed', 'settled', 'cancelled')),
    split_mode      VARCHAR(10) NOT NULL DEFAULT 'by_item'
                    CHECK (split_mode IN ('by_item', 'even')),
    currency        CHAR(3) NOT NULL DEFAULT 'usd',
    tax_cents       INT NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
    tip_cents       INT NOT NULL DEFAULT 0 CHECK (tip_cents >= 0),
    -- Bumped on every change so clients can ignore stale live updates.
    version         INT NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at    TIMESTAMPTZ,
    -- The host who confirmed; credited with any waivers in the activity feed.
    confirmed_by    INT REFERENCES users(id) ON DELETE SET NULL,
    settled_at      TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ
);

-- upgrade
ALTER TABLE splits ADD COLUMN IF NOT EXISTS merchant_name VARCHAR(255);
ALTER TABLE splits ADD COLUMN IF NOT EXISTS receipt_date DATE;
ALTER TABLE splits ADD COLUMN IF NOT EXISTS confirmed_by INT REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE splits ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;
ALTER TABLE splits ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- Only one bill can be open for claiming per group at a time.
CREATE UNIQUE INDEX IF NOT EXISTS splits_one_open_per_group ON splits (group_id) WHERE status = 'claiming';
CREATE INDEX IF NOT EXISTS splits_group_status ON splits (group_id, status);

CREATE TABLE IF NOT EXISTS split_items (
    id                SERIAL PRIMARY KEY,
    split_id          INT NOT NULL REFERENCES splits(id) ON DELETE CASCADE,
    name              VARCHAR(255) NOT NULL,
    quantity          INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price_cents  INT NOT NULL CHECK (unit_price_cents >= 0),
    position          INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS split_items_split ON split_items (split_id, position);

-- "I had this": one row per person per item. Shared items have several rows.
CREATE TABLE IF NOT EXISTS split_item_claims (
    item_id     INT NOT NULL REFERENCES split_items(id) ON DELETE CASCADE,
    user_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    claimed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id, user_id)
);

-- upgrade
ALTER TABLE split_item_claims ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ NOT NULL DEFAULT now();

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
    -- Stripe's decline code (e.g. 'insufficient_funds') so hosts know why.
    payment_error_code        VARCHAR(64),
    paid_at                   TIMESTAMPTZ,
    PRIMARY KEY (split_id, user_id)
);

-- upgrade
ALTER TABLE split_participants ADD COLUMN IF NOT EXISTS payment_error_code VARCHAR(64);
ALTER TABLE split_participants ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

-- "Bills I'm part of" for the home page.
CREATE INDEX IF NOT EXISTS split_participants_user ON split_participants (user_id);

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
    paid_at                   TIMESTAMPTZ,
    UNIQUE (source_payment_intent_id, host_user_id)
);

-- upgrade
ALTER TABLE split_payouts ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

-- Released when a host finishes Connect onboarding.
CREATE INDEX IF NOT EXISTS split_payouts_host_status ON split_payouts (host_user_id, status);


-- ---------------------------------------------------------------------------
-- transactions: completed payments between two people
-- ---------------------------------------------------------------------------
-- One row per member -> host share of a successful charge. Feeds the network
-- map (public rows build the graph) and "You paid / paid you" on the home page.

-- The original transactions table (balance, VARCHAR dates, a required
-- transfer id) was never written to by the API. Drop it when empty, otherwise
-- keep its rows as transactions_legacy.
DO $$
DECLARE
    legacy_rows BIGINT;
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = current_schema() AND table_name = 'transactions'
                 AND column_name = 'balance') THEN
        EXECUTE 'SELECT count(*) FROM transactions' INTO legacy_rows;
        IF legacy_rows = 0 THEN
            DROP TABLE transactions;
        ELSE
            ALTER TABLE transactions RENAME TO transactions_legacy;
            ALTER TABLE transactions_legacy RENAME CONSTRAINT transactions_pkey TO transactions_legacy_pkey;
            ALTER SEQUENCE IF EXISTS transactions_id_seq RENAME TO transactions_legacy_id_seq;
        END IF;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS transactions (
    id                        BIGSERIAL PRIMARY KEY,
    sender_id                 INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id              INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount_cents              INT NOT NULL CHECK (amount_cents > 0),
    currency                  CHAR(3) NOT NULL DEFAULT 'usd',
    split_id                  INT REFERENCES splits(id) ON DELETE SET NULL,
    group_id                  INT REFERENCES groups(id) ON DELETE SET NULL,
    stripe_payment_intent_id  TEXT,
    -- Copied from the payer's users.transactions_private when recorded.
    is_private                BOOLEAN NOT NULL DEFAULT false,
    note                      VARCHAR(255),
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (sender_id <> recipient_id),
    -- A webhook retry can't record the same share twice.
    UNIQUE (stripe_payment_intent_id, recipient_id)
);

-- Graph walks go out from a person in both directions over public rows.
CREATE INDEX IF NOT EXISTS transactions_sender_public ON transactions (sender_id) WHERE NOT is_private;
CREATE INDEX IF NOT EXISTS transactions_recipient_public ON transactions (recipient_id) WHERE NOT is_private;
-- A person's own history (public and private), newest first.
CREATE INDEX IF NOT EXISTS transactions_sender_time ON transactions (sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS transactions_recipient_time ON transactions (recipient_id, created_at DESC);


-- ---------------------------------------------------------------------------
-- stripe_webhook_events: Stripe retries webhooks, so each event is handled once
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS stripe_webhook_events (
    id            TEXT PRIMARY KEY,          -- evt_...
    type          VARCHAR(100) NOT NULL,
    received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Null until the handler finishes, so a failed attempt is retried.
    processed_at  TIMESTAMPTZ
);

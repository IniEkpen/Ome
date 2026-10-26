-- Mock data for development, demos and the App Review account.
--
-- Run it with `npm run seed`, which applies schema.sql first and then this
-- file in one transaction. Re-running resets the mock data to a fresh state
-- (timestamps are relative to now), and leaves real accounts alone.
--
-- Every mock user signs in with the password: password123
--
--   demo   Demo User     the main account: hosts two groups, has bills open
--   ada    Ada Lovelace  owns Ski Trip, invited demo to it
--   ben    Ben Carter
--   cleo   Cleo Park     hosts Pizza night, which is charging demo
--   dev    Dev Shah      has a pending invite to Friday Dinner
--   eli    Eli Moreno
--   fay    Fay Okafor    pays privately by default
--   gus    Gus Ito       no card on file, for testing the card gate
--
-- The mock cards satisfy the card gate but have no Stripe customer, so a real
-- charge against them fails. Add a Stripe test card from Profile to charge.
--
-- Mock users are recognised by their @example.com email (a domain reserved
-- for examples), so a real account that happens to be called "demo" is never
-- deleted.

DO $$
DECLARE
    -- scrypt$<salt>$<hash> of 'password123' (see express/auth.js)
    pw CONSTANT TEXT := 'scrypt$bc60198887dbec5dba61414bf352f0c2$6a3046a001fa5bd46c3262b3daa56b2cf2c38f9619536c71356de7a5e6c5dcd45bbdcd5e07a68bebc7c67ef46ea2257135c7e9f389a481fc6a138b949023d5f1';
    mock_users CONSTANT TEXT[] := ARRAY['demo', 'ada', 'ben', 'cleo', 'dev', 'eli', 'fay', 'gus'];

    demo INT; ada INT; ben INT; cleo INT; dev INT; eli INT; fay INT; gus INT;
    dinner INT; roommates INT; book_club INT; ski_trip INT;
    tack_room INT; costco INT; pizza INT;
    burger INT; fries INT; margaritas INT; salad INT; wings INT;
BEGIN
    -- Reset: refuse to touch a real account that has one of these usernames.
    IF EXISTS (SELECT 1 FROM users
               WHERE lower(username) = ANY (mock_users)
                 AND (email IS NULL OR email NOT LIKE '%@example.com')) THEN
        RAISE EXCEPTION 'A real account uses one of the mock usernames (%). Rename it before seeding.',
            array_to_string(mock_users, ', ');
    END IF;

    -- Groups cascade to their splits, items, claims, participants and payouts;
    -- deleting the users then cascades to memberships and transactions.
    DELETE FROM groups WHERE created_by_user IN
        (SELECT id FROM users WHERE lower(username) = ANY (mock_users));
    DELETE FROM users WHERE lower(username) = ANY (mock_users);

    -- -----------------------------------------------------------------------
    -- users
    -- -----------------------------------------------------------------------
    INSERT INTO users (username, first_name, last_name, email, phone, password,
                       default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year,
                       created_at, last_login_at)
    VALUES ('demo', 'Demo', 'User', 'demo@example.com', '555-0100', pw,
            'pm_mock_demo', 'visa', '4242', 12, 2030, now() - interval '60 days', now() - interval '1 hour')
    RETURNING id INTO demo;

    INSERT INTO users (username, first_name, last_name, email, phone, password,
                       default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year, created_at)
    VALUES ('ada', 'Ada', 'Lovelace', 'ada@example.com', '555-0101', pw,
            'pm_mock_ada', 'mastercard', '4444', 8, 2029, now() - interval '55 days')
    RETURNING id INTO ada;

    INSERT INTO users (username, first_name, last_name, email, phone, password,
                       default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year, created_at)
    VALUES ('ben', 'Ben', 'Carter', 'ben@example.com', '555-0102', pw,
            'pm_mock_ben', 'visa', '1881', 3, 2028, now() - interval '50 days')
    RETURNING id INTO ben;

    INSERT INTO users (username, first_name, last_name, email, phone, password,
                       default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year, created_at)
    VALUES ('cleo', 'Cleo', 'Park', 'cleo@example.com', '555-0103', pw,
            'pm_mock_cleo', 'amex', '8431', 11, 2029, now() - interval '45 days')
    RETURNING id INTO cleo;

    INSERT INTO users (username, first_name, last_name, email, phone, password,
                       default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year, created_at)
    VALUES ('dev', 'Dev', 'Shah', 'dev@example.com', '555-0104', pw,
            'pm_mock_dev', 'visa', '0077', 6, 2030, now() - interval '40 days')
    RETURNING id INTO dev;

    INSERT INTO users (username, first_name, last_name, email, phone, password,
                       default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year, created_at)
    VALUES ('eli', 'Eli', 'Moreno', 'eli@example.com', '555-0105', pw,
            'pm_mock_eli', 'discover', '1117', 1, 2031, now() - interval '35 days')
    RETURNING id INTO eli;

    INSERT INTO users (username, first_name, last_name, email, phone, password, transactions_private,
                       default_payment_method_id, card_brand, card_last4, card_exp_month, card_exp_year, created_at)
    VALUES ('fay', 'Fay', 'Okafor', 'fay@example.com', '555-0106', pw, true,
            'pm_mock_fay', 'visa', '5556', 9, 2029, now() - interval '30 days')
    RETURNING id INTO fay;

    INSERT INTO users (username, first_name, last_name, email, phone, password, created_at)
    VALUES ('gus', 'Gus', 'Ito', 'gus@example.com', '555-0107', pw, now() - interval '2 days')
    RETURNING id INTO gus;

    -- -----------------------------------------------------------------------
    -- groups
    -- -----------------------------------------------------------------------
    INSERT INTO groups (group_name, created_by_user, created_at)
    VALUES ('Friday Dinner', demo, now() - interval '7 days') RETURNING id INTO dinner;
    INSERT INTO groups (group_name, created_by_user, created_at)
    VALUES ('Roommates', demo, now() - interval '30 days') RETURNING id INTO roommates;
    INSERT INTO groups (group_name, created_by_user, created_at)
    VALUES ('Book Club', cleo, now() - interval '20 days') RETURNING id INTO book_club;
    INSERT INTO groups (group_name, created_by_user, created_at)
    VALUES ('Ski Trip', ada, now() - interval '14 days') RETURNING id INTO ski_trip;

    INSERT INTO groupmembers (group_id, user_id, role, status, invited_by, created_at, joined_at) VALUES
        -- Friday Dinner: dev hasn't answered the invite yet.
        (dinner, demo, 'owner',  'accepted', NULL, now() - interval '7 days', now() - interval '7 days'),
        (dinner, ada,  'member', 'accepted', demo, now() - interval '7 days', now() - interval '6 days'),
        (dinner, ben,  'member', 'accepted', demo, now() - interval '7 days', now() - interval '2 days'),
        (dinner, cleo, 'member', 'accepted', demo, now() - interval '7 days', now() - interval '3 hours'),
        (dinner, dev,  'member', 'pending',  demo, now() - interval '1 day',  NULL),
        -- Roommates
        (roommates, demo, 'owner',  'accepted', NULL, now() - interval '30 days', now() - interval '30 days'),
        (roommates, eli,  'member', 'accepted', demo, now() - interval '30 days', now() - interval '29 days'),
        (roommates, fay,  'member', 'accepted', demo, now() - interval '30 days', now() - interval '28 days'),
        -- Book Club: cleo hosts, demo is a member.
        (book_club, cleo, 'owner',  'accepted', NULL, now() - interval '20 days', now() - interval '20 days'),
        (book_club, demo, 'member', 'accepted', cleo, now() - interval '20 days', now() - interval '19 days'),
        (book_club, ada,  'member', 'accepted', cleo, now() - interval '20 days', now() - interval '18 days'),
        -- Ski Trip: demo has a pending invite from ada (shows on the Groups tab).
        (ski_trip, ada,  'owner',  'accepted', NULL, now() - interval '14 days', now() - interval '14 days'),
        (ski_trip, ben,  'member', 'accepted', ada,  now() - interval '14 days', now() - interval '13 days'),
        (ski_trip, dev,  'member', 'accepted', ada,  now() - interval '14 days', now() - interval '12 days'),
        (ski_trip, eli,  'member', 'accepted', ada,  now() - interval '14 days', now() - interval '11 days'),
        (ski_trip, demo, 'member', 'pending',  ada,  now() - interval '5 hours', NULL);

    -- -----------------------------------------------------------------------
    -- Friday Dinner: "The Tack Room", open for claiming
    -- -----------------------------------------------------------------------
    -- demo hosts and hasn't picked items yet, so Home shows "Pick your items".
    INSERT INTO splits (group_id, created_by, title, merchant_name, receipt_date, status, split_mode,
                        tax_cents, tip_cents, version, created_at)
    VALUES (dinner, demo, 'The Tack Room', 'The Tack Room', current_date, 'claiming', 'by_item',
            640, 1200, 4, now() - interval '2 hours')
    RETURNING id INTO tack_room;

    INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position)
    VALUES (tack_room, 'Smash burger', 1, 1850, 0) RETURNING id INTO burger;
    INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position)
    VALUES (tack_room, 'Truffle fries', 2, 650, 1) RETURNING id INTO fries;
    INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position)
    VALUES (tack_room, 'Margarita', 2, 1200, 2) RETURNING id INTO margaritas;
    INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position)
    VALUES (tack_room, 'Caesar salad', 1, 1400, 3) RETURNING id INTO salad;
    INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position)
    VALUES (tack_room, 'Hot wings', 1, 1500, 4) RETURNING id INTO wings;

    INSERT INTO split_participants (split_id, user_id, is_host) VALUES
        (tack_room, demo, true),
        (tack_room, ada,  false),
        (tack_room, ben,  false),
        (tack_room, cleo, false);

    -- The fries are shared by ada and ben; the wings are still unclaimed.
    INSERT INTO split_item_claims (item_id, user_id, claimed_at) VALUES
        (burger,     ada,  now() - interval '100 minutes'),
        (fries,      ada,  now() - interval '100 minutes'),
        (fries,      ben,  now() - interval '90 minutes'),
        (margaritas, ben,  now() - interval '90 minutes'),
        (salad,      cleo, now() - interval '30 minutes');

    -- -----------------------------------------------------------------------
    -- Roommates: "Costco run", settled 5 days ago
    -- -----------------------------------------------------------------------
    -- $126.00 split evenly three ways. demo waived $5 of fay's share.
    INSERT INTO splits (group_id, created_by, title, merchant_name, receipt_date, status, split_mode,
                        version, created_at, confirmed_at, confirmed_by, settled_at)
    VALUES (roommates, demo, 'Costco run', 'Costco', current_date - 6, 'settled', 'even',
            6, now() - interval '6 days', now() - interval '5 days', demo, now() - interval '5 days')
    RETURNING id INTO costco;

    INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position) VALUES
        (costco, 'Groceries', 1, 9600, 0),
        (costco, 'Paper towels and soap', 1, 3000, 1);

    INSERT INTO split_participants (split_id, user_id, is_host, waived_cents, owed_cents, charge_cents,
                                    payment_status, stripe_payment_intent_id, paid_at) VALUES
        (costco, demo, true,  0,   4200, 0,    'not_required', NULL, NULL),
        (costco, eli,  false, 0,   4200, 4200, 'succeeded', 'pi_mock_costco_eli', now() - interval '5 days'),
        (costco, fay,  false, 500, 4200, 3700, 'succeeded', 'pi_mock_costco_fay', now() - interval '5 days');

    -- demo hasn't set up payouts, so the money is held for them.
    INSERT INTO split_payouts (split_id, host_user_id, source_payment_intent_id, amount_cents, status, created_at) VALUES
        (costco, demo, 'pi_mock_costco_eli', 4200, 'awaiting_host_onboarding', now() - interval '5 days'),
        (costco, demo, 'pi_mock_costco_fay', 3700, 'awaiting_host_onboarding', now() - interval '5 days');

    INSERT INTO transactions (sender_id, recipient_id, amount_cents, split_id, group_id,
                              stripe_payment_intent_id, is_private, note, created_at) VALUES
        (eli, demo, 4200, costco, roommates, 'pi_mock_costco_eli', false, 'Costco run', now() - interval '5 days'),
        (fay, demo, 3700, costco, roommates, 'pi_mock_costco_fay', true,  'Costco run', now() - interval '5 days');

    -- -----------------------------------------------------------------------
    -- Book Club: "Pizza night", confirmed and still charging demo
    -- -----------------------------------------------------------------------
    -- $54 of pizza + $6 tip = $60, three ways. ada has paid; demo's is processing.
    INSERT INTO splits (group_id, created_by, title, merchant_name, receipt_date, status, split_mode,
                        tip_cents, version, created_at, confirmed_at, confirmed_by)
    VALUES (book_club, cleo, 'Pizza night', 'Tony''s Pizza', current_date - 1, 'confirmed', 'even',
            600, 3, now() - interval '1 day', now() - interval '1 hour', cleo)
    RETURNING id INTO pizza;

    INSERT INTO split_items (split_id, name, quantity, unit_price_cents, position) VALUES
        (pizza, 'Large pizza', 3, 1800, 0);

    INSERT INTO split_participants (split_id, user_id, is_host, owed_cents, charge_cents,
                                    payment_status, stripe_payment_intent_id, paid_at) VALUES
        (pizza, cleo, true,  2000, 0,    'not_required', NULL, NULL),
        (pizza, ada,  false, 2000, 2000, 'succeeded',  'pi_mock_pizza_ada',  now() - interval '55 minutes'),
        (pizza, demo, false, 2000, 2000, 'processing', 'pi_mock_pizza_demo', NULL);

    INSERT INTO split_payouts (split_id, host_user_id, source_payment_intent_id, amount_cents, status, created_at) VALUES
        (pizza, cleo, 'pi_mock_pizza_ada', 2000, 'awaiting_host_onboarding', now() - interval '55 minutes');

    INSERT INTO transactions (sender_id, recipient_id, amount_cents, split_id, group_id,
                              stripe_payment_intent_id, is_private, note, created_at) VALUES
        (ada, cleo, 2000, pizza, book_club, 'pi_mock_pizza_ada', false, 'Pizza night', now() - interval '55 minutes');

    -- -----------------------------------------------------------------------
    -- Older payments, so the network map has several layers. Each is tied to
    -- a group both people are in, as payments made through the app are.
    --   layer 1: ada, cleo, eli   layer 2: ben, dev   (fay's payments are all private)
    -- -----------------------------------------------------------------------
    INSERT INTO transactions (sender_id, recipient_id, amount_cents, group_id,
                              stripe_payment_intent_id, is_private, note, created_at) VALUES
        (demo, ada,  2400, book_club, 'pi_mock_old_1', false, 'Concert tickets', now() - interval '25 days'),
        (cleo, demo, 4000, book_club, 'pi_mock_old_2', false, 'Book Club',       now() - interval '18 days'),
        (ada,  dev,  8000, ski_trip,  'pi_mock_old_3', false, 'Ski Trip',        now() - interval '12 days'),
        (ben,  cleo, 1500, dinner,    'pi_mock_old_4', false, 'Coffee',          now() - interval '10 days'),
        (dev,  eli,  3000, ski_trip,  'pi_mock_old_5', false, 'Gas money',       now() - interval '9 days'),
        (ben,  ada,  6000, ski_trip,  'pi_mock_old_6', false, 'Ski Trip',        now() - interval '8 days'),
        (fay,  eli,   900, roommates, 'pi_mock_old_7', true,  'Lunch',           now() - interval '4 days'),
        (demo, fay,  1250, roommates, 'pi_mock_old_8', true,  'Movie night',     now() - interval '3 days');

    RAISE NOTICE 'Seeded % mock users (password: password123). Sign in as "demo".', array_length(mock_users, 1);
END $$;

CREATE TABLE users(
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(255),
    password TEXT,
    stripe_customer_id TEXT UNIQUE


);


CREATE TABLE transactions(
    id SERIAL PRIMARY KEY,
    balance INT,
    sender_id  INT REFERENCES users(id),
    recipient_id  INT REFERENCES users(id),
    current_status VARCHAR(255)  NOT NULL,
    stripe_transfer_id  TEXT  NOT NULL,
    created_at  VARCHAR(255) NOT NULL,
    updated_at  VARCHAR(255) NOT NULL
);


CREATE TABLE groups(
    id  SERIAL PRIMARY KEY,
    group_name VARCHAR(255),
    created_by_user INT REFERENCES users(id)
);


CREATE TABLE groupmembers(
    id  SERIAL PRIMARY KEY,
    group_id INT REFERENCES groups(id),
    user_id INT REFERENCES users(id)
);




ALTER TABLE  groupmembers
ADD COLUMN  role VARCHAR(50) NOT NULL DEFAULT 'member';
ALTER TABLE users
ADD COLUMN card_info VARCHAR(25) NOT NULL DEFAULT 'yes';


ALTER TABLE groupmembers
ADD CONSTRAINT unique_group_user UNIQUE (group_id, user_id);


ALTER TABLE groupmembers
ADD COLUMN status VARCHAR(50) NOT NULL DEFAULT ‘pending’


const express = require('express');
const app = express();
app.use(cors());
app.use(express.json());
module.exports = app;

const userRoutes = require('./routes/userRoutes');

app.use('/users', userRoutes);
// Create a user account



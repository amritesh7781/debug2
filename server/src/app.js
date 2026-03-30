const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Serve static files from the React frontend app
app.use(express.static(path.join(__dirname, '../public')));

// Health Check Route
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    message: 'ShopSmart Backend is running',
    timestamp: new Date().toISOString()
  });
});

// Any route that doesn't match /api will serve the React app
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public', 'index.html'), (err) => {
    if (err) {
      // If we are not in production or files are missing, just send a basic message
      res.status(200).send('ShopSmart Backend Service (Static files may not be available)');
    }
  });
});

module.exports = app;

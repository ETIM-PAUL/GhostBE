const express = require('express');
const router = express.Router();
const userRoutes = require('./userRoutes');

// Health check
router.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'API is running' });
});

// Mount route modules
router.use('/users', userRoutes);

module.exports = router;
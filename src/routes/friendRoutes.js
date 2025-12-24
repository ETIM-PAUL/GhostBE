const express = require('express');
const router = express.Router();
const friendController = require('../controllers/friendController');
const { validateRequest } = require('../middleware/validateRequest');

router.get('/get-user-friends', validateRequest, friendController.getUserFriends);
router.get('/get-pending-requests', validateRequest, friendController.getPendingRequests);
router.post('/cancel-request', validateRequest, friendController.cancelRequest);
router.put('/accept-request', validateRequest, friendController.acceptRequest);

module.exports = router;
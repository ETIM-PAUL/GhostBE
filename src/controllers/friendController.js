const friendService = require('../services/friendService');
const userService = require('../services/userService');
const logger = require('../utils/logger');

class FriendController {
  async getUserFriends(req, res, next) {
    try {
      const { verifiedSigner } = req.verifiedSigner;
      const users = await friendService.getUserFriends(verifiedSigner);
      res.json({ success: true, data: users });
    } catch (error) {
      next(error);
    }
  }

  async getPendingRequests(req, res, next) {
    try {
      const { verifiedSigner } = req.verifiedSigner;
      const requests = await friendService.getPendingRequests(verifiedSigner);
      
      if (!requests) {
        return res.status(404).json({ 
          success: false, 
          error: 'No pending requests not found' 
        });
      }
      
      res.json({ success: true, data: requests });
    } catch (error) {
      next(error);
    }
  }

  async cancelRequest(req, res, next) {
    try {
      const verifiedSigner = req.verifiedSigner;
      const { signature, message } = req.body;
      const cancelled = await friendService.cancelRequest(verifiedSigner, signature, message);
      
      if (!cancelled) {
        return res.status(404).json({ 
          success: false, 
          error: 'Request not found' 
        });
      }
      
      res.json({ 
        success: true, 
        message: 'Friend request cancelled successfully'
      });
    } catch (error) {
      if (error.message === 'Mismatch Payload') {
        return res.status(400).json({ 
          success: false, 
          error: 'Mismatch Payload' 
        });
      }
      next(error);
    }
  }

  async acceptRequest(req, res, next) {
    try {
      const { id } = req.params;
      const { name, email } = req.body;
      const user = await userService.updateUser(id, name, email);
      
      if (!user) {
        return res.status(404).json({ 
          success: false, 
          error: 'User not found' 
        });
      }
      
      res.json({ 
        success: true, 
        data: user,
        message: 'User updated successfully'
      });
    } catch (error) {
      next(error);
    }
  }

  async removeFriend(req, res, next) {
    try {
      const { id } = req.params;
      const deleted = await userService.deleteUser(id);
      
      if (!deleted) {
        return res.status(404).json({ 
          success: false, 
          error: 'User not found' 
        });
      }
      
      res.json({ 
        success: true, 
        message: 'User deleted successfully' 
      });
    } catch (error) {
      next(error);
    }
  }
}

module.exports = new FriendController();
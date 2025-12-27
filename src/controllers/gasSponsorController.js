const gasSponsor = require('../services/gasSponsor');

class GasSponsorController {
  async sponsorGasTransaction(req, res, next) {
    try {
      const { transaction, senderAuth } = req.body;
      const pendingTransaction = await gasSponsor.sponsorTransaction(transaction, senderAuth);
      if (pendingTransaction) {
        res.json({ 
          success: true, 
          data: pendingTransaction,
          message: 'Transaction submitted successfully'
        });
      }

    } catch (error) {
      next(error);
    }
  }
}

module.exports = new GasSponsorController();
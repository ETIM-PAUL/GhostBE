const supabase = require('../config/database');
import {
    GasStationClient
  } from "@shinami/clients/aptos";

  import {
    AccountAddress,
    AccountAuthenticator,
    Aptos,
    AptosConfig,
    SimpleTransaction,
    Deserializer,
    Hex,
    MoveString,
    Network
  } from "@aptos-labs/ts-sdk";

  let gasSponsorStation = null;

  const getGasStationClient = async () => {
    if (!gasClient) {
      const { GasStationClient } = await import("@shinami/clients/aptos");
      let GAS_STATION_AND_WALLET_TESTNET_BE_KEY = process.env.GAS_STATION_AND_WALLET_TESTNET_BE_KEY;
      gasSponsorStation = new GasStationClient(GAS_STATION_AND_WALLET_TESTNET_BE_KEY);
    }
    return gasSponsorStation;
  };

  class GasSponsorService {
      
  async sponsorTransaction(transaction, senderAuth) { 
    const gasSponsorClient = await getGasStationClient();
      try {
          // Step 1: Sponsor and submit the transaction
          // First, deserialize the SimpleTransaction and sender AccountAuthenticator sent from the FE
          const simpleTx = SimpleTransaction.deserialize(new Deserializer(Hex.fromHexString(transaction).toUint8Array()));
          const senderSig = AccountAuthenticator.deserialize(new Deserializer(Hex.fromHexString(senderAuth).toUint8Array()));
          const pendingTransaction = await gasSponsorClient.sponsorAndSubmitSignedTransaction(simpleTx, senderSig);
      
          // Step 2: Send the PendingTransactionResponse back to the FE
          return pendingTransaction
      } catch (err) {
          next(err);
      }
  }  
  }

module.exports = new GasSponsorService();
const supabase = require('../config/database');
const { ethers } = require('ethers');

class FriendService {
  async getUserFriends(signer) {
    const { data: signerUser, error: signerErr } = await supabase
      .from('users')
      .select('id, wallet_address')
      .eq('wallet_address', signer)
      .single();

    if (signerErr) {
      if (signerErr.code === 'PGRST116') {
        throw new Error('Mismatch Payload'); // no matching user
      }
      throw signerErr;
    }

    const { data, error } = await supabase
    .from('friend_requests')
    .select('to_user_id')
    .eq('from_user_id', signerUser.id)
    .eq('status', "accepted");

    if (error) throw error;
    return data;
  }

  async getPendingRequests(signer) {
    const { data: signerUser, error: signerErr } = await supabase
      .from('users')
      .select('id, wallet_address, to_user_id')
      .eq('wallet_address', signer)
      .single();

    if (signerErr) {
      if (signerErr.code === 'PGRST116') {
        throw new Error('Mismatch Payload'); // no matching user
      }
      throw signerErr;
    }
    
    const { data, error } = await supabase
    .from('friend_requests')
    .select('to_user_id')
    .eq('from_user_id', signerUser.id)
    .eq('status', "pending");

    if (error) throw error;
    return data;
  }
  
  async cancelRequestOrRemoveFriend(signer, signature, message) {
    // Decode and parse the stringified JSON message
    let decodedFriendRequestId;
    try {
      // Parse the stringified JSON message to extract to_user_id
      const parsedMessage = JSON.parse(message);
      decodedFriendRequestId = parsedMessage.id;
      
      if (!decodedFriendRequestId) {
        throw new Error('Provide friend request id');
      }
    } catch (error) {
      if (error.message === 'Mismatch Payload') {
        throw error;
      }
      throw new Error('Mismatch Payload');
    }

    // 4. Delete the record
    const { error: deleteError } = await supabase
      .from('friend_requests')
      .delete()
      .eq('id', decodedFriendRequestId);

    if (deleteError) throw deleteError;

    return true;
  }
  
  async acceptFriendRequest(signer, signature, message) {
    // Decode and parse the stringified JSON message
    let decodedFriendRequestId;
    try {
      // Parse the stringified JSON message to extract to_user_id
      const parsedMessage = JSON.parse(message);
      decodedFriendRequestId = parsedMessage.id;
      
      if (!decodedFriendRequestId) {
        throw new Error('Provide friend request id');
      }
    } catch (error) {
      if (error.message === 'Mismatch Payload') {
        throw error;
      }
      throw new Error('Mismatch Payload');
    }

    // 4. Delete the record
    const { error: updateError } = await supabase
      .from('friend_requests')
      .update({ status: 'accepted' })
      .eq('id', decodedFriendRequestId);

    if (updateError) throw updateError;

    return true;
  }
}

module.exports = new FriendService();
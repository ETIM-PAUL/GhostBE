const supabase = require('../config/database');

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
    .eq('status', "pending");

    if (error) throw error;
    return data;
  }
}

module.exports = new FriendService();
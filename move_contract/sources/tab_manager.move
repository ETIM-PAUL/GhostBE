module tab_manager::tab_manager {
    use std::string::String;
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::event;

    // USDC coin type for Movement testnet (update this address after deployment)
    // This should be the USDC token address on Movement testnet
    struct USDC {}

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_INVALID_PERIOD: u64 = 2;
    const E_TAB_NOT_FOUND: u64 = 3;
    const E_MEMBER_NOT_FOUND: u64 = 4;
    const E_INVALID_AMOUNT: u64 = 5;
    const E_ALREADY_SETTLED: u64 = 6;
    const E_NOT_MEMBER: u64 = 7;
    const E_DUPLICATE_WALLET: u64 = 8;
    const E_INSUFFICIENT_BALANCE: u64 = 9;
    const E_NOT_FOUND: u64 = 10;
    const E_AMOUNT_MISMATCH: u64 = 11;

    // Constants
    const MIN_PERIOD_SECONDS: u64 = 259200; // 3 days
    const MAX_PERIOD_SECONDS: u64 = 2592000; // 30 days
    const STATUS_OPENED: vector<u8> = b"opened";
    const STATUS_CLOSED: vector<u8> = b"closed";
    const STATUS_SETTLED: vector<u8> = b"settled";
    const STATUS_PENDING: vector<u8> = b"pending";

    // Structs
    struct TabMember has store, drop, copy {
        payee_privy_id: String,
        payee_wallet: address,
        tab_amount: u64,
        status: String,
        confirmed_at: String,
    }

    struct Tab has store, drop, copy {
        id: u64,
        name: String,
        amount_spent: u64,
        created_by: address,
        settler_wallet: address,
        group_id: String,
        status: String,
        created_at: u64,
        closed_at: u64,
        opened_period: u64,
        members: vector<TabMember>,
    }

    struct AutoSettlement has store, drop, copy {
        wallet: address,
        max_amount: u64,
        min_amount: u64,
        balance: u64,
        auto_settle: bool,
    }

    struct TabRegistry has key {
        tabs: vector<Tab>,
        next_tab_id: u64,
        authorized_creator: address,
        auto_settlements: vector<AutoSettlement>,
        usdc_coin_type: String, // Store USDC coin type address
    }

    // Events
    #[event]
    struct TabCreatedEvent has store, drop {
        tab_id: u64,
        name: String,
        created_by: address,
        settler_wallet: address,
        group_id: String,
        amount_spent: u64,
        created_at: u64,
    }

    #[event]
    struct TabMemberAddedEvent has store, drop {
        tab_id: u64,
        payee_wallet: address,
        payee_privy_id: String,
        tab_amount: u64,
    }

    #[event]
    struct TabSettledEvent has store, drop {
        tab_id: u64,
        payee_wallet: address,
        settler_wallet: address,
        amount: u64,
        is_auto: bool,
        settled_at: u64,
    }

    #[event]
    struct DepositEvent has store, drop {
        wallet: address,
        amount: u64,
        new_balance: u64,
    }

    // Initialize the contract
    public entry fun initialize(
        account: &signer, 
        authorized_creator: address,
        usdc_coin_type: String
    ) {
        let deployer = signer::address_of(account);
        
        if (!exists<TabRegistry>(deployer)) {
            move_to(account, TabRegistry {
                tabs: vector::empty(),
                next_tab_id: 1,
                authorized_creator,
                auto_settlements: vector::empty(),
                usdc_coin_type,
            });
        };
    }

    // Update authorized creator (only deployer can call)
    public entry fun update_authorized_creator(
        _account: &signer,
        registry_address: address,
        new_creator: address
    ) acquires TabRegistry {
        let registry = borrow_global_mut<TabRegistry>(registry_address);
        registry.authorized_creator = new_creator;
    }

    // Create a new tab
    public entry fun create_tab(
        account: &signer,
        registry_address: address,
        name: String,
        amount_spent: u64,
        settler_wallet: address,
        group_id: String,
        opened_period: u64,
        member_privy_ids: vector<String>,
        member_wallets: vector<address>,
        member_amounts: vector<u64>,
    ) acquires TabRegistry {
        let creator = signer::address_of(account);
        let registry = borrow_global_mut<TabRegistry>(registry_address);
        
        // Check authorization
        assert!(creator == registry.authorized_creator, E_NOT_AUTHORIZED);
        
        // Validate period
        assert!(opened_period >= MIN_PERIOD_SECONDS && opened_period <= MAX_PERIOD_SECONDS, E_INVALID_PERIOD);
        
        let tab_id = registry.next_tab_id;
        let current_time = timestamp::now_seconds();
        
        // Validate that all member amounts sum to amount_spent
        let total_member_amount = 0u64;
        let i = 0;
        let len = vector::length(&member_amounts);
        while (i < len) {
            total_member_amount = total_member_amount + *vector::borrow(&member_amounts, i);
            i = i + 1;
        };
        assert!(total_member_amount == amount_spent, E_AMOUNT_MISMATCH);
        
        // Check for duplicate wallets
        let i = 0;
        let len = vector::length(&member_wallets);
        while (i < len) {
            let wallet = *vector::borrow(&member_wallets, i);
            let j = i + 1;
            while (j < len) {
                assert!(wallet != *vector::borrow(&member_wallets, j), E_DUPLICATE_WALLET);
                j = j + 1;
            };
            i = i + 1;
        };
        
        // Create tab members and check auto settlement
        let members = vector::empty<TabMember>();
        let i = 0;
        while (i < len) {
            let payee_wallet = *vector::borrow(&member_wallets, i);
            let tab_amount = *vector::borrow(&member_amounts, i);
            let payee_privy_id = *vector::borrow(&member_privy_ids, i);
            
            let member = TabMember {
                payee_privy_id,
                payee_wallet,
                tab_amount,
                status: std::string::utf8(STATUS_PENDING),
                confirmed_at: std::string::utf8(b""),
            };
            
            // Check if auto settlement applies
            if (group_id != std::string::utf8(b"")) {
                let auto_settle_index = find_auto_settlement(&registry.auto_settlements, payee_wallet);
                if (auto_settle_index < vector::length(&registry.auto_settlements)) {
                    let auto_settlement = vector::borrow(&registry.auto_settlements, auto_settle_index);
                    if (auto_settlement.auto_settle && 
                        tab_amount >= auto_settlement.min_amount && 
                        tab_amount <= auto_settlement.max_amount &&
                        auto_settlement.balance >= tab_amount) {
                        
                        // Auto settle this member - transfer USDC
                        // Note: In a real implementation, you'd need to handle the USDC transfer here
                        // This requires the contract to hold USDC on behalf of users
                        
                        member.status = std::string::utf8(STATUS_SETTLED);
                        member.confirmed_at = u64_to_string(current_time);
                        
                        // Update auto settlement balance
                        let auto_settlement_mut = vector::borrow_mut(&mut registry.auto_settlements, auto_settle_index);
                        auto_settlement_mut.balance = auto_settlement_mut.balance - tab_amount;
                        
                        // Emit auto settlement event
                        event::emit(TabSettledEvent {
                            tab_id,
                            payee_wallet,
                            settler_wallet,
                            amount: tab_amount,
                            is_auto: true,
                            settled_at: current_time,
                        });
                    };
                };
            };
            
            vector::push_back(&mut members, member);
            
            // Emit member added event
            event::emit(TabMemberAddedEvent {
                tab_id,
                payee_wallet,
                payee_privy_id,
                tab_amount,
            });
            
            i = i + 1;
        };
        
        // Create tab
        let tab = Tab {
            id: tab_id,
            name,
            amount_spent,
            created_by: creator,
            settler_wallet,
            group_id,
            status: std::string::utf8(STATUS_OPENED),
            created_at: current_time,
            closed_at: 0,
            opened_period,
            members,
        };
        
        vector::push_back(&mut registry.tabs, tab);
        registry.next_tab_id = tab_id + 1;
        
        // Emit tab created event
        event::emit(TabCreatedEvent {
            tab_id,
            name,
            created_by: creator,
            settler_wallet,
            group_id,
            amount_spent,
            created_at: current_time,
        });
    }

    // Settle a tab member's payment with USDC
    public entry fun settle_tab<CoinType>(
        account: &signer,
        registry_address: address,
        tab_id: u64,
        amount: u64,
    ) acquires TabRegistry {
        let payer = signer::address_of(account);
        let registry = borrow_global_mut<TabRegistry>(registry_address);
        let current_time = timestamp::now_seconds();
        
        // Find the tab
        let tab_index = find_tab(&registry.tabs, tab_id);
        assert!(tab_index < vector::length(&registry.tabs), E_TAB_NOT_FOUND);
        
        let tab = vector::borrow_mut(&mut registry.tabs, tab_index);
        
        // Find the member
        let member_index = find_member(&tab.members, payer);
        assert!(member_index < vector::length(&tab.members), E_MEMBER_NOT_FOUND);
        
        let member = vector::borrow_mut(&mut tab.members, member_index);
        
        // Verify caller is the payee
        assert!(member.payee_wallet == payer, E_NOT_MEMBER);
        
        // Check if already settled
        assert!(member.status != std::string::utf8(STATUS_SETTLED), E_ALREADY_SETTLED);
        
        // Verify amount
        assert!(amount == member.tab_amount, E_INVALID_AMOUNT);
        
        // Transfer USDC from payer to settler
        coin::transfer<CoinType>(account, tab.settler_wallet, amount);

        // Update member
        member.status = std::string::utf8(STATUS_SETTLED);
        member.confirmed_at = u64_to_string(current_time);
        
        // Check if all members settled
        let all_settled = true;
        let i = 0;
        let len = vector::length(&tab.members);
        while (i < len) {
            let m = vector::borrow(&tab.members, i);
            if (m.status != std::string::utf8(STATUS_SETTLED)) {
                all_settled = false;
                break
            };
            i = i + 1;
        };
        
        // Update tab status if all settled
        if (all_settled) {
            tab.status = std::string::utf8(STATUS_CLOSED);
            tab.closed_at = current_time;
        };
        
        // Emit settlement event
        event::emit(TabSettledEvent {
            tab_id,
            payee_wallet: payer,
            settler_wallet: tab.settler_wallet,
            amount,
            is_auto: false,
            settled_at: current_time,
        });
    }

    // Add or update auto settlement configuration
    public entry fun configure_auto_settlement(
        account: &signer,
        registry_address: address,
        max_amount: u64,
        min_amount: u64,
        auto_settle: bool,
    ) acquires TabRegistry {
        let wallet = signer::address_of(account);
        let registry = borrow_global_mut<TabRegistry>(registry_address);
        
        let index = find_auto_settlement(&registry.auto_settlements, wallet);
        
        if (index < vector::length(&registry.auto_settlements)) {
            // Update existing
            let auto_settlement = vector::borrow_mut(&mut registry.auto_settlements, index);
            auto_settlement.max_amount = max_amount;
            auto_settlement.min_amount = min_amount;
            auto_settlement.auto_settle = auto_settle;
        } else {
            // Create new
            let auto_settlement = AutoSettlement {
                wallet,
                max_amount,
                min_amount,
                balance: 0,
                auto_settle,
            };
            vector::push_back(&mut registry.auto_settlements, auto_settlement);
        };
    }

    // Deposit USDC for auto settlement
    public entry fun deposit_for_auto_settlement<CoinType>(
        account: &signer,
        registry_address: address,
        amount: u64,
    ) acquires TabRegistry {
        let wallet = signer::address_of(account);
        let registry = borrow_global_mut<TabRegistry>(registry_address);
        
        // Transfer USDC to the registry address
        coin::transfer<CoinType>(account, registry_address, amount);
        
        let index = find_auto_settlement(&registry.auto_settlements, wallet);
        assert!(index < vector::length(&registry.auto_settlements), E_NOT_FOUND);
        
        let auto_settlement = vector::borrow_mut(&mut registry.auto_settlements, index);
        auto_settlement.balance = auto_settlement.balance + amount;
        
        // Emit deposit event
        event::emit(DepositEvent {
            wallet,
            amount,
            new_balance: auto_settlement.balance,
        });
    }

    // View functions
    #[view]
    public fun get_tabs_by_creator(registry_address: address, creator: address): vector<Tab> acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let result = vector::empty<Tab>();
        
        let i = 0;
        let len = vector::length(&registry.tabs);
        while (i < len) {
            let tab = vector::borrow(&registry.tabs, i);
            if (tab.created_by == creator) {
                vector::push_back(&mut result, *tab);
            };
            i = i + 1;
        };
        
        result
    }

    #[view]
    public fun get_tabs_by_member(registry_address: address, member_wallet: address): vector<Tab> acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let result = vector::empty<Tab>();
        
        let i = 0;
        let len = vector::length(&registry.tabs);
        while (i < len) {
            let tab = vector::borrow(&registry.tabs, i);
            let member_index = find_member(&tab.members, member_wallet);
            if (member_index < vector::length(&tab.members)) {
                vector::push_back(&mut result, *tab);
            };
            i = i + 1;
        };
        
        result
    }

    #[view]
    public fun get_tab_by_id(registry_address: address, tab_id: u64): Tab acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let index = find_tab(&registry.tabs, tab_id);
        assert!(index < vector::length(&registry.tabs), E_TAB_NOT_FOUND);
        *vector::borrow(&registry.tabs, index)
    }

    #[view]
    public fun get_auto_settlement(registry_address: address, wallet: address): AutoSettlement acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let index = find_auto_settlement(&registry.auto_settlements, wallet);
        assert!(index < vector::length(&registry.auto_settlements), E_NOT_FOUND);
        *vector::borrow(&registry.auto_settlements, index)
    }

   #[view]
    public fun get_tab_status_by_id(
        registry_address: address,
        tab_id: u64
    ): String acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let index = find_tab(&registry.tabs, tab_id);
        assert!(index < vector::length(&registry.tabs), E_TAB_NOT_FOUND);
        vector::borrow(&registry.tabs, index).status
    }

    #[view]
    public fun get_tab_amount_spent_by_id(
        registry_address: address,
        tab_id: u64
    ): u64 acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let index = find_tab(&registry.tabs, tab_id);
        assert!(index < vector::length(&registry.tabs), E_TAB_NOT_FOUND);
        vector::borrow(&registry.tabs, index).amount_spent
    }

    #[view]
    public fun get_tab_member_status(
        registry_address: address,
        tab_id: u64,
        member_wallet: address
    ): String acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let tab_index = find_tab(&registry.tabs, tab_id);
        assert!(tab_index < vector::length(&registry.tabs), E_TAB_NOT_FOUND);

        let tab = vector::borrow(&registry.tabs, tab_index);
        let member_index = find_member(&tab.members, member_wallet);
        assert!(member_index < vector::length(&tab.members), E_MEMBER_NOT_FOUND);

        vector::borrow(&tab.members, member_index).status
    }

    #[view]
    public fun get_auto_settlement_balance_by_wallet(
        registry_address: address,
        wallet: address
    ): u64 acquires TabRegistry {
        let registry = borrow_global<TabRegistry>(registry_address);
        let index = find_auto_settlement(&registry.auto_settlements, wallet);
        assert!(index < vector::length(&registry.auto_settlements), E_NOT_FOUND);
        vector::borrow(&registry.auto_settlements, index).balance
    }


    // Helper functions
    fun find_tab(tabs: &vector<Tab>, tab_id: u64): u64 {
        let i = 0;
        let len = vector::length(tabs);
        while (i < len) {
            let tab = vector::borrow(tabs, i);
            if (tab.id == tab_id) {
                return i
            };
            i = i + 1;
        };
        len
    }

    fun find_member(members: &vector<TabMember>, wallet: address): u64 {
        let i = 0;
        let len = vector::length(members);
        while (i < len) {
            let member = vector::borrow(members, i);
            if (member.payee_wallet == wallet) {
                return i
            };
            i = i + 1;
        };
        len
    }

    fun find_auto_settlement(auto_settlements: &vector<AutoSettlement>, wallet: address): u64 {
        let i = 0;
        let len = vector::length(auto_settlements);
        while (i < len) {
            let auto_settlement = vector::borrow(auto_settlements, i);
            if (auto_settlement.wallet == wallet) {
                return i
            };
            i = i + 1;
        };
        len
    }

    fun u64_to_string(value: u64): String {
        // Simple conversion - in production use a proper conversion library
        if (value == 0) {
            return std::string::utf8(b"0")
        };
        std::string::utf8(b"timestamp")
    }
}
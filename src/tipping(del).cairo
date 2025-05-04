#[starknet::contract]
mod Tipping {
    // Import necessary modules and traits
    use starknet::{ContractAddress, get_caller_address, contract_address_const};
    use zeroable::Zeroable;
    use starknet::contract_address_to_felt252;
    use traits::{Into, TryInto};
    use option::OptionTrait;
    use array::{ArrayTrait, SpanTrait};
    use integer::{u256_safe_divmod, u256_safe_sub, u256_eq};
    use super::interfaces::itipping::{ITipping, IERC20Dispatcher, IERC20DispatcherTrait, IERC20CamelDispatcher, IERC20CamelDispatcherTrait};

    // Storage variables
    #[storage]
    struct Storage {
        // Owner address
        owner: ContractAddress,
        // Default payment token address
        default_payment_token: ContractAddress,
        // Platform fee percentage (out of 10000)
        platform_fee: u256,
        // Platform fee recipient
        fee_recipient: ContractAddress,
        // Mapping of creator addresses to their total received tips
        creator_total_tips: LegacyMap<(ContractAddress, ContractAddress), u256>,
        // Mapping to track if a token is supported for tipping
        supported_tokens: LegacyMap<ContractAddress, bool>,
        // List of supported tokens
        supported_token_list: LegacyMap<u32, ContractAddress>,
        // Number of supported tokens
        supported_token_count: u32,
    }

    // Define events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TipSent: TipSent,
        TokenAdded: TokenAdded,
        TokenRemoved: TokenRemoved,
        FeeUpdated: FeeUpdated,
        FeeRecipientUpdated: FeeRecipientUpdated,
        OwnershipTransferred: OwnershipTransferred,
    }

    // Event structs
    #[derive(Drop, starknet::Event)]
    struct TipSent {
        sender: ContractAddress,
        recipient: ContractAddress,
        token: ContractAddress,
        amount: u256,
        platform_fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenAdded {
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct TokenRemoved {
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct FeeUpdated {
        old_fee: u256,
        new_fee: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct FeeRecipientUpdated {
        old_recipient: ContractAddress,
        new_recipient: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
    }

    // Constructor function
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        default_payment_token: ContractAddress,
        platform_fee: u256,
        fee_recipient: ContractAddress,
    ) {
        // Set initial values
        self.owner.write(owner);
        self.default_payment_token.write(default_payment_token);
        self.platform_fee.write(platform_fee);
        self.fee_recipient.write(fee_recipient);
        
        // Add default payment token to supported tokens
        self.supported_tokens.write(default_payment_token, true);
        self.supported_token_list.write(0, default_payment_token);
        self.supported_token_count.write(1);
    }

    // Contract interface implementation
    #[abi(embed_v0)]
    impl TippingImpl of ITipping<ContractState> {
        // Send a tip to a creator using the default token
        fn tip_creator(
            ref self: ContractState, 
            creator: ContractAddress, 
            amount: u256
        ) {
            // Get default token
            let token = self.default_payment_token.read();
            self._send_tip(creator, amount, token);
        }

        // Send a tip to a creator using a specific token
        fn tip_creator_with_token(
            ref self: ContractState, 
            creator: ContractAddress, 
            amount: u256, 
            token: ContractAddress
        ) {
            // Check if token is supported
            assert(self.supported_tokens.read(token), 'Token not supported');
            self._send_tip(creator, amount, token);
        }

        // Get total tips received by a creator for a specific token
        fn get_creator_tips(
            self: @ContractState,
            creator: ContractAddress,
            token: ContractAddress
        ) -> u256 {
            self.creator_total_tips.read((creator, token))
        }

        // Admin: Add a supported token
        fn add_supported_token(
            ref self: ContractState,
            token: ContractAddress
        ) {
            // Only owner can add tokens
            self._only_owner();
            
            // Check if token is not already supported
            assert(!self.supported_tokens.read(token), 'Token already supported');
            
            // Add token to supported tokens
            let count = self.supported_token_count.read();
            self.supported_tokens.write(token, true);
            self.supported_token_list.write(count, token);
            self.supported_token_count.write(count + 1);
            
            // Emit event
            self.emit(Event::TokenAdded(TokenAdded { token }));
        }

        // Admin: Remove a supported token
        fn remove_supported_token(
            ref self: ContractState,
            token: ContractAddress
        ) {
            // Only owner can remove tokens
            self._only_owner();
            
            // Check if token is supported
            assert(self.supported_tokens.read(token), 'Token not supported');
            
            // Cannot remove default token
            let default_token = self.default_payment_token.read();
            assert(token != default_token, 'Cannot remove default token');
            
            // Remove token from supported tokens
            self.supported_tokens.write(token, false);
            
            // Emit event
            self.emit(Event::TokenRemoved(TokenRemoved { token }));
            
            // Note: Not removing from the list to maintain list integrity
            // In a real implementation, we might want to reorganize the list
        }

        // Admin: Update platform fee
        fn update_platform_fee(
            ref self: ContractState,
            new_fee: u256
        ) {
            // Only owner can update fee
            self._only_owner();
            
            // Fee cannot be more than 20% (2000 out of 10000)
            assert(new_fee <= 2000_u256, 'Fee too high');
            
            let old_fee = self.platform_fee.read();
            self.platform_fee.write(new_fee);
            
            // Emit event
            self.emit(Event::FeeUpdated(FeeUpdated { old_fee, new_fee }));
        }

        // Admin: Update fee recipient
        fn update_fee_recipient(
            ref self: ContractState,
            new_recipient: ContractAddress
        ) {
            // Only owner can update fee recipient
            self._only_owner();
            
            // New recipient cannot be zero
            assert(!new_recipient.is_zero(), 'Invalid fee recipient');
            
            let old_recipient = self.fee_recipient.read();
            self.fee_recipient.write(new_recipient);
            
            // Emit event
            self.emit(Event::FeeRecipientUpdated(FeeRecipientUpdated { 
                old_recipient, 
                new_recipient 
            }));
        }

        // Admin: Transfer ownership
        fn transfer_ownership(
            ref self: ContractState,
            new_owner: ContractAddress
        ) {
            // Only owner can transfer ownership
            self._only_owner();
            
            // New owner cannot be zero
            assert(!new_owner.is_zero(), 'Invalid new owner');
            
            let previous_owner = self.owner.read();
            self.owner.write(new_owner);
            
            // Emit event
            self.emit(Event::OwnershipTransferred(OwnershipTransferred { 
                previous_owner, 
                new_owner 
            }));
        }

        // Getter: Get current owner
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        // Getter: Get default payment token
        fn get_default_payment_token(self: @ContractState) -> ContractAddress {
            self.default_payment_token.read()
        }

        // Getter: Get platform fee
        fn get_platform_fee(self: @ContractState) -> u256 {
            self.platform_fee.read()
        }

        // Getter: Get fee recipient
        fn get_fee_recipient(self: @ContractState) -> ContractAddress {
            self.fee_recipient.read()
        }

        // Getter: Check if token is supported
        fn is_token_supported(self: @ContractState, token: ContractAddress) -> bool {
            self.supported_tokens.read(token)
        }

        // Getter: Get list of supported tokens
        fn get_supported_tokens(self: @ContractState) -> Array<ContractAddress> {
            let count = self.supported_token_count.read();
            let mut result = ArrayTrait::new();
            
            let mut i: u32 = 0;
            while i < count {
                let token = self.supported_token_list.read(i);
                // Only include if still supported (not removed)
                if self.supported_tokens.read(token) {
                    result.append(token);
                }
                i += 1;
            }
            
            result
        }
    }

    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        // Check if caller is the owner
        fn _only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'Caller is not the owner');
        }

        // Try to transfer ERC20 tokens, attempting both standard and camel case interfaces
        fn _transfer_tokens(
            token: ContractAddress,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) -> bool {
            // First try standard interface
            let erc20 = IERC20Dispatcher { contract_address: token };
            
            // We need to handle potential errors when calling external contracts
            match erc20.transfer_from(sender, recipient, amount) {
                Result::Ok(success) => {
                    if success {
                        return true;
                    }
                },
                Result::Err(_) => {}
            }
            
            // If standard interface fails, try camel case interface
            let erc20_camel = IERC20CamelDispatcher { contract_address: token };
            
            match erc20_camel.transferFrom(sender, recipient, amount) {
                Result::Ok(success) => {
                    return success;
                },
                Result::Err(_) => {
                    return false;
                }
            }
        }

        // Send a tip to a creator
        fn _send_tip(
            ref self: ContractState,
            creator: ContractAddress,
            amount: u256,
            token: ContractAddress
        ) {
            // Check inputs
            assert(!creator.is_zero(), 'Invalid creator address');
            assert(amount > 0_u256, 'Amount must be greater than 0');
            
            // Get caller
            let caller = get_caller_address();
            
            // Calculate platform fee
            let platform_fee_percentage = self.platform_fee.read();
            let platform_fee_amount = (amount * platform_fee_percentage) / 10000_u256;
            let creator_amount = amount - platform_fee_amount;
            
            // Get fee recipient
            let fee_recipient = self.fee_recipient.read();
            
            // Transfer fee to fee recipient if fee is greater than 0
            if platform_fee_amount > 0_u256 {
                let success = self._transfer_tokens(token, caller, fee_recipient, platform_fee_amount);
                assert(success, 'Fee transfer failed');
            }
            
            // Transfer amount to creator
            let success = self._transfer_tokens(token, caller, creator, creator_amount);
            assert(success, 'Creator transfer failed');
            
            // Update creator total tips
            let current_tips = self.creator_total_tips.read((creator, token));
            self.creator_total_tips.write((creator, token), current_tips + creator_amount);
            
            // Emit tip event
            self.emit(Event::TipSent(TipSent { 
                sender: caller, 
                recipient: creator, 
                token, 
                amount: creator_amount, 
                platform_fee: platform_fee_amount 
            }));
        }
    }
}
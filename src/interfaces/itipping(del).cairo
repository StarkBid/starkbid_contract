use starknet::ContractAddress;
use array::Array;

#[starknet::interface]
trait ITipping<TContractState> {
    // Send a tip to a creator using the default token
    fn tip_creator(ref self: TContractState, creator: ContractAddress, amount: u256);
    
    // Send a tip to a creator using a specific token
    fn tip_creator_with_token(
        ref self: TContractState, 
        creator: ContractAddress, 
        amount: u256, 
        token: ContractAddress
    );
    
    // Get total tips received by a creator for a specific token
    fn get_creator_tips(
        self: @TContractState, 
        creator: ContractAddress, 
        token: ContractAddress
    ) -> u256;
    
    // Admin: Add a supported token
    fn add_supported_token(ref self: TContractState, token: ContractAddress);
    
    // Admin: Remove a supported token
    fn remove_supported_token(ref self: TContractState, token: ContractAddress);
    
    // Admin: Update platform fee
    fn update_platform_fee(ref self: TContractState, new_fee: u256);
    
    // Admin: Update fee recipient
    fn update_fee_recipient(ref self: TContractState, new_recipient: ContractAddress);
    
    // Admin: Transfer ownership
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    
    // Getter: Get current owner
    fn get_owner(self: @TContractState) -> ContractAddress;
    
    // Getter: Get default payment token
    fn get_default_payment_token(self: @TContractState) -> ContractAddress;
    
    // Getter: Get platform fee
    fn get_platform_fee(self: @TContractState) -> u256;
    
    // Getter: Get fee recipient
    fn get_fee_recipient(self: @TContractState) -> ContractAddress;
    
    // Getter: Check if token is supported
    fn is_token_supported(self: @TContractState, token: ContractAddress) -> bool;
    
    // Getter: Get list of supported tokens
    fn get_supported_tokens(self: @TContractState) -> Array<ContractAddress>;
}

// Interface for ERC20 token interaction
#[starknet::interface]
trait IERC20<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

// Camel case version of the ERC20 interface for compatibility with older tokens
#[starknet::interface]
trait IERC20Camel<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn decimals(self: @TContractState) -> u8;
    fn totalSupply(self: @TContractState) -> u256;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}
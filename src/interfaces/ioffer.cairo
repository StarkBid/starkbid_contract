use core::traits::TryInto;
use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store, PartialEq)]
pub enum OfferStatus {
    #[default]
    Active: (),
    Accepted: (),
    Cancelled: (),
    Expired: (),
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Offer {
    pub id: u256,
    pub nft_contract: ContractAddress,
    pub token_id: u256,
    pub offerer: ContractAddress,
    pub payment_token: ContractAddress,
    pub offer_amount: u256,
    pub expiration: u64,
    pub status: OfferStatus,
    pub royalty_recipient: ContractAddress,
    pub royalty_percentage: u256,
}


#[starknet::interface]
pub trait IOffer<TContractState> {
    // Create a new offer for an NFT
    fn create_offer(
        ref self: TContractState,
        nft_contract: ContractAddress,
        token_id: u256,
        payment_token: ContractAddress,
        offer_amount: u256,
        expiration: u64
    ) -> u256;

    // Accept an offer (NFT owner only)
    fn accept_offer(ref self: TContractState, offer_id: u256);

    // Cancel an offer (offerer only)
    fn cancel_offer(ref self: TContractState, offer_id: u256);

    // View functions
    fn get_offer(self: @TContractState, offer_id: u256) -> Offer;
    fn get_offer_status(self: @TContractState, offer_id: u256) -> OfferStatus;
    fn is_offer_active(self: @TContractState, offer_id: u256) -> bool;

    // Royalty management
    fn set_royalty_info(
        ref self: TContractState,
        nft_contract: ContractAddress,
        recipient: ContractAddress,
        percentage: u256
    );
    fn get_royalty_info(
        self: @TContractState, nft_contract: ContractAddress
    ) -> (ContractAddress, u256);

    // Access control
    fn grant_this_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn revoke_this_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn renounce_this_role(ref self: TContractState, role: felt252);
    fn has_this_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
    fn get_this_role_admin(self: @TContractState, role: felt252) -> felt252;
    fn get_this_role_member_count(self: @TContractState, role: felt252) -> u256;

    fn pause_offers(ref self: TContractState);
    fn unpause_offers(ref self: TContractState);
    fn are_offers_paused(self: @TContractState) -> bool;
}

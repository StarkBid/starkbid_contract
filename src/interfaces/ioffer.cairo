use starknet::ContractAddress;
use core::traits::TryInto;

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
    id: u256,
    nft_contract: ContractAddress,
    token_id: u256,
    offerer: ContractAddress,
    payment_token: ContractAddress, // Zero address for ETH/STRK
    offer_amount: u256,
    expiration: u64,
    status: OfferStatus,
    royalty_recipient: ContractAddress,
    royalty_percentage: u256, // Base points (e.g., 250 = 2.5%)
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
        self: @TContractState, 
        nft_contract: ContractAddress
    ) -> (ContractAddress, u256);
}

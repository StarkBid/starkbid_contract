use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
pub struct Listing {
    pub id: u256,
    pub seller: ContractAddress,
    pub asset_contract: ContractAddress,
    pub token_id: u256,
    pub price: u256,
    pub start_time: u64,
    pub end_time: u64,
    pub listing_type: ListingType,
    pub status: ListingStatus,
    pub highest_bidder: ContractAddress,
    pub highest_bid: u256,
}

#[derive(Drop, Copy, Serde, starknet::Store, PartialEq)]
pub enum ListingType {
    #[default]
    FixedPrice: (),
    Auction: (),
}

#[derive(Drop, Serde, starknet::Store, PartialEq)]
pub enum ListingStatus {
    #[default]
    Active: (),
    Sold: (),
    Cancelled: (),
}

#[starknet::interface]
pub trait IMarketplace<TContractState> {
    // Core listing operations
    fn create_listing(
        ref self: TContractState,
        asset_contract: ContractAddress,
        token_id: u256,
        price: u256,
        listing_type: ListingType,
        duration: u64,
    ) -> u256;
    fn purchase_listing(ref self: TContractState, listing_id: u256);
    fn cancel_listing(ref self: TContractState, listing_id: u256);
    fn update_listing_price(ref self: TContractState, listing_id: u256, new_price: u256);

    // Auction functionality
    fn place_bid(ref self: TContractState, listing_id: u256, bid_amount: u256);
    fn finalize_auction(ref self: TContractState, listing_id: u256);

    // Batch operations for gas optimization
    fn batch_create_listings(
        ref self: TContractState,
        asset_contracts: Array<ContractAddress>,
        token_ids: Array<u256>,
        prices: Array<u256>,
        listing_types: Array<ListingType>,
        durations: Array<u64>,
    ) -> Array<u256>;
    fn batch_cancel_listings(ref self: TContractState, listing_ids: Array<u256>);
    fn batch_finalize_auctions(ref self: TContractState, listing_ids: Array<u256>);

    //  view functions
    fn get_listing(self: @TContractState, listing_id: u256) -> Listing;
    fn get_listing_status(self: @TContractState, listing_id: u256) -> ListingStatus;
    fn is_listing_active(self: @TContractState, listing_id: u256) -> bool;

    fn pause_marketplace(ref self: TContractState);
    fn unpause_marketplace(ref self: TContractState);

    // Access control
    fn grant_this_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn revoke_this_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn renounce_this_role(ref self: TContractState, role: felt252);
    fn has_this_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
    fn get_this_role_admin(self: @TContractState, role: felt252) -> felt252;
    fn get_this_role_member_count(self: @TContractState, role: felt252) -> u256;
}


use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, stop_cheat_block_timestamp, stop_cheat_caller_address,
};
use starkbid_contract::interfaces::imarketplace::{
    IMarketplaceDispatcher, IMarketplaceDispatcherTrait, ListingStatus, ListingType,
};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};

// Helper to initialize contract
fn init_contract() -> IMarketplaceDispatcher {
    let contract_class = declare("Marketplace").unwrap().contract_class();
    let (contract_address, _) = contract_class.deploy(@array![]).unwrap();
    IMarketplaceDispatcher { contract_address }
}

// Helper addresses
fn seller() -> ContractAddress {
    contract_address_const::<12345>()
}

fn buyer() -> ContractAddress {
    contract_address_const::<67890>()
}

fn nft_contract() -> ContractAddress {
    contract_address_const::<54321>()
}

#[test]
fn test_create_listing() {
    let contract = init_contract();
    let token_id = 1_u256;
    let price = 1000_u256;
    let duration = 3600_u64; // 1 hour

    // Create listing as seller
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), token_id, price, ListingType::FixedPrice(()), duration);
    stop_cheat_caller_address(contract.contract_address);

    // Verify listing was created correctly
    let listing = contract.get_listing(listing_id);
    assert(listing.seller == seller(), 'Wrong seller');
    assert(listing.asset_contract == nft_contract(), 'Wrong contract');
    assert(listing.token_id == token_id, 'Wrong token ID');
    assert(listing.price == price, 'Wrong price');
    assert(listing.listing_type == ListingType::FixedPrice(()), 'Wrong listing type');
    assert(listing.status == ListingStatus::Active(()), 'Wrong status');
    assert(listing.id == listing_id, 'Wrong listing ID');
}

#[test]
fn test_purchase_listing() {
    let contract = init_contract();
    let token_id = 1_u256;
    let price = 1000_u256;
    let duration = 3600_u64;

    // Create listing as seller
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), token_id, price, ListingType::FixedPrice(()), duration);
    stop_cheat_caller_address(contract.contract_address);

    // Purchase as buyer
    start_cheat_caller_address(contract.contract_address, buyer());
    contract.purchase_listing(listing_id);
    stop_cheat_caller_address(contract.contract_address);

    // Verify purchase
    let listing = contract.get_listing(listing_id);
    assert(listing.status == ListingStatus::Sold(()), 'Not marked as sold');
}

#[test]
fn test_cancel_listing() {
    let contract = init_contract();
    let token_id = 1_u256;
    let price = 1000_u256;
    let duration = 3600_u64;

    // Create listing as seller
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), token_id, price, ListingType::FixedPrice(()), duration);

    // Cancel listing
    contract.cancel_listing(listing_id);
    stop_cheat_caller_address(contract.contract_address);

    // Verify cancellation
    let listing = contract.get_listing(listing_id);
    assert(listing.status == ListingStatus::Cancelled(()), 'Not cancelled');
}

#[test]
fn test_update_listing_price() {
    let contract = init_contract();
    let token_id = 1_u256;
    let price = 1000_u256;
    let new_price = 1500_u256;
    let duration = 3600_u64;

    // Create listing as seller
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), token_id, price, ListingType::FixedPrice(()), duration);

    // Update price
    contract.update_listing_price(listing_id, new_price);
    stop_cheat_caller_address(contract.contract_address);

    // Verify price update
    let listing = contract.get_listing(listing_id);
    assert(listing.price == new_price, 'Price not updated');
}

#[test]
fn test_place_bid() {
    let contract = init_contract();
    let token_id = 1_u256;
    let starting_price = 1000_u256;
    let bid_amount = 1200_u256;
    let duration = 3600_u64;

    // Create auction listing
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(
            nft_contract(), token_id, starting_price, ListingType::Auction(()), duration,
        );
    stop_cheat_caller_address(contract.contract_address);

    // Place bid as buyer
    start_cheat_caller_address(contract.contract_address, buyer());
    contract.place_bid(listing_id, bid_amount);
    stop_cheat_caller_address(contract.contract_address);

    // Verify bid
    let listing = contract.get_listing(listing_id);
    assert(listing.highest_bidder == buyer(), 'Wrong bidder');
    assert(listing.highest_bid == bid_amount, 'Wrong bid amount');
}

#[test]
fn test_finalize_auction() {
    let contract = init_contract();
    let token_id = 1_u256;
    let starting_price = 1000_u256;
    let bid_amount = 1200_u256;
    let duration = 3600_u64; // 1 hour duration

    // Get current timestamp to calculate future times
    let start_time = get_block_timestamp();
    let end_time = start_time + duration;

    // Create auction listing
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(
            nft_contract(), token_id, starting_price, ListingType::Auction(()), duration,
        );
    stop_cheat_caller_address(contract.contract_address);

    // Place bid as buyer
    start_cheat_caller_address(contract.contract_address, buyer());
    contract.place_bid(listing_id, bid_amount);
    stop_cheat_caller_address(contract.contract_address);

    // Verify listing is active and has correct bid
    let listing = contract.get_listing(listing_id);
    assert(listing.highest_bidder == buyer(), 'Wrong bidder');
    assert(listing.highest_bid == bid_amount, 'Wrong bid amount');
    assert(listing.status == ListingStatus::Active(()), 'Should be active');

    // Advance time past the auction end time
    start_cheat_block_timestamp(contract.contract_address, end_time + 1);

    // Finalize auction
    contract.finalize_auction(listing_id);
    stop_cheat_block_timestamp(contract.contract_address);

    // Verify auction finalized
    let updated_listing = contract.get_listing(listing_id);
    assert(updated_listing.status == ListingStatus::Sold(()), 'Auction not finalized');
    assert(updated_listing.highest_bidder == buyer(), 'Winner is wrong');
}

#[test]
fn test_batch_create_listings() {
    let contract = init_contract();
    let mut asset_contracts = ArrayTrait::new();
    let mut token_ids = ArrayTrait::new();
    let mut prices = ArrayTrait::new();
    let mut listing_types = ArrayTrait::new();
    let mut durations = ArrayTrait::new();

    // Prepare batch data (2 listings)
    asset_contracts.append(nft_contract());
    asset_contracts.append(nft_contract());

    token_ids.append(1_u256);
    token_ids.append(2_u256);

    prices.append(1000_u256);
    prices.append(2000_u256);

    listing_types.append(ListingType::FixedPrice(()));
    listing_types.append(ListingType::Auction(()));

    durations.append(3600_u64);
    durations.append(7200_u64);

    // Create batch listings
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_ids = contract
        .batch_create_listings(asset_contracts, token_ids, prices, listing_types, durations);
    stop_cheat_caller_address(contract.contract_address);

    // Verify listings were created
    assert(listing_ids.len() == 2_u32, 'Wrong number of listings');

    let listing1 = contract.get_listing(*listing_ids.at(0));
    let listing2 = contract.get_listing(*listing_ids.at(1));

    assert(listing1.token_id == 1_u256, 'Wrong token ID for listing 1');
    assert(listing2.token_id == 2_u256, 'Wrong token ID for listing 2');
}

#[test]
fn test_is_listing_active() {
    let contract = init_contract();
    let token_id = 1_u256;
    let price = 1000_u256;
    let duration = 3600_u64;

    // Create listing
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), token_id, price, ListingType::FixedPrice(()), duration);
    stop_cheat_caller_address(contract.contract_address);

    // Check active status
    assert(contract.is_listing_active(listing_id), 'Should be active');

    // Cancel listing
    start_cheat_caller_address(contract.contract_address, seller());
    contract.cancel_listing(listing_id);
    stop_cheat_caller_address(contract.contract_address);

    // Check inactive status
    assert(!contract.is_listing_active(listing_id), 'Should be inactive');
}

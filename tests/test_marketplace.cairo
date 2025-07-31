use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, stop_cheat_block_timestamp, stop_cheat_caller_address,
};
use starkbid_contract::constants::{DEFAULT_ADMIN_ROLE, MARKETPLACE_ADMIN_ROLE, PAUSER_ROLE};
use starkbid_contract::interfaces::imarketplace::{
    IMarketplaceDispatcher, IMarketplaceDispatcherTrait, ListingStatus, ListingType,
};
use starknet::{ContractAddress, contract_address_const, get_block_timestamp};

// Helper to initialize contract
fn init_contract() -> IMarketplaceDispatcher {
    let contract_class = declare("Marketplace").unwrap().contract_class();
    let mut constructor_args: Array<felt252> = array![];
    admin_address().serialize(ref constructor_args);
    let (contract_address, _) = contract_class.deploy(@constructor_args).unwrap();
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

fn admin_address() -> ContractAddress {
    contract_address_const::<99999>()
}

fn marketplace_admin() -> ContractAddress {
    contract_address_const::<11111>()
}

fn pauser() -> ContractAddress {
    contract_address_const::<22222>()
}

fn unauthorized_user() -> ContractAddress {
    contract_address_const::<33333>()
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

#[test]
fn test_initial_admin_roles() {
    let contract = init_contract();

    // Verify admin has both DEFAULT_ADMIN_ROLE and MARKETPLACE_ADMIN_ROLE
    assert(
        contract.has_this_role(DEFAULT_ADMIN_ROLE, admin_address()), 'Admin missing default role'
    );
    assert(
        contract.has_this_role(MARKETPLACE_ADMIN_ROLE, admin_address()),
        'Admin missing marketplace role'
    );

    // Verify role member count
    assert(contract.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 1, 'Wrong admin count');
    assert(
        contract.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 1,
        'Wrong marketplace admin count'
    );
}

#[test]
fn test_role_hierarchy() {
    let contract = init_contract();

    // Verify role hierarchy - DEFAULT_ADMIN_ROLE should be admin of other roles
    assert(
        contract.get_this_role_admin(MARKETPLACE_ADMIN_ROLE) == DEFAULT_ADMIN_ROLE,
        'Wrong marketplace admin role'
    );
    assert(
        contract.get_this_role_admin(PAUSER_ROLE) == DEFAULT_ADMIN_ROLE, 'Wrong pauser admin role'
    );
}

#[test]
fn test_grant_role() {
    let contract = init_contract();

    // Grant MARKETPLACE_ADMIN_ROLE to marketplace_admin
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin());
    stop_cheat_caller_address(contract.contract_address);

    // Verify role was granted
    assert(contract.has_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin()), 'Role not granted');
    assert(contract.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 2, 'Wrong member count');
}

#[test]
fn test_grant_pauser_role() {
    let contract = init_contract();

    // Grant PAUSER_ROLE to pauser address
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, pauser());
    stop_cheat_caller_address(contract.contract_address);

    // Verify role was granted
    assert(contract.has_this_role(PAUSER_ROLE, pauser()), 'Pauser role not granted');
    assert(contract.get_this_role_member_count(PAUSER_ROLE) == 1, 'Wrong pauser count');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_grant_role_unauthorized() {
    let contract = init_contract();

    // Try to grant role as unauthorized user
    start_cheat_caller_address(contract.contract_address, unauthorized_user());
    contract.grant_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin());
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
fn test_revoke_role() {
    let contract = init_contract();

    // First grant a role
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin());

    // Verify granted
    assert(
        contract.has_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin()),
        'Role not granted initially'
    );
    assert(contract.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 2, 'Wrong initial count');

    // Revoke the role
    contract.revoke_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin());
    stop_cheat_caller_address(contract.contract_address);

    // Verify revoked
    assert(
        !contract.has_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin()), 'Role not revoked'
    );
    assert(contract.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 1, 'Wrong final count');
}

#[test]
#[should_panic(expected: ('Cannot remove last admin',))]
fn test_revoke_last_admin_protection() {
    let contract = init_contract();

    // Try to revoke the last admin role
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.revoke_this_role(DEFAULT_ADMIN_ROLE, admin_address());
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
fn test_renounce_role() {
    let contract = init_contract();

    // First grant a role to marketplace_admin
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin());
    stop_cheat_caller_address(contract.contract_address);

    // Verify granted
    assert(contract.has_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin()), 'Role not granted');

    // Renounce the role as marketplace_admin
    start_cheat_caller_address(contract.contract_address, marketplace_admin());
    contract.renounce_this_role(MARKETPLACE_ADMIN_ROLE);
    stop_cheat_caller_address(contract.contract_address);

    // Verify renounced
    assert(
        !contract.has_this_role(MARKETPLACE_ADMIN_ROLE, marketplace_admin()), 'Role not renounced'
    );
}

#[test]
#[should_panic(expected: ('Cannot remove last admin',))]
fn test_renounce_last_admin_protection() {
    let contract = init_contract();

    // Try to renounce the last admin role
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.renounce_this_role(DEFAULT_ADMIN_ROLE);
    stop_cheat_caller_address(contract.contract_address);
}

////
///  PAUSE/UNPAUSE FUNCTIONALITY TESTS
///

#[test]
#[should_panic(expected: ('Marketplace paused',))]
fn test_pause_marketplace() {
    let contract = init_contract();

    // Grant PAUSER_ROLE to pauser
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, pauser());
    stop_cheat_caller_address(contract.contract_address);

    // Pause marketplace as pauser
    start_cheat_caller_address(contract.contract_address, pauser());
    contract.pause_marketplace();
    stop_cheat_caller_address(contract.contract_address);

    // Try to create listing - should fail
    start_cheat_caller_address(contract.contract_address, seller());
    contract
        .create_listing(nft_contract(), 1_u256, 1000_u256, ListingType::FixedPrice(()), 3600_u64);
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_pause_marketplace_unauthorized() {
    let contract = init_contract();

    // Try to pause as unauthorized user
    start_cheat_caller_address(contract.contract_address, unauthorized_user());
    contract.pause_marketplace();
    stop_cheat_caller_address(contract.contract_address);
}

#[test]
fn test_unpause_marketplace() {
    let contract = init_contract();

    // Grant PAUSER_ROLE to pauser
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, pauser());
    stop_cheat_caller_address(contract.contract_address);

    // Pause marketplace
    start_cheat_caller_address(contract.contract_address, pauser());
    contract.pause_marketplace();

    // Unpause marketplace
    contract.unpause_marketplace();
    stop_cheat_caller_address(contract.contract_address);

    // Now create listing should work
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), 1_u256, 1000_u256, ListingType::FixedPrice(()), 3600_u64);
    stop_cheat_caller_address(contract.contract_address);

    // Verify listing was created successfully
    let listing = contract.get_listing(listing_id);
    assert(listing.status == ListingStatus::Active(()), 'Listing should be active');
}

#[test]
#[should_panic(expected: ('Marketplace paused',))]
fn test_purchase_listing_when_paused() {
    let contract = init_contract();

    // Create a listing first
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), 1_u256, 1000_u256, ListingType::FixedPrice(()), 3600_u64);
    stop_cheat_caller_address(contract.contract_address);

    // Grant PAUSER_ROLE and pause marketplace
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, pauser());
    stop_cheat_caller_address(contract.contract_address);

    start_cheat_caller_address(contract.contract_address, pauser());
    contract.pause_marketplace();
    stop_cheat_caller_address(contract.contract_address);

    // Try to purchase - should fail
    start_cheat_caller_address(contract.contract_address, buyer());
    contract.purchase_listing(listing_id);
    stop_cheat_caller_address(contract.contract_address);
}

///
///  MULTIPLE ADMIN MANAGEMENT TESTS
///

#[test]
fn test_multiple_admins() {
    let contract = init_contract();
    let second_admin = contract_address_const::<77777>();

    // Grant DEFAULT_ADMIN_ROLE to second admin
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(DEFAULT_ADMIN_ROLE, second_admin);
    stop_cheat_caller_address(contract.contract_address);

    // Verify both admins exist
    assert(contract.has_this_role(DEFAULT_ADMIN_ROLE, admin_address()), 'First admin missing');
    assert(contract.has_this_role(DEFAULT_ADMIN_ROLE, second_admin), 'Second admin missing');
    assert(contract.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 2, 'Wrong admin count');

    // Second admin should be able to grant roles
    start_cheat_caller_address(contract.contract_address, second_admin);
    contract.grant_this_role(PAUSER_ROLE, pauser());
    stop_cheat_caller_address(contract.contract_address);

    // Verify role was granted by second admin
    assert!(contract.has_this_role(PAUSER_ROLE, pauser()), "Role not granted by second admin");
}

#[test]
fn test_remove_one_of_multiple_admins() {
    let contract = init_contract();
    let second_admin = contract_address_const::<77777>();

    // Add second admin
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(DEFAULT_ADMIN_ROLE, second_admin);

    // Now remove first admin (should work since there's still another admin)
    contract.revoke_this_role(DEFAULT_ADMIN_ROLE, admin_address());
    stop_cheat_caller_address(contract.contract_address);

    // Verify first admin removed but second admin remains
    assert(!contract.has_this_role(DEFAULT_ADMIN_ROLE, admin_address()), 'First admin not removed');
    assert(contract.has_this_role(DEFAULT_ADMIN_ROLE, second_admin), 'Second admin missing');
    assert(contract.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 1, 'Wrong admin count');
}

///
///  ROLE MEMBER TRACKING TESTS
///

#[test]
fn test_role_member_count_tracking() {
    let contract = init_contract();

    // Initially should have 1 admin
    assert(
        contract.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 1, 'Wrong initial admin count'
    );
    assert(contract.get_this_role_member_count(PAUSER_ROLE) == 0, 'Wrong initial pauser count');

    // Add multiple pausers
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, pauser());
    contract.grant_this_role(PAUSER_ROLE, buyer());
    contract.grant_this_role(PAUSER_ROLE, seller());
    stop_cheat_caller_address(contract.contract_address);

    // Verify counts
    assert(
        contract.get_this_role_member_count(PAUSER_ROLE) == 3, 'Wrong pauser count after grants'
    );

    // Remove one pauser
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.revoke_this_role(PAUSER_ROLE, buyer());
    stop_cheat_caller_address(contract.contract_address);

    // Verify count decreased
    assert(
        contract.get_this_role_member_count(PAUSER_ROLE) == 2, 'Wrong pauser count after revoke'
    );
}

#[test]
fn test_duplicate_role_prevention() {
    let contract = init_contract();

    // Grant role to same user twice
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, pauser());
    contract.grant_this_role(PAUSER_ROLE, pauser()); // Duplicate
    stop_cheat_caller_address(contract.contract_address);

    // Should still only count as 1
    assert(contract.get_this_role_member_count(PAUSER_ROLE) == 1, 'Duplicate role granted');
    assert!(contract.has_this_role(PAUSER_ROLE, pauser()), "Role missing after duplicate grant");
}

///
///  INTEGRATION TESTS
///

#[test]
#[should_panic]
fn test_normal_marketplace_operations_with_rbac() {
    let contract = init_contract();

    // Grant PAUSER_ROLE to pauser
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, pauser());
    stop_cheat_caller_address(contract.contract_address);

    // Normal marketplace operations should still work
    start_cheat_caller_address(contract.contract_address, seller());
    let listing_id = contract
        .create_listing(nft_contract(), 1_u256, 1000_u256, ListingType::FixedPrice(()), 3600_u64);
    stop_cheat_caller_address(contract.contract_address);

    // Purchase should work
    start_cheat_caller_address(contract.contract_address, buyer());
    contract.purchase_listing(listing_id);
    stop_cheat_caller_address(contract.contract_address);

    // Verify purchase
    let listing = contract.get_listing(listing_id);
    assert(listing.status == ListingStatus::Sold(()), 'Purchase failed');

    // Pauser should be able to pause
    start_cheat_caller_address(contract.contract_address, pauser());
    contract.pause_marketplace();
    stop_cheat_caller_address(contract.contract_address);

    // New listings should fail when paused
    start_cheat_caller_address(contract.contract_address, seller());

    contract
        .create_listing(nft_contract(), 2_u256, 2000_u256, ListingType::FixedPrice(()), 3600_u64);
    stop_cheat_caller_address(contract.contract_address);
}


#[test]
#[should_panic(expected: ('account is zero address',))]
fn test_role_operations_zero_address() {
    let contract = init_contract();

    // Granting role to zero address
    let zero_address = contract_address_const::<0>();
    start_cheat_caller_address(contract.contract_address, admin_address());
    contract.grant_this_role(PAUSER_ROLE, zero_address);
    stop_cheat_caller_address(contract.contract_address);
}

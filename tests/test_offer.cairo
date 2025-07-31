use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp
};
use starkbid_contract::constants::{DEFAULT_ADMIN_ROLE, MARKETPLACE_ADMIN_ROLE, PAUSER_ROLE};

use starkbid_contract::interfaces::ioffer::{IOfferDispatcher, IOfferDispatcherTrait, OfferStatus};
use starknet::ContractAddress;

fn ADMIN() -> ContractAddress {
    'admin'.try_into().unwrap()
}

fn USER1() -> ContractAddress {
    0x111.try_into().unwrap()
}

fn USER2() -> ContractAddress {
    0x222.try_into().unwrap()
}

fn PAUSER() -> ContractAddress {
    0x333.try_into().unwrap()
}

fn UNAUTHORIZED_USER() -> ContractAddress {
    0x444.try_into().unwrap()
}

// Helper to initialize contract
fn deploy_contract() -> IOfferDispatcher {
    let contract = declare("Offer").unwrap().contract_class();
    let mut calldata = array![];
    ADMIN().serialize(ref calldata);
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    IOfferDispatcher { contract_address }
}

fn get_contract_addresses() -> (ContractAddress, ContractAddress, ContractAddress) {
    (
        0x123.try_into().unwrap(), // NFT contract
        0x456.try_into().unwrap(), // Payment token (ERC20)
        0x789.try_into().unwrap() // Royalty recipient
    )
}

fn test_create_offer() {
    let offer_contract = deploy_contract();
    let (nft_contract, payment_token, _) = get_contract_addresses();
    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600; // 1 hour from now

    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    let offer_id = offer_contract
        .create_offer(nft_contract, token_id, payment_token, offer_amount, expiration);

    let offer = offer_contract.get_offer(offer_id);
    assert(offer.token_id == token_id, 'Wrong token ID');
    assert(offer.offer_amount == offer_amount, 'Wrong amount');
    assert(offer.status == OfferStatus::Active(()), 'Wrong status');

    stop_cheat_block_timestamp(offer_contract.contract_address);
}

fn test_accept_offer() {
    let offer_contract = deploy_contract();
    let (nft_contract, payment_token, royalty_recipient) = get_contract_addresses();
    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600;

    // Set royalty info (2.5%)
    offer_contract.set_royalty_info(nft_contract, royalty_recipient, 250.into());

    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    // Create offer
    let offer_id = offer_contract
        .create_offer(nft_contract, token_id, payment_token, offer_amount, expiration);

    // Accept offer
    let seller = starknet::contract_address_const::<0x999>();
    start_cheat_caller_address(offer_contract.contract_address, seller);
    offer_contract.accept_offer(offer_id);
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify offer status
    let offer = offer_contract.get_offer(offer_id);
    assert(offer.status == OfferStatus::Accepted(()), 'Wrong status');

    stop_cheat_block_timestamp(offer_contract.contract_address);
}

fn test_cancel_offer() {
    let offer_contract = deploy_contract();
    let (nft_contract, payment_token, _) = get_contract_addresses();
    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600;

    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    // Create and immediately cancel offer
    let buyer = starknet::contract_address_const::<0x888>();
    start_cheat_caller_address(offer_contract.contract_address, buyer);

    let offer_id = offer_contract
        .create_offer(nft_contract, token_id, payment_token, offer_amount, expiration);

    offer_contract.cancel_offer(offer_id);
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify cancellation
    let offer = offer_contract.get_offer(offer_id);
    assert(offer.status == OfferStatus::Cancelled(()), 'Wrong status');

    stop_cheat_block_timestamp(offer_contract.contract_address);
}

fn test_expired_offer() {
    let offer_contract = deploy_contract();
    let (nft_contract, payment_token, _) = get_contract_addresses();
    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600;

    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    // Create offer
    let offer_id = offer_contract
        .create_offer(nft_contract, token_id, payment_token, offer_amount, expiration);

    // Advance time past expiration
    start_cheat_block_timestamp(offer_contract.contract_address, expiration + 1);

    // Verify offer is not active
    assert(!offer_contract.is_offer_active(offer_id), 'Should be inactive');

    stop_cheat_block_timestamp(offer_contract.contract_address);
}

fn test_royalty_calculation() {
    let offer_contract = deploy_contract();
    let (nft_contract, payment_token, royalty_recipient) = get_contract_addresses();
    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600;

    // Set royalty (5%)
    offer_contract.set_royalty_info(nft_contract, royalty_recipient, 500.into());

    // Verify royalty info
    let (recipient, percentage) = offer_contract.get_royalty_info(nft_contract);
    assert(recipient == royalty_recipient, 'Wrong recipient');
    assert(percentage == 500.into(), 'Wrong percentage');
}

#[test]
fn test_initial_admin_roles() {
    let offer_contract = deploy_contract();

    // Verify admin has both DEFAULT_ADMIN_ROLE and MARKETPLACE_ADMIN_ROLE
    assert!(
        offer_contract.has_this_role(DEFAULT_ADMIN_ROLE, ADMIN()), "Admin missing default role"
    );
    assert!(
        offer_contract.has_this_role(MARKETPLACE_ADMIN_ROLE, ADMIN()),
        "admin missing marketplace role"
    );

    // Verify role member count
    assert(offer_contract.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 1, 'Wrong admin count');
    assert(
        offer_contract.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 1,
        'Wrong marketplace admin count'
    );
    assert(offer_contract.get_this_role_member_count(PAUSER_ROLE) == 0, 'Wrong pauser count');
}

#[test]
fn test_role_hierarchy() {
    let offer_contract = deploy_contract();

    // Verify role hierarchy - DEFAULT_ADMIN_ROLE should be admin of other roles
    assert(
        offer_contract.get_this_role_admin(MARKETPLACE_ADMIN_ROLE) == DEFAULT_ADMIN_ROLE,
        'Wrong marketplace admin role'
    );
    assert(
        offer_contract.get_this_role_admin(PAUSER_ROLE) == DEFAULT_ADMIN_ROLE,
        'Wrong pauser admin role'
    );
    assert(
        offer_contract.get_this_role_admin(DEFAULT_ADMIN_ROLE) == DEFAULT_ADMIN_ROLE,
        'Wrong default admin role'
    );
}

#[test]
fn test_grant_pauser_role() {
    let offer_contract = deploy_contract();

    // Grant PAUSER_ROLE
    start_cheat_caller_address(offer_contract.contract_address, ADMIN());
    offer_contract.grant_this_role(PAUSER_ROLE, PAUSER());
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify role was granted
    assert(offer_contract.has_this_role(PAUSER_ROLE, PAUSER()), 'Role not granted');
    assert(offer_contract.get_this_role_member_count(PAUSER_ROLE) == 1, 'Wrong member count');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_grant_role_unauthorized() {
    let offer_contract = deploy_contract();

    // Try to grant role as unauthorized user
    start_cheat_caller_address(offer_contract.contract_address, UNAUTHORIZED_USER());
    offer_contract.grant_this_role(PAUSER_ROLE, PAUSER());
    stop_cheat_caller_address(offer_contract.contract_address);
}

#[test]
fn test_set_royalty_info_requires_admin() {
    let offer_contract = deploy_contract();
    let (nft_contract, _, royalty_recipient) = get_contract_addresses();

    start_cheat_caller_address(offer_contract.contract_address, ADMIN());
    offer_contract.set_royalty_info(nft_contract, royalty_recipient, 500.into());
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify it was set
    let (recipient, percentage) = offer_contract.get_royalty_info(nft_contract);
    assert(recipient == royalty_recipient, 'Wrong recipient');
    assert(percentage == 500.into(), 'Wrong percentage');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_set_royalty_info_unauthorized() {
    let offer_contract = deploy_contract();
    let (nft_contract, _, royalty_recipient) = get_contract_addresses();

    // Try to set royalty info as unauthorized user
    start_cheat_caller_address(offer_contract.contract_address, UNAUTHORIZED_USER());
    offer_contract.set_royalty_info(nft_contract, royalty_recipient, 500.into());
    stop_cheat_caller_address(offer_contract.contract_address);
}

#[test]
fn test_pause_offers() {
    let offer_contract = deploy_contract();

    // Grant PAUSER_ROLE to pauser
    start_cheat_caller_address(offer_contract.contract_address, ADMIN());
    offer_contract.grant_this_role(PAUSER_ROLE, PAUSER());
    stop_cheat_caller_address(offer_contract.contract_address);

    // Should not be paused initially
    assert!(!offer_contract.are_offers_paused(), "Offers should not be paused initially");

    // Pause offers as pauser
    start_cheat_caller_address(offer_contract.contract_address, PAUSER());
    offer_contract.pause_offers();
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify paused
    assert(offer_contract.are_offers_paused(), 'Offers should be paused');
}

#[test]
#[should_panic(expected: ('Offers Paused',))]
fn test_create_offer_when_paused() {
    let offer_contract = deploy_contract();
    let (nft_contract, payment_token, _) = get_contract_addresses();

    // Grant PAUSER_ROLE and pause offers
    start_cheat_caller_address(offer_contract.contract_address, ADMIN());
    offer_contract.grant_this_role(PAUSER_ROLE, PAUSER());
    stop_cheat_caller_address(offer_contract.contract_address);

    start_cheat_caller_address(offer_contract.contract_address, PAUSER());
    offer_contract.pause_offers();
    stop_cheat_caller_address(offer_contract.contract_address);

    // Try to create offer when paused - should fail
    let current_time: u64 = 100;
    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    start_cheat_caller_address(offer_contract.contract_address, USER1());
    offer_contract
        .create_offer(nft_contract, 1.into(), payment_token, 1000.into(), current_time + 3600);
    stop_cheat_caller_address(offer_contract.contract_address);
    stop_cheat_block_timestamp(offer_contract.contract_address);
}

#[test]
fn test_multiple_admins() {
    let offer_contract = deploy_contract();

    // Grant DEFAULT_ADMIN_ROLE to USER1
    start_cheat_caller_address(offer_contract.contract_address, ADMIN());
    offer_contract.grant_this_role(DEFAULT_ADMIN_ROLE, USER1());
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify both admins exist
    assert(offer_contract.has_this_role(DEFAULT_ADMIN_ROLE, ADMIN()), 'First admin missing');
    assert(offer_contract.has_this_role(DEFAULT_ADMIN_ROLE, USER1()), 'Second admin missing');
    assert(offer_contract.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 2, 'Wrong admin count');

    // Second admin should be able to grant roles
    start_cheat_caller_address(offer_contract.contract_address, USER1());
    offer_contract.grant_this_role(PAUSER_ROLE, PAUSER());
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify role was granted by second admin
    assert!(
        offer_contract.has_this_role(PAUSER_ROLE, PAUSER()), "Role not granted by second admin"
    );
}

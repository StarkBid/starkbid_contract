use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, spy_events, EventSpyAssertionsTrait,
    start_cheat_caller_address_global, stop_cheat_caller_address_global, stop_cheat_block_timestamp,
    start_cheat_block_timestamp
};
use starkbid_contract::components::pausable::IPausableDispatcher;
use starkbid_contract::components::pausable::IPausableDispatcherTrait;
use starkbid_contract::components::pausable::PausableComponent::{
    Event as PausableEvent, Paused, Unpaused
};
use starkbid_contract::interfaces::imarketplace::{
    IMarketplaceDispatcher, IMarketplaceDispatcherTrait, ListingType
};
use starkbid_contract::interfaces::ioffer::{IOfferDispatcher, IOfferDispatcherTrait, OfferStatus};
use starknet::{ContractAddress, contract_address_const};

fn OWNER() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn UNAUTHORIZED_USER() -> ContractAddress {
    contract_address_const::<'unauthorized'>()
}
fn deploy_offer_contract() -> (IOfferDispatcher, IPausableDispatcher) {
    let contract = declare("Offer").unwrap().contract_class();

    // Deploy AS the OWNER address so get_caller_address() returns OWNER
    start_cheat_caller_address_global(OWNER());
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    stop_cheat_caller_address_global();

    (IOfferDispatcher { contract_address }, IPausableDispatcher { contract_address })
}

fn get_contract_addresses() -> (ContractAddress, ContractAddress, ContractAddress) {
    (
        0x123.try_into().unwrap(), // NFT contract
        0x456.try_into().unwrap(), // Payment token (ERC20)
        0x789.try_into().unwrap() // Royalty recipient
    )
}

fn deploy_marketplace_contract() -> (IMarketplaceDispatcher, IPausableDispatcher) {
    let contract = declare("Marketplace").unwrap().contract_class();

    // Deploy AS the OWNER address so get_caller_address() returns OWNER
    start_cheat_caller_address_global(OWNER());
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    stop_cheat_caller_address_global();

    (IMarketplaceDispatcher { contract_address }, IPausableDispatcher { contract_address })
}

#[test]
fn test_pause_functionality() {
    let (_, pausable) = deploy_offer_contract();

    // Initially not paused
    assert(!pausable.paused(), 'Should not be paused initially');

    // Pause contract
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Verify paused
    assert(pausable.paused(), 'Should be paused');
}

#[test]
fn test_unpause_functionality() {
    //pauser
    let (_, pausable) = deploy_offer_contract();

    // Pause first
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    assert(pausable.paused(), 'Should be paused');

    // Unpause
    pausable.unpause();
    stop_cheat_caller_address(pausable.contract_address);

    // Verify unpaused
    assert(!pausable.paused(), 'Should not be paused');
}

#[test]
fn test_pause_events() {
    let (_, pausable) = deploy_offer_contract();
    let mut spy = spy_events();

    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Check for Paused event
    spy
        .assert_emitted(
            @array![(pausable.contract_address, PausableEvent::Paused(Paused { account: OWNER() }))]
        );
}

#[test]
fn test_unpause_events() {
    let (_, pausable) = deploy_offer_contract();
    let mut spy = spy_events();

    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    pausable.unpause();
    stop_cheat_caller_address(pausable.contract_address);

    // Check for Unpaused event
    spy
        .assert_emitted(
            @array![
                (pausable.contract_address, PausableEvent::Unpaused(Unpaused { account: OWNER() }))
            ]
        );
}

#[test]
#[should_panic(expected: 'Caller is not the pauser')]
fn test_unauthorized_pause() {
    let (_, pausable) = deploy_offer_contract();

    // Try to pause with unauthorized user
    start_cheat_caller_address(pausable.contract_address, UNAUTHORIZED_USER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);
}

#[test]
#[should_panic(expected: 'Caller is not the pauser')]
fn test_unauthorized_unpause() {
    let (_, pausable) = deploy_offer_contract();

    // Pause as owner first
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Try to unpause with unauthorized user
    start_cheat_caller_address(pausable.contract_address, UNAUTHORIZED_USER());
    pausable.unpause();
    stop_cheat_caller_address(pausable.contract_address);
}

#[test]
#[should_panic(expected: 'Contract is paused')]
fn test_double_pause() {
    let (_, pausable) = deploy_offer_contract();

    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();

    // Try to pause again, should fail
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);
}

#[test]
#[should_panic(expected: 'Contract is not paused')]
fn test_double_unpause() {
    let (_, pausable) = deploy_offer_contract();

    start_cheat_caller_address(pausable.contract_address, OWNER());

    // Try to unpause when not paused, should fail
    pausable.unpause();
    stop_cheat_caller_address(pausable.contract_address);
}

// Test protected functions in Offer contract
#[test]
#[should_panic(expected: 'Contract is paused')]
fn test_offer_create_when_paused() {
    let (offer_contract, pausable) = deploy_offer_contract();

    // Pause contract
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Try to create offer, should fail
    let nft_contract = contract_address_const::<0x123>();
    let payment_token = contract_address_const::<0x456>();

    offer_contract.create_offer(nft_contract, 1.into(), payment_token, 1000.into(), 1000);
}

#[test]
#[should_panic(expected: 'Contract is paused')]
fn test_offer_accept_when_paused() {
    let (offer_contract, pausable) = deploy_offer_contract();
    let (nft_contract, payment_token, _) = get_contract_addresses();

    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600;

    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    // Create offer first before pausing
    let buyer = contract_address_const::<0x888>();
    start_cheat_caller_address(offer_contract.contract_address, buyer);

    let offer_id = offer_contract
        .create_offer(
            nft_contract, token_id, contract_address_const::<0>(), offer_amount, expiration
        );
    stop_cheat_caller_address(offer_contract.contract_address);

    // Pause contract
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Try to accept offer, should fail with 'Contract is paused'
    start_cheat_caller_address(offer_contract.contract_address, OWNER());
    offer_contract.accept_offer(offer_id);
    stop_cheat_caller_address(offer_contract.contract_address);
}

#[should_panic(expected: 'Contract is paused')]
fn test_offer_cancel_when_paused() {
    let (offer_contract, pausable) = deploy_offer_contract();
    let (nft_contract, _, _) = get_contract_addresses();

    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600;

    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    let buyer = contract_address_const::<0x888>();
    start_cheat_caller_address(offer_contract.contract_address, buyer);
    let offer_id = offer_contract
        .create_offer(
            nft_contract, token_id, contract_address_const::<0>(), offer_amount, expiration
        );
    stop_cheat_caller_address(offer_contract.contract_address);

    // Pause contract
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Try to cancel offer, should fail with Contract is paused
    start_cheat_caller_address(offer_contract.contract_address, buyer);
    offer_contract.cancel_offer(offer_id);
    stop_cheat_caller_address(offer_contract.contract_address);
}

// Test protected functions in Marketplace contract
#[test]
#[should_panic(expected: 'Contract is paused')]
fn test_marketplace_create_listing_when_paused() {
    let (marketplace, pausable) = deploy_marketplace_contract();

    // Pause contract
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Try to create listing, should fail
    let nft_contract = contract_address_const::<0x123>();
    marketplace
        .create_listing(nft_contract, 1.into(), 1000.into(), ListingType::FixedPrice(()), 3600);
}

#[test]
#[should_panic(expected: 'Contract is paused')]
fn test_marketplace_purchase_when_paused() {
    let (marketplace, pausable) = deploy_marketplace_contract();

    // Create listing first
    let nft_contract = contract_address_const::<0x123>();
    start_cheat_caller_address(marketplace.contract_address, OWNER());
    let listing_id = marketplace
        .create_listing(nft_contract, 1.into(), 1000.into(), ListingType::FixedPrice(()), 3600);
    stop_cheat_caller_address(marketplace.contract_address);

    // Pause contract
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();
    stop_cheat_caller_address(pausable.contract_address);

    // Try to purchase, should fail
    marketplace.purchase_listing(listing_id);
}

// Test that functions work normally when not paused
#[test]
fn test_functions_work_when_not_paused() {
    let (offer_contract, pausable) = deploy_offer_contract();
    let (nft_contract, _, _) = get_contract_addresses();

    // Verify not paused
    assert(!pausable.paused(), 'Should not be paused initially');

    let token_id: u256 = 1.into();
    let offer_amount: u256 = 1000.into();
    let current_time: u64 = 100;
    let expiration: u64 = current_time + 3600;

    start_cheat_block_timestamp(offer_contract.contract_address, current_time);

    let buyer = contract_address_const::<0x888>();
    start_cheat_caller_address(offer_contract.contract_address, buyer);
    let offer_id = offer_contract
        .create_offer(
            nft_contract, token_id, contract_address_const::<0>(), offer_amount, expiration
        );
    stop_cheat_caller_address(offer_contract.contract_address);

    // Verify offer was created
    let offer = offer_contract.get_offer(offer_id);
    assert(offer.token_id == 1.into(), 'Offer should be created');
    assert(offer.status == OfferStatus::Active(()), 'Should be active');

    stop_cheat_block_timestamp(offer_contract.contract_address);
}
// Test resume functionality after unpause
#[test]
fn test_resume_after_unpause() {
    let (offer_contract, pausable) = deploy_offer_contract();
    let (nft_contract, _, _) = get_contract_addresses();

    start_cheat_block_timestamp(offer_contract.contract_address, 100);

    // Pause
    start_cheat_caller_address(pausable.contract_address, OWNER());
    pausable.pause();

    // Unpause
    pausable.unpause();
    stop_cheat_caller_address(pausable.contract_address);

    // Use zero payment token
    let buyer = contract_address_const::<0x888>();
    start_cheat_caller_address(offer_contract.contract_address, buyer);
    let offer_id = offer_contract
        .create_offer(nft_contract, 1.into(), contract_address_const::<0>(), 1000.into(), 2000);
    stop_cheat_caller_address(offer_contract.contract_address);

    let offer = offer_contract.get_offer(offer_id);
    assert(offer.token_id == 1.into(), 'Should work after unpause');

    stop_cheat_block_timestamp(offer_contract.contract_address);
}

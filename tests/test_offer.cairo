use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_block_timestamp, stop_cheat_block_timestamp
};

use starkbid_contract::interfaces::ioffer::{IOfferDispatcher, IOfferDispatcherTrait, OfferStatus};
use starknet::ContractAddress;

// Helper to initialize contract
fn deploy_contract() -> IOfferDispatcher {
    let contract = declare("Offer").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    IOfferDispatcher { contract_address }
}

fn get_contract_addresses() -> (ContractAddress, ContractAddress, ContractAddress) {
    (
        0x123.try_into().unwrap(), // NFT contract
        0x456.try_into().unwrap(), // Payment token (ERC20)
        0x789.try_into().unwrap() // Royalty recipient
    )
}

#[test]
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

#[test]
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

#[test]
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

#[test]
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

#[test]
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

use snforge_std::{assert, assert_event_emitted, start_cheat_caller_address, stop_cheat_caller_address};
use starkbid_contract::src::auth::{generate_challenge, verify_challenge, is_authenticated};
use starknet::crypto::{sign_message};
use starknet::ContractAddress;

#[test]
fn test_generate_challenge() {
    let auth_contract = init_auth_contract();
    let wallet = ContractAddress::from(0x123);

    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let nonce = auth_contract.generate_challenge(wallet);
    stop_cheat_caller_address(auth_contract.contract_address);

    assert_event_emitted!(AuthenticationAttempt, |event| {
        event.wallet == wallet && event.nonce == nonce
    });
}

#[test]
fn test_verify_challenge_success() {
    let auth_contract = init_auth_contract();
    let wallet = ContractAddress::from(0x123);

    // Generate a challenge
    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let nonce = auth_contract.generate_challenge(wallet);
    stop_cheat_caller_address(auth_contract.contract_address);

    // Sign the nonce
    let private_key = 0xabc; 
    let signature = sign_message(wallet, nonce, private_key);

    // Verify the challenge
    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let is_valid = auth_contract.verify_challenge(wallet, nonce, signature);
    stop_cheat_caller_address(auth_contract.contract_address);

    assert(is_valid, "Authentication failed when it should have succeeded");
    assert_event_emitted!(AuthenticationSuccess, |event| {
        event.wallet == wallet
    });
}

#[test]
fn test_verify_challenge_invalid_signature() {
    let auth_contract = init_auth_contract();
    let wallet = ContractAddress::from(0x123);

    // Generate a challenge
    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let nonce = auth_contract.generate_challenge(wallet);
    stop_cheat_caller_address(auth_contract.contract_address);

    // Provide an invalid signature
    let invalid_signature = [0xdeadbeef];

    // Verify the challenge
    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let is_valid = auth_contract.verify_challenge(wallet, nonce, invalid_signature);
    stop_cheat_caller_address(auth_contract.contract_address);

    assert(!is_valid, "Authentication succeeded with an invalid signature");
    assert_event_emitted!(AuthenticationFailure, |event| {
        event.wallet == wallet && event.reason == "Invalid signature"
    });
}

#[test]
fn test_verify_challenge_expired_nonce() {
    let auth_contract = init_auth_contract();
    let wallet = ContractAddress::from(0x123);

    // Generate a challenge
    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let nonce = auth_contract.generate_challenge(wallet);
    stop_cheat_caller_address(auth_contract.contract_address);

    // Simulate time passing beyond the expiration
    cheat_increase_block_timestamp(600);  

    // Sign the nonce
    let private_key = 0xabc; 
    let signature = sign_message(wallet, nonce, private_key);

    // Verify the challenge
    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let is_valid = auth_contract.verify_challenge(wallet, nonce, signature);
    stop_cheat_caller_address(auth_contract.contract_address);

    assert(!is_valid, "Authentication succeeded with an expired nonce");
    assert_event_emitted!(AuthenticationFailure, |event| {
        event.wallet == wallet && event.reason == "Nonce expired"
    });
}

#[test]
fn test_is_authenticated() {
    let auth_contract = init_auth_contract();
    let wallet = ContractAddress::from(0x123);

    // Initially, the wallet should not be authenticated
    let is_authenticated = auth_contract.is_authenticated(wallet);
    assert(!is_authenticated, "Wallet is authenticated without verification");

    // Generate and verify a challenge
    start_cheat_caller_address(auth_contract.contract_address, wallet);
    let nonce = auth_contract.generate_challenge(wallet);
    let private_key = 0xabc; 
    let signature = sign_message(wallet, nonce, private_key);
    auth_contract.verify_challenge(wallet, nonce, signature);
    stop_cheat_caller_address(auth_contract.contract_address);

    let is_authenticated = auth_contract.is_authenticated(wallet);
    assert(is_authenticated, "Wallet is not authenticated after successful verification");
}
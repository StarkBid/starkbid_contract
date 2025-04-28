use starknet::ContractAddress;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};

use starkbid_contract::{IVerifySignatureSafeDispatcher, IVerifySignatureSafeDispatcherTrait, IVerifySignatureDispatcherTrait, IVerifySignatureDispatcher};

// Test constants
const TEST_MESSAGE: felt252 = [1, 128, 18, 14];
const VALID_SIGNATURE_R: felt252 = 12345;
const VALID_SIGNATURE_S: felt252 = 67890;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_successful_verification() {
    let contract_address = deploy_contract("VerifySignature");
    let user_address = 1.try_into().unwrap();
    
    start_cheat_caller_address(contract_address, user_address);
    
    let mut dispatcher = IVerifySignatureDispatcher { contract_address };
    
    // Initial nonce should be 0
    assert(dispatcher.get_nonce(user_address) == 0, 'Invalid initial nonce');
    
    // Test verification with valid signature
    let success = dispatcher.verify_signature(
        user_address,
        TEST_MESSAGE,
        VALID_SIGNATURE_R,
        VALID_SIGNATURE_S
    );
    
    // Verification should succeed
    assert(success, 'Verification failed');
    
    // Nonce should be incremented
    assert(dispatcher.get_nonce(user_address) == 1, 'Nonce not incremented');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_replay_attack_prevention() {
    let contract_address = deploy_contract("VerifySignature");
    let user_address = 1.try_into().unwrap();
    
    start_cheat_caller_address(contract_address, user_address);
    
    let mut dispatcher = IVerifySignatureDispatcher { contract_address };

    // First verification should succeed
    let success1 = dispatcher.verify_signature(
        user_address,
        TEST_MESSAGE,
        VALID_SIGNATURE_R,
        VALID_SIGNATURE_S
    );
    assert(success1, 'First verification failed');
    
    // Second verification with same signature should fail (replay attack)
    let success2 = dispatcher.verify_signature(
        user_address,
        TEST_MESSAGE,
        VALID_SIGNATURE_R,
        VALID_SIGNATURE_S
    );
    assert(!success2, 'Replay attack not prevented');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_multiple_users() {
    let contract_address = deploy_contract("VerifySignature");
    let user1_address = 1.try_into().unwrap();
    let user2_address = 2.try_into().unwrap();
    
    let mut dispatcher = IVerifySignatureDispatcher { contract_address };
    
    // Verify first user
    start_cheat_caller_address(contract_address, user1_address);
    let success1 = dispatcher.verify_signature(
        user1_address,
        TEST_MESSAGE,
        VALID_SIGNATURE_R,
        VALID_SIGNATURE_S
    );
    assert(success1, 'User1 verification failed');
    stop_cheat_caller_address(contract_address);
    
    // Verify second user
    start_cheat_caller_address(contract_address, user2_address);
    let success2 = dispatcher.verify_signature(
        user2_address,
        TEST_MESSAGE,
        VALID_SIGNATURE_R,
        VALID_SIGNATURE_S
    );
    assert(success2, 'User2 verification failed');
    stop_cheat_caller_address(contract_address);
    
    // Check nonces are incremented independently
    assert(dispatcher.get_nonce(user1_address) == 1, 'User1 nonce incorrect');
    assert(dispatcher.get_nonce(user2_address) == 1, 'User2 nonce incorrect');
}

#[test]
fn test_caller_address() {
    let contract_address = deploy_contract("VerifySignature");
    let user_address = 1.try_into().unwrap();
    
    start_cheat_caller_address(contract_address, user_address);
    
    let mut dispatcher = IVerifySignatureDispatcher { contract_address };
    
    // Check caller address
    let caller = dispatcher.get_caller_address();
    assert(caller == user_address, 'Invalid caller address');

    stop_cheat_caller_address(contract_address);
}

#[test]
#[feature("safe_dispatcher")]
fn test_invalid_user_address() {
    let contract_address = deploy_contract("VerifySignature");
    let user_address = 0.try_into().unwrap(); // Zero address
    
    let safe_dispatcher = IVerifySignatureSafeDispatcher { contract_address };
    
    match safe_dispatcher.verify_signature(
        user_address,
        TEST_MESSAGE,
        VALID_SIGNATURE_R,
        VALID_SIGNATURE_S
    ) {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0_usize) == 'Invalid user address', *panic_data.at(0_usize));
        },
    };
}

// Public Key (claimed_address): 0x31b88d91e173d70b5bd284f7a898d99005d9ade236ee671e0db0078996aa599
// Message Hash: 0x58321ffee1726cb07afce91edc8dfdaad7529ea299105d5a42558078f45d73
// r: 3f84085dd543cffc770b5a2b19f3b82111fc3edb4baa9037e2a0065aa97e653
// s: 55630ca80a49ba6bfb979accc01f18a3a7179071b819b38c42ef94144eebcf
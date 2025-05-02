use starknet::ContractAddress;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};

use starkbid_contract::interfaces::iverify_sig::{IVerifySignatureSafeDispatcher, IVerifySignatureSafeDispatcherTrait, IVerifySignatureDispatcherTrait, IVerifySignatureDispatcher};

const TEST_MESSAGE: felt252 = 0x65ad64cab8a5e6aca149cb913a31ad2d0129a0c81fe20c33c2d5f1892215529;

const VALID_SIGNATURE_R: felt252 = 0x7cbf320dabe3be212384b74213ffff100e75920513e74558ceec110d041d133;
const VALID_SIGNATURE_S: felt252 = 0x2a28596801bae683197812ab8072489289b4230d51a0dcd1b6b1848c234472e;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_successful_verification() {
    let contract_address = deploy_contract("VerifySignature");
    let user_address = 0x3c10a541a68dd7b4f9be06c5ccac0f2d91e2810c5cfe460370e3cee25afce56.try_into().unwrap();
    
    start_cheat_caller_address(contract_address, user_address);
    
    let dispatcher = IVerifySignatureDispatcher { contract_address };
    
    // Test verification with valid signature
    let success = dispatcher.verify_signature(
        user_address,
        TEST_MESSAGE,
        VALID_SIGNATURE_R,
        VALID_SIGNATURE_S
    );
    
    // Verification should succeed
    assert(success, 'Verification failed');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_invalid_signature() {
    let contract_address = deploy_contract("VerifySignature");
    let user_address = 0x3c10a541a68dd7b4f9be06c5ccac0f2d91e2810c5cfe460370e3cee25afce56.try_into().unwrap();
    let INVALID_SIGNATURE_R = 0x3ecf5bd3cb1730db4d93afa06171ea06b51b4d5951d4b877721aaafda04512f;
    let INVALID_SIGNATURE_S = 0x373741a5eac15c4d018d3c6f289b7af8f2d92e8a021e5ccb4ca19252d3afb1c;
    
    start_cheat_caller_address(contract_address, user_address);
    
    let dispatcher = IVerifySignatureDispatcher { contract_address };

    let verified = dispatcher.verify_signature(
        user_address,
        TEST_MESSAGE,
        INVALID_SIGNATURE_R,
        INVALID_SIGNATURE_S
    );
    assert(!verified, 'Invalid signature');
    
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_multiple_users() {
    let contract_address = deploy_contract("VerifySignature");
    let user1_address = 0x3c10a541a68dd7b4f9be06c5ccac0f2d91e2810c5cfe460370e3cee25afce56.try_into().unwrap();
    let user2_address = 0xbc774f8ca1bbe71728cd661ad4515d66dca540bd697788e48787f970900a0b.try_into().unwrap(); // Replace with a different public key
    
    let dispatcher = IVerifySignatureDispatcher { contract_address };
    
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
        0x3ecf5bd3cb1730db4d93afa06171ea06b51b4d5951d4b877721aaafda04512f,
        0x373741a5eac15c4d018d3c6f289b7af8f2d92e8a021e5ccb4ca19252d3afb1c
    );
    assert(success2, 'User2 verification failed');
    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_caller_address() {
    let contract_address = deploy_contract("VerifySignature");
    let user_address = 0x3c10a541a68dd7b4f9be06c5ccac0f2d91e2810c5cfe460370e3cee25afce56.try_into().unwrap();
    
    start_cheat_caller_address(contract_address, user_address);
    
    let dispatcher = IVerifySignatureDispatcher { contract_address };
    
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
            assert(*panic_data.at(0) == 'Invalid user address', 'Unexpected panic data');
        },
    };
}

// with ts: user 1
// Public Key (claimed_address): 0x3c10a541a68dd7b4f9be06c5ccac0f2d91e2810c5cfe460370e3cee25afce56
// Full Public Key: 0x0403c10a541a68dd7b4f9be06c5ccac0f2d91e2810c5cfe460370e3cee25afce56077bcb1bc19e46f37cf09f8cca167c831b79024ea74c460f68f14ef823cda423
// Message Hash: 0x65ad64cab8a5e6aca149cb913a31ad2d0129a0c81fe20c33c2d5f1892215529
// r: 0x7cbf320dabe3be212384b74213ffff100e75920513e74558ceec110d041d133
// s: 0x2a28596801bae683197812ab8072489289b4230d51a0dcd1b6b1848c234472e

// user2
// Public Key (claimed_address): 0xbc774f8ca1bbe71728cd661ad4515d66dca540bd697788e48787f970900a0b
// Full Public Key: 0x0400bc774f8ca1bbe71728cd661ad4515d66dca540bd697788e48787f970900a0b00cf961e985937e65eb4af777752ca08ff93bb052abf7e510b67dd51afdb2c90
// Message Hash: 0x65ad64cab8a5e6aca149cb913a31ad2d0129a0c81fe20c33c2d5f1892215529
// r: 0x3ecf5bd3cb1730db4d93afa06171ea06b51b4d5951d4b877721aaafda04512f
// s: 0x373741a5eac15c4d018d3c6f289b7af8f2d92e8a021e5ccb4ca19252d3afb1c

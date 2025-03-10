use starknet::ContractAddress;
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};

use starkbid_contract::IHelloStarknetSafeDispatcher;
use starkbid_contract::IHelloStarknetSafeDispatcherTrait;
use starkbid_contract::IHelloStarknetDispatcher;
use starkbid_contract::IHelloStarknetDispatcherTrait;
use starknet::contract_address_const;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_increase_balance() {
    let contract_address = deploy_contract("HelloStarknet");

    let dispatcher = IHelloStarknetDispatcher { contract_address };

    let balance_before = dispatcher.get_balance();
    assert(balance_before == 0, 'Invalid balance');

    dispatcher.increase_balance(42);

    let balance_after = dispatcher.get_balance();
    assert(balance_after == 42, 'Invalid balance');
}

#[test]
#[feature("safe_dispatcher")]
fn test_cannot_increase_balance_with_zero_value() {
    let contract_address = deploy_contract("HelloStarknet");

    let safe_dispatcher = IHelloStarknetSafeDispatcher { contract_address };

    let balance_before = safe_dispatcher.get_balance().unwrap();
    assert(balance_before == 0, 'Invalid balance');

    match safe_dispatcher.increase_balance(0) {
        Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
        Result::Err(panic_data) => {
            assert(*panic_data.at(0) == 'Amount cannot be 0', *panic_data.at(0));
        },
    };
}

#[test]
fn test_validate_wallet() {
    let contract_address = deploy_contract("HelloStarknet");
    let dispatcher = IHelloStarknetDispatcher { contract_address };

    // Test zero address
    let zero_address: ContractAddress = contract_address_const::<0>();
    assert(!dispatcher.validate_wallet(zero_address), 'Zero address should fail');

    // Test with a valid address
    let valid_address: ContractAddress = contract_address_const::<0x02e554f88fc04ddbc2809d15f6dcdc1e8f339d4be8459a2c026713de3d0f22cd>();
    assert(dispatcher.validate_wallet(valid_address), 'Valid address should pass');
}

#[test]
fn test_get_caller_address() {
    let contract_address = deploy_contract("HelloStarknet");
    let test_wallet: ContractAddress = 0x123456789.try_into().unwrap();

    start_cheat_caller_address(contract_address, test_wallet);

    let dispatcher = IHelloStarknetDispatcher { contract_address };
    let caller_address = dispatcher.get_caller_address();
    let test_wallet_felt: felt252 = test_wallet.into();

    assert(caller_address == test_wallet_felt, 'Invalid caller address');
    stop_cheat_caller_address(contract_address);
}

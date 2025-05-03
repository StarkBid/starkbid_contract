use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starkbid_contract::interfaces::iownership::{IOwnershipDispatcher, IOwnershipDispatcherTrait};
use starknet::{ContractAddress, contract_address_const};

// Helper to initialize contract
fn deploy_contract() -> IOwnershipDispatcher {
    let contract_class = declare("Ownership").unwrap().contract_class();
    let (contract_address, _) = contract_class.deploy(@array![]).unwrap();
    IOwnershipDispatcher { contract_address }
}


fn ASSET_CONTRACT() -> ContractAddress {
    contract_address_const::<'ASSET'>()
}

fn OWNER_CONTRACT() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}
fn NEW_OWNER_CONTRACT() -> ContractAddress {
    contract_address_const::<'NEW_OWNER'>()
}

#[test]
fn test_transfer_ownership_successful() {
    let ownership_dispatcher = deploy_contract();
    let token_id: u256 = 1;
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
    // verify asset owner
    let asset_owner = ownership_dispatcher.get_asset_owner(ASSET_CONTRACT(), token_id);
    let asset_ownership_history = ownership_dispatcher
        .get_asset_ownership_history(ASSET_CONTRACT(), token_id);
    assert(asset_owner == OWNER_CONTRACT(), 'Invalid Owner');
    assert(asset_ownership_history.len() == 1, 'Invalid history length');
    assert(*asset_ownership_history.at(0) == OWNER_CONTRACT(), 'Invalid history data');

    // Change owner to another contract
    start_cheat_caller_address(ownership_dispatcher.contract_address, OWNER_CONTRACT());
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, NEW_OWNER_CONTRACT());
    stop_cheat_caller_address(ownership_dispatcher.contract_address);

    // Check if new_owner is the owner
    // verify new asset owner
    let asset_owner = ownership_dispatcher.get_asset_owner(ASSET_CONTRACT(), token_id);
    let asset_ownership_history = ownership_dispatcher
        .get_asset_ownership_history(ASSET_CONTRACT(), token_id);
    assert(asset_owner == NEW_OWNER_CONTRACT(), 'Invalid Owner');
    assert(asset_ownership_history.len() == 2, 'Invalid history length');
    assert(*asset_ownership_history.at(0) == OWNER_CONTRACT(), 'Invalid history data at index 0');
    assert(
        *asset_ownership_history.at(1) == NEW_OWNER_CONTRACT(), 'Invalid history data at index 1',
    );
}

#[test]
#[should_panic(expected: 'Invalid Owner')]
fn test_transfer_ownership_fails_with_invalid_owner() {
    let ownership_dispatcher = deploy_contract();
    let token_id: u256 = 1;
    // This won't fail because the current owner of this asset
    // is a zero address and the caller is a zero address
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
    // This wull fail because the current owner of this asset
    // is the owner_contract and the caller is a zero address
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, NEW_OWNER_CONTRACT());
}

#[test]
#[should_panic(expected: 'Cannot transfer asset to self')]
fn test_transfer_ownership_fails_with_same_owner() {
    let ownership_dispatcher = deploy_contract();
    let token_id: u256 = 1;
    // This won't fail because the current owner of this asset
    // is a zero address and the caller is a zero address
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
    // This wull fail because the current owner of this asset
    // is the owner_contract and the new_owner is the owner_contract
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
}

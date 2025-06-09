use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};

// Import the contract interfaces (adjust path as needed)
use starkbid_contract::interfaces::inft_metadata::{
    IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait, IMetadataManagerDispatcher,
    IMetadataManagerDispatcherTrait,
};
use starkbid_contract::nft_metadata::ERC721Metadata;
use starknet::testing::{set_block_timestamp, set_caller_address};
use starknet::{ContractAddress, contract_address_const};


// Test constants
fn OWNER() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn USER() -> ContractAddress {
    contract_address_const::<'user'>()
}

fn ADMIN() -> ContractAddress {
    contract_address_const::<'admin'>()
}

fn NAME() -> ByteArray {
    "TestNFT"
}

fn SYMBOL() -> ByteArray {
    "TNFT"
}

fn GATEWAY() -> ByteArray {
    "https://ipfs.io/ipfs/"
}

fn SAMPLE_IPFS_HASH() -> ByteArray {
    "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG"
}

fn UPDATED_IPFS_HASH() -> ByteArray {
    "QmNewHashForUpdatedMetadata123456789"
}

// Helper function to deploy contract
fn deploy_contract() -> ContractAddress {
    let contract = declare("ERC721Metadata").unwrap().contract_class();
    let mut constructor_args: Array<felt252> = array![];
    NAME().serialize(ref constructor_args);
    SYMBOL().serialize(ref constructor_args);
    OWNER().serialize(ref constructor_args);
    GATEWAY().serialize(ref constructor_args);

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}

// =====================================
// ERC-721 Metadata Standard Tests
// =====================================

#[test]
fn test_name() {
    let contract_address = deploy_contract();
    let dispatcher = IERC721MetadataDispatcher { contract_address };

    let name = dispatcher.name();
    assert!(name == NAME(), "Name should match constructor value");
}

#[test]
fn test_symbol() {
    let contract_address = deploy_contract();
    let dispatcher = IERC721MetadataDispatcher { contract_address };

    let symbol = dispatcher.symbol();
    assert!(symbol == SYMBOL(), "Symbol should match constructor value");
}

#[test]
fn test_token_uri_for_existing_token() {
    let contract_address = deploy_contract();
    let metadata_dispatcher = IMetadataManagerDispatcher { contract_address };
    let erc721_dispatcher = IERC721MetadataDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    // Set metadata for token
    let token_id = 1_u256;
    let ipfs_hash = SAMPLE_IPFS_HASH();
    let metadata_hash = 12345_felt252;

    metadata_dispatcher.set_token_metadata(token_id, ipfs_hash.clone(), metadata_hash);

    // Get token URI
    let uri = erc721_dispatcher.token_uri(token_id);
    let expected_uri = metadata_dispatcher.construct_ipfs_url(ipfs_hash);

    assert!(uri == expected_uri, "Token URI should match constructed IPFS URL");

    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'Token does not exist')]
fn test_token_uri_for_nonexistent_token() {
    let contract_address = deploy_contract();
    let dispatcher = IERC721MetadataDispatcher { contract_address };

    let _uri = dispatcher.token_uri(999_u256);
}

// =====================================
// Metadata Management Tests
// =====================================

#[test]
fn test_set_token_metadata() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let token_id = 1_u256;
    let ipfs_hash = SAMPLE_IPFS_HASH();
    let metadata_hash = 12345_felt252;

    dispatcher.set_token_metadata(token_id, ipfs_hash.clone(), metadata_hash);

    let (stored_hash, stored_metadata_hash) = dispatcher.get_token_metadata(token_id);
    assert!(stored_hash == ipfs_hash, "IPFS hash should be stored correctly");
    assert!(stored_metadata_hash == metadata_hash, "Metadata hash should be stored correctly");

    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'Only owner can set metadata')]
fn test_set_token_metadata_unauthorized() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, USER());

    dispatcher.set_token_metadata(1_u256, SAMPLE_IPFS_HASH(), 12345_felt252);
}

#[test]
fn test_update_token_metadata() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let token_id = 1_u256;
    let initial_hash = SAMPLE_IPFS_HASH();
    let updated_hash = UPDATED_IPFS_HASH();
    let metadata_hash = 12345_felt252;
    let updated_metadata_hash = 54321_felt252;

    // Set initial metadata
    dispatcher.set_token_metadata(token_id, initial_hash, metadata_hash);

    // Update metadata
    dispatcher.update_token_metadata(token_id, updated_hash.clone(), updated_metadata_hash);

    let (stored_hash, stored_metadata_hash) = dispatcher.get_token_metadata(token_id);
    assert!(stored_hash == updated_hash, "IPFS hash should be updated");
    assert!(stored_metadata_hash == updated_metadata_hash, "Metadata hash should be updated");

    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'Not authorized')]
fn test_update_token_metadata_unauthorized() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    // Owner sets initial metadata
    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(1_u256, SAMPLE_IPFS_HASH(), 12345_felt252);
    stop_cheat_caller_address(contract_address);

    // Unauthorized user tries to update
    start_cheat_caller_address(contract_address, USER());
    dispatcher.update_token_metadata(1_u256, UPDATED_IPFS_HASH(), 54321_felt252);
}

#[test]
#[should_panic(expected: 'Token does not exist')]
fn test_get_token_metadata_nonexistent() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let _metadata = dispatcher.get_token_metadata(999_u256);
}

// =====================================
// Attribute Management Tests
// =====================================

#[test]
fn test_add_attribute() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let token_id = 1_u256;
    dispatcher.set_token_metadata(token_id, SAMPLE_IPFS_HASH(), 12345_felt252);

    let trait_type = 'rarity';
    let value = 'legendary';

    dispatcher.add_attribute(token_id, trait_type, value);

    let stored_value = dispatcher.get_attribute(token_id, trait_type);
    assert!(stored_value == value, "Attribute should be stored correctly");

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_add_multiple_attributes() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let token_id = 1_u256;
    dispatcher.set_token_metadata(token_id, SAMPLE_IPFS_HASH(), 12345_felt252);

    // Add multiple attributes
    dispatcher.add_attribute(token_id, 'rarity', 'legendary');
    dispatcher.add_attribute(token_id, 'power', 'fire');
    dispatcher.add_attribute(token_id, 'level', '100');

    let all_attributes = dispatcher.get_all_attributes(token_id);
    assert!(all_attributes.len() == 3, "Should have 3 attributes");

    // Check individual attributes
    assert!(
        dispatcher.get_attribute(token_id, 'rarity') == 'legendary', "Rarity attribute incorrect",
    );
    assert!(dispatcher.get_attribute(token_id, 'power') == 'fire', "Power attribute incorrect");
    assert!(dispatcher.get_attribute(token_id, 'level') == '100', "Level attribute incorrect");

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_remove_attribute() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let token_id = 1_u256;
    dispatcher.set_token_metadata(token_id, SAMPLE_IPFS_HASH(), 12345_felt252);

    let trait_type = 'rarity';
    let value = 'legendary';

    // Add then remove attribute
    dispatcher.add_attribute(token_id, trait_type, value);
    dispatcher.remove_attribute(token_id, trait_type);

    let stored_value = dispatcher.get_attribute(token_id, trait_type);
    assert!(stored_value == 0, "Attribute should be removed");

    let all_attributes = dispatcher.get_all_attributes(token_id);
    assert!(all_attributes.len() == 0, "Should have no attributes after removal");

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_update_existing_attribute() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let token_id = 1_u256;
    dispatcher.set_token_metadata(token_id, SAMPLE_IPFS_HASH(), 12345_felt252);

    let trait_type = 'rarity';
    let initial_value = 'common';
    let updated_value = 'legendary';

    // Add initial attribute
    dispatcher.add_attribute(token_id, trait_type, initial_value);
    assert!(
        dispatcher.get_attribute(token_id, trait_type) == initial_value, "Initial value incorrect",
    );

    // Update existing attribute
    dispatcher.add_attribute(token_id, trait_type, updated_value);
    assert!(
        dispatcher.get_attribute(token_id, trait_type) == updated_value, "Updated value incorrect",
    );

    // Should still have only one attribute
    let all_attributes = dispatcher.get_all_attributes(token_id);
    assert!(all_attributes.len() == 1, "Should have only 1 attribute after update");

    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'Not authorized')]
fn test_add_attribute_unauthorized() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(1_u256, SAMPLE_IPFS_HASH(), 12345_felt252);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER());
    dispatcher.add_attribute(1_u256, 'rarity', 'legendary');
}

#[test]
#[should_panic(expected: 'Token does not exist')]
fn test_add_attribute_nonexistent_token() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.add_attribute(999_u256, 'rarity', 'legendary');
}

// =====================================
// Validation Tests
// =====================================

#[test]
fn test_validate_metadata_valid() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let token_id = 1_u256;
    dispatcher.set_token_metadata(token_id, SAMPLE_IPFS_HASH(), 12345_felt252);

    let is_valid = dispatcher.validate_metadata(token_id);
    assert!(is_valid, "Metadata should be valid");

    stop_cheat_caller_address(contract_address);
}

#[test]
fn test_validate_metadata_nonexistent_token() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let is_valid = dispatcher.validate_metadata(999_u256);
    assert!(!is_valid, "Metadata should be invalid for nonexistent token");
}

#[test]
fn test_validate_ipfs_hash() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let valid_hash = SAMPLE_IPFS_HASH();
    let empty_hash: ByteArray = "";

    assert!(dispatcher.validate_ipfs_hash(valid_hash), "Valid hash should pass validation");
    assert!(!dispatcher.validate_ipfs_hash(empty_hash), "Empty hash should fail validation");
}

// =====================================
// URL Construction Tests
// =====================================

#[test]
fn test_construct_ipfs_url() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let ipfs_hash = SAMPLE_IPFS_HASH();
    let url = dispatcher.construct_ipfs_url(ipfs_hash.clone());

    let expected_url = GATEWAY() + ipfs_hash;
    assert!(url == expected_url, "Constructed URL should match expected format");
}

#[test]
fn test_get_gateway_url() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let gateway = dispatcher.get_gateway_url();
    assert!(gateway == GATEWAY(), "Gateway should match constructor value");
}

#[test]
fn test_set_gateway_url() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());

    let new_gateway: ByteArray = "https://gateway.pinata.cloud/ipfs/";
    dispatcher.set_gateway_url(new_gateway.clone());

    let stored_gateway = dispatcher.get_gateway_url();
    assert!(stored_gateway == new_gateway, "Gateway should be updated");

    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'Only owner can set gateway')]
fn test_set_gateway_url_unauthorized() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, USER());
    dispatcher.set_gateway_url("https://unauthorized.gateway/");
}

// =====================================
// Authorization Tests
// =====================================

#[test]
fn test_is_authorized_owner() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(1_u256, SAMPLE_IPFS_HASH(), 12345_felt252);
    stop_cheat_caller_address(contract_address);

    // Owner should always be authorized
    assert!(dispatcher.is_authorized(1_u256, OWNER()), "Owner should be authorized");
}

#[test]
fn test_is_authorized_admin() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let token_id = 1_u256;

    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(token_id, SAMPLE_IPFS_HASH(), 12345_felt252);
    dispatcher.set_metadata_admin(token_id, ADMIN());
    stop_cheat_caller_address(contract_address);

    // Admin should be authorized for their token
    assert!(dispatcher.is_authorized(token_id, ADMIN()), "Admin should be authorized");

    // Admin should not be authorized for other tokens
    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(2_u256, SAMPLE_IPFS_HASH(), 12345_felt252);
    stop_cheat_caller_address(contract_address);

    assert!(
        !dispatcher.is_authorized(2_u256, ADMIN()),
        "Admin should not be authorized for other tokens",
    );
}

#[test]
fn test_is_authorized_unauthorized_user() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(1_u256, SAMPLE_IPFS_HASH(), 12345_felt252);
    stop_cheat_caller_address(contract_address);

    // Regular user should not be authorized
    assert!(!dispatcher.is_authorized(1_u256, USER()), "Regular user should not be authorized");
}

#[test]
fn test_set_metadata_admin() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let token_id = 1_u256;

    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(token_id, SAMPLE_IPFS_HASH(), 12345_felt252);

    // Set admin
    dispatcher.set_metadata_admin(token_id, ADMIN());

    let stored_admin = dispatcher.get_metadata_admin(token_id);
    assert!(stored_admin == ADMIN(), "Admin should be set correctly");

    stop_cheat_caller_address(contract_address);
}

#[test]
#[should_panic(expected: 'Not authorized')]
fn test_set_metadata_admin_unauthorized() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    start_cheat_caller_address(contract_address, OWNER());
    dispatcher.set_token_metadata(1_u256, SAMPLE_IPFS_HASH(), 12345_felt252);
    stop_cheat_caller_address(contract_address);

    start_cheat_caller_address(contract_address, USER());
    dispatcher.set_metadata_admin(1_u256, ADMIN());
}

#[test]
#[should_panic(expected: 'Token does not exist')]
fn test_get_metadata_admin_nonexistent_token() {
    let contract_address = deploy_contract();
    let dispatcher = IMetadataManagerDispatcher { contract_address };

    let _admin = dispatcher.get_metadata_admin(999_u256);
}

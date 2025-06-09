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

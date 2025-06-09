use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};

// Import the contract interfaces (adjust path as needed)
use starkbid_contract::interfaces::inft_metadata::{IERC721Metadata, IMetadataManager};
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

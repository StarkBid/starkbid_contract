use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};

// Import the contract interfaces (adjust path as needed)
use starkbid_contract::interfaces::ierc721::{IERC721MintableDispatcher, IERC721MintableDispatcherTrait, 
    IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait, IERC721Dispatcher, IERC721DispatcherTrait};

use starknet::{ContractAddress, contract_address_const};

// Test constants
fn OWNER() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn USER() -> ContractAddress {
    contract_address_const::<'user'>()
}

fn NAME() -> ByteArray {
    "TestNFT"
}

fn SYMBOL() -> ByteArray {
    "TNFT"
}

fn BASE_URI() -> ByteArray {
    "https://ipfs.io/ipfs/"
}



// Helper function to deploy contract
fn deploy_contract() -> ContractAddress {
    let contract = declare("ERC721Metadata").unwrap().contract_class();
    let mut constructor_args: Array<felt252> = array![];
    OWNER().serialize(ref constructor_args);
    NAME().serialize(ref constructor_args);
    SYMBOL().serialize(ref constructor_args);
    BASE_URI().serialize(ref constructor_args);

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap();
    contract_address
}
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


#[test]
fn test_nft_factory() {
    let nft_factory_address = deploy_contract();

    let erc721_dispatcher = IERC721Dispatcher {contract_address: nft_factory_address};
    let erc721_metadata_dispatcher = IERC721MetadataDispatcher {contract_address: nft_factory_address};
    // check if the contract is deployed
    assert(erc721_metadata_dispatcher.name() == NAME(), 'name mismatch');
    assert(erc721_metadata_dispatcher.symbol() == SYMBOL(), 'symbol mismatch');
    assert(erc721_metadata_dispatcher.base_uri() == BASE_URI(), 'base uri mismatch');

}
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};

// Import the contract interfaces (adjust path as needed)
use starkbid_contract::interfaces::ierc721::{
    IERC721MintableDispatcher, IERC721MintableDispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait, IERC721Dispatcher, IERC721DispatcherTrait
};

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
    let contract = declare("NftFactory").unwrap().contract_class();
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
    let erc721_metadata_dispatcher = IERC721MetadataDispatcher {
        contract_address: nft_factory_address
    };
    // check if the contract is deployed
    assert(erc721_metadata_dispatcher.name() == NAME(), 'name mismatch');
    assert(erc721_metadata_dispatcher.symbol() == SYMBOL(), 'symbol mismatch');
}

#[test]
fn test_nft_factory_mint() {
    let nft_factory_address = deploy_contract();
    let erc721_mintable_dispatcher = IERC721MintableDispatcher {
        contract_address: nft_factory_address
    };
    let erc721_dispatcher = IERC721Dispatcher { contract_address: nft_factory_address };
    start_cheat_caller_address(nft_factory_address, OWNER());
    erc721_mintable_dispatcher.mint(1);
    stop_cheat_caller_address(nft_factory_address);
    assert(erc721_dispatcher.balance_of(OWNER()) == 1, 'balance mismatch');
    assert(erc721_dispatcher.owner_of(1) == OWNER(), 'owner mismatch');
}

#[test]
fn test_nft_factory_burn() {
    let nft_factory_address = deploy_contract();
    let erc721_mintable_dispatcher = IERC721MintableDispatcher {
        contract_address: nft_factory_address
    };
    let erc721_dispatcher = IERC721Dispatcher { contract_address: nft_factory_address };
    start_cheat_caller_address(nft_factory_address, OWNER());
    erc721_mintable_dispatcher.mint(1);
    stop_cheat_caller_address(nft_factory_address);
    start_cheat_caller_address(nft_factory_address, OWNER());
    erc721_mintable_dispatcher.burn(1);
    assert(erc721_dispatcher.balance_of(OWNER()) == 0, 'balance mismatch');
    stop_cheat_caller_address(nft_factory_address);
}


#[test]
#[should_panic]
fn test_nft_factory_burn_not_owner() {
    let nft_factory_address = deploy_contract();
    let erc721_mintable_dispatcher = IERC721MintableDispatcher {
        contract_address: nft_factory_address
    };
    let erc721_dispatcher = IERC721Dispatcher { contract_address: nft_factory_address };
    start_cheat_caller_address(nft_factory_address, USER());
    erc721_mintable_dispatcher.mint(1);
    stop_cheat_caller_address(nft_factory_address);
    assert(erc721_dispatcher.balance_of(OWNER()) == 1, 'balance mismatch');
    assert(erc721_dispatcher.owner_of(1) == OWNER(), 'owner mismatch');
    stop_cheat_caller_address(nft_factory_address);
    erc721_mintable_dispatcher.burn(1); // should panic
}

#[test]
fn test_nft_factory_transfer() {
    let nft_factory_address = deploy_contract();
    let erc721_mintable_dispatcher = IERC721MintableDispatcher {
        contract_address: nft_factory_address
    };
    let erc721_dispatcher = IERC721Dispatcher { contract_address: nft_factory_address };
    start_cheat_caller_address(nft_factory_address, OWNER());
    erc721_mintable_dispatcher.mint(1);
    erc721_dispatcher.transfer_from(OWNER(), USER(), 1);
    stop_cheat_caller_address(nft_factory_address);
    assert(erc721_dispatcher.balance_of(OWNER()) == 0, 'balance mismatch');
    assert(erc721_dispatcher.balance_of(USER()) == 1, 'balance mismatch');
    assert(erc721_dispatcher.owner_of(1) == USER(), 'owner mismatch');
}


#[test]
fn test_nft_factory_approve() {
    let nft_factory_address = deploy_contract();
    let erc721_mintable_dispatcher = IERC721MintableDispatcher {
        contract_address: nft_factory_address
    };
    let erc721_dispatcher = IERC721Dispatcher { contract_address: nft_factory_address };
    start_cheat_caller_address(nft_factory_address, OWNER());
    erc721_mintable_dispatcher.mint(1);
    erc721_dispatcher.approve(USER(), 1);
    stop_cheat_caller_address(nft_factory_address);
    assert(erc721_dispatcher.get_approved(1) == USER(), 'approved mismatch');
}

#[test]
#[should_panic]
fn test_nft_factory_approve_not_owner() {
    let nft_factory_address = deploy_contract();
    let erc721_mintable_dispatcher = IERC721MintableDispatcher {
        contract_address: nft_factory_address
    };
    let erc721_dispatcher = IERC721Dispatcher { contract_address: nft_factory_address };
    start_cheat_caller_address(nft_factory_address, USER());
    erc721_mintable_dispatcher.mint(1);
    stop_cheat_caller_address(nft_factory_address);
    start_cheat_caller_address(nft_factory_address, OWNER());
    erc721_dispatcher.approve(OWNER(), 1);
    stop_cheat_caller_address(nft_factory_address);
}

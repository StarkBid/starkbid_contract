use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, spy_events, EventSpyAssertionsTrait, EventSpy
};

use starkbid_contract::interfaces::{
    ICollectionFactoryDispatcher, ICollectionFactoryDispatcherTrait
};
use starknet::{ContractAddress, ClassHash, contract_address_const};

// Test constants
fn OWNER() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn USER1() -> ContractAddress {
    contract_address_const::<'user1'>()
}

fn USER2() -> ContractAddress {
    contract_address_const::<'user2'>()
}

fn ZERO_ADDRESS() -> ContractAddress {
    contract_address_const::<0>()
}

// Helper function to deploy factory
fn deploy_factory(owner: ContractAddress) -> ICollectionFactoryDispatcher {
    let contract = declare("NFTCollectionFactory").unwrap().contract_class();
    let mut constructor_calldata = array![owner.into()];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    ICollectionFactoryDispatcher { contract_address }
}

#[starknet::interface]
trait IMockCollection<TContractState> {
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
}


#[starknet::contract]
mod MockCollection {
    use starknet::ContractAddress;


    #[storage]
    struct Storage {
        owner: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
    }

    #[constructor]
    fn constructor(ref self: Storage, owner: ContractAddress) {
        self.owner.write(owner);
        self.name.write("MockCollection");
        self.symbol.write("MCK");
    }

    #[abi(embed_v0)]
    impl MockCollectionImpl of super::IMockCollection<Storage> {
        fn get_owner(self: @Storage) -> ContractAddress {
            self.owner.read()
        }
        fn name(self: @Storage) -> ByteArray {
            self.name.read()
        }
        fn symbol(self: @Storage) -> ByteArray {
            self.symbol.read()
        }
    }
}

// Helper function to get collection class hash
fn get_collection_class_hash() -> ClassHash {
    let contract = declare("MockCollection").unwrap().contract_class();
    contract.class_hash
}

#[test]
fn test_declare_collection_class() {
    let factory = deploy_factory(OWNER());
    let class_hash = get_collection_class_hash();

    start_cheat_caller_address(factory.contract_address, OWNER());

    let mut spy = spy_events();
    let result = factory.declare_collection_class(class_hash);

    assert!(result);
    assert!(factory.is_class_declared(class_hash));

    // Check event emission
    let events = spy.get_events().emitted_by(factory.contract_address);
    assert_eq!(events.len(), 1);

    let (from, event) = events.at(0);
    assert_eq!(*from, factory.contract_address);

    stop_cheat_caller_address(factory.contract_address);
}

#[test]
#[should_panic(expected: ('Unauthorized caller',))]
fn test_declare_collection_class_unauthorized() {
    let factory = deploy_factory(OWNER());
    let class_hash = get_collection_class_hash();

    start_cheat_caller_address(factory.contract_address, USER1());
    factory.declare_collection_class(class_hash);
}

#[test]
#[should_panic(expected: ('Class hash already declared',))]
fn test_declare_collection_class_already_declared() {
    let factory = deploy_factory(OWNER());
    let class_hash = get_collection_class_hash();

    start_cheat_caller_address(factory.contract_address, OWNER());
    factory.declare_collection_class(class_hash);
    // Try to declare again
    factory.declare_collection_class(class_hash);
}

#[test]
fn test_deploy_collection() {
    let factory = deploy_factory(OWNER());
    let class_hash = get_collection_class_hash();

    // First declare the class
    start_cheat_caller_address(factory.contract_address, OWNER());
    factory.declare_collection_class(class_hash);
    stop_cheat_caller_address(factory.contract_address);

    // Deploy collection
    start_cheat_caller_address(factory.contract_address, USER1());
    let mut spy = spy_events();
    let arguments: Array<felt252> = array![USER().into()];

    let (contract_address, collection_id) = factory.deploy_collection(class_hash, arguments);

    // Verify collection was registered
    assert_eq!(factory.get_collection_address(collection_id), contract_address);
    assert_eq!(factory.get_collection_creator(collection_id), USER());

    // Verify collection was initialized
    let collection = IMockCollectionDispatcher { contract_address };
    assert_eq!(collection.name(), "MockCollection");
    assert_eq!(collection.symbol(), "MTC");
    assert!(collection.get_owner(), USER());

    // Check event emission
    let events = spy.get_events().emitted_by(factory.contract_address);
    assert_eq!(events.len(), 1);

    stop_cheat_caller_address(factory.contract_address);
}


#[test]
#[should_panic(expected: ('Class hash not declared',))]
fn test_deploy_collection_class_not_declared() {
    let factory = deploy_factory(OWNER());
    let class_hash = get_collection_class_hash();
    let arguments: Array<felt252> = array![USER().into()];
    start_cheat_caller_address(factory.contract_address, USER1());
    factory.deploy_collection(class_hash, arguments);
}


#[test]
fn test_deploy_multiple_collections() {
    let factory = deploy_factory(OWNER());
    let class_hash = get_collection_class_hash();

    start_cheat_caller_address(factory.contract_address, OWNER());
    factory.declare_collection_class(class_hash);
    stop_cheat_caller_address(factory.contract_address);

    // Deploy collection 1
    start_cheat_caller_address(factory.contract_address, USER1());
    let mut spy = spy_events();
    let arguments: Array<felt252> = array![USER().into()];

    let (contract_address, collection_id) = factory.deploy_collection(class_hash, arguments);

    // Verify collection was registered
    assert_eq!(factory.get_collection_address(collection_id), contract_address);
    assert_eq!(factory.get_collection_creator(collection_id), USER());

    // Verify collection was initialized
    let collection = IMockCollectionDispatcher { contract_address };
    assert_eq!(collection.name(), "MockCollection");
    assert_eq!(collection.symbol(), "MTC");
    assert!(collection.get_owner(), USER());

    // Check event emission
    let events = spy.get_events().emitted_by(factory.contract_address);
    assert_eq!(events.len(), 1);

    stop_cheat_caller_address(factory.contract_address);
    start_cheat_caller_address(factory.contract_address, USER2());

    let arguments: Array<felt252> = array![USER2().into()];

    let (contract_address_2, collection_id_2) = factory.deploy_collection(class_hash, arguments);
    stop_cheat_caller_address(factory.contract_address);

    // Verify both collections exist and are different
    assert_ne!(contract_address, contract_address_2);
    assert_eq!(factory.get_collection_address(collection_id_2), contract_address_2);
    assert_eq!(factory.get_collection_creator(collection_id_2), USER2());
    // Verify collection was initialized
    let collection = IMockCollectionDispatcher { contract_address: contract_address_2 };
    assert_eq!(collection.name(), "MockCollection");
    assert_eq!(collection.symbol(), "MTC");
    assert!(collection.get_owner(), USER2());
}

#[test]
#[should_panic(expected: ('Collection not found',))]
fn test_get_collection_creator_not_found() {
    let factory = deploy_factory(OWNER());
    factory.get_collection_creator(999_u256);
}

#[test]
fn test_is_class_declared() {
    let factory = deploy_factory(OWNER());
    let class_hash = get_collection_class_hash();

    // Initially not declared
    assert!(!factory.is_class_declared(class_hash));

    // Declare class
    start_cheat_caller_address(factory.contract_address, OWNER());
    factory.declare_collection_class(class_hash);
    stop_cheat_caller_address(factory.contract_address);

    // Now should be declared
    assert!(factory.is_class_declared(class_hash));
}
#[test]
fn test_transfer_ownership() {
    let factory = deploy_factory(OWNER());

    start_cheat_caller_address(factory.contract_address, OWNER());
    let mut spy = spy_events();

    factory.transfer_ownership(USER1());

    assert_eq!(factory.get_factory_owner(), USER1());

    // Check event emission
    let events = spy.get_events().emitted_by(factory.contract_address);
    assert_eq!(events.len(), 1);

    stop_cheat_caller_address(factory.contract_address);
}

#[test]
#[should_panic(expected: ('Unauthorized caller',))]
fn test_transfer_ownership_unauthorized() {
    let factory = deploy_factory(OWNER());

    start_cheat_caller_address(factory.contract_address, USER1());
    factory.transfer_ownership(USER2());
}

#[test]
#[should_panic(expected: ('Zero address not allowed',))]
fn test_transfer_ownership_zero_address() {
    let factory = deploy_factory(OWNER());

    start_cheat_caller_address(factory.contract_address, OWNER());
    factory.transfer_ownership(ZERO_ADDRESS());
}

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address, spy_events, EventSpyAssertionsTrait, EventSpy
};

use starkbid_contract::interfaces::{
    ICollectionFactoryDispatcher, ICollectionFactoryDispatcherTrait
};
use starknet::{ContractAddress, ClassHash, contract_address_const, class_hash_const};

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

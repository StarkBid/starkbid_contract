#[starknet::contract]
mod CollectionFactory {
    use core::num::traits::Zero;
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address,
        deploy_syscall, SyscallResultTrait
    };
    use starknet::storage::{Map, StoragePathEntry};

    #[storage]
    struct Storage {
        // Factory owner
        owner: ContractAddress,
        
        // Mapping of collection_id => contract_address
        collections: Map<u256, ContractAddress>,
        
        // Mapping of collection_id => creator_address
        collection_creators: Map<u256, ContractAddress>,
        
        // Mapping of class_hash => is_declared
        declared_classes: Map<ClassHash, bool>,
        
        // Collection counter for generating unique IDs
        collection_counter: u256,
    }
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        CollectionCreated: CollectionCreated,
        ClassDeclared: ClassDeclared,
        OwnershipTransferred: OwnershipTransferred,
    }

    #[derive(Drop, starknet::Event)]
    struct CollectionCreated {
        #[key]
        collection_id: u256,
        #[key]
        creator: ContractAddress,
        contract_address: ContractAddress,
        class_hash: ClassHash,
        name: ByteArray,
        symbol: ByteArray,
        royalty_percentage: u16,
    }

    #[derive(Drop, starknet::Event)]
    struct ClassDeclared {
        #[key]
        class_hash: ClassHash,
        declared_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress,
    }
}
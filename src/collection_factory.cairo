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
}
#[starknet::contract]
mod CollectionFactory {
    use core::num::traits::Zero;
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address,
        deploy_syscall, SyscallResultTrait
    };
    use starknet::storage::{Map, StoragePathEntry};
    use crate::interfaces::icollection_factory::ICollectionFactory;

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

    mod Errors {
        const ZERO_ADDRESS: felt252 = 'Zero address not allowed';
        const CLASS_NOT_DECLARED: felt252 = 'Class hash not declared';
        const CLASS_ALREADY_DECLARED: felt252 = 'Class hash already declared';
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        assert(!owner.is_zero(), Errors::ZERO_ADDRESS);
        self.owner.write(owner);
        self.collection_counter.write(0);
    }

    #[abi(embed_v0)]
    impl CollectionFactoryImpl of ICollectionFactory<ContractState> {
        fn declare_collection_class(
            ref self: ContractState, 
            class_hash: ClassHash
        ) -> bool {
            self._assert_only_owner();
            
            // Check if class is already declared
            assert(!self.declared_classes.read(class_hash), Errors::CLASS_ALREADY_DECLARED);
            
            // Mark class as declared
            self.declared_classes.write(class_hash, true);
            // Emit event
            self.emit(ClassDeclared {
                class_hash,
                declared_by: get_caller_address()
            });
            
            true
        }
        fn deploy_collection(
            ref self: ContractState,
            class_hash: ClassHash,
            arguments: Array<felt252>,
        ) -> ContractAddress {
            self._assert_class_declared(class_hash);
            // Generate unique salt from blocktimestamp and block number
            let creator = get_caller_address();
            let salt = PoseidonTrait::new()
                .update_with(get_block_timestamp())
                .update_with(get_block_number())
                .finalize();
            
        
            let (contract_address, _) = deploy_syscall(
                class_hash,
                salt,
                arguments.span(),
                false
            ).unwrap();
            
            let collection_id = self.collection_counter.read();
            
            // Store collection mapping
            self.collections.write(collection_id, contract_address);
            self.collection_creators.write(collection_id, creator);
            // Increment collection counter
            self.collection_counter.write(collection_id + 1);
            
            // Emit CollectionCreated event
            self.emit(CollectionCreated {
                collection_id,
                creator,
                contract_address,
                class_hash 
            });
            
            contract_address
        }
    }
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'Only owner can call this function');
        }
        fn _assert_class_declared(ref self: ContractState, class_hash: ClassHash) {
            assert(self.declared_classes.read(class_hash), Errors::CLASS_NOT_DECLARED);
        }
    }
}
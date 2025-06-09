#[starknet::contract]
pub mod ERC721Metadata {
    use core::byte_array::ByteArray;
    use core::byte_array::ByteArrayTrait;
    use crate::interfaces::inft_metadata::{IERC721Metadata, IMetadataManager};
    use starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    #[derive(Drop, Serde, starknet::Store)]
    struct TokenMetadata {
        ipfs_hash: ByteArray, // IPFS hash stored as ByteArray
        metadata_hash: felt252, // Hash of metadata for integrity
        created_at: u64, // Timestamp
        updated_at: u64, // Last update timestamp
        admin: ContractAddress // Authorized admin for this token
    }

    #[derive(Drop, Serde, starknet::Store)]
    struct Attribute {
        trait_type: felt252,
        value: felt252,
    }

    #[storage]
    struct Storage {
        // ERC-721 basic info
        name: ByteArray,
        symbol: ByteArray,
        // Core metadata storage
        token_metadata: Map<u256, TokenMetadata>,
        // Attribute storage: token_id -> trait_type -> value
        token_attributes: Map<(u256, felt252), felt252>,
        // Attribute keys for enumeration: token_id -> array of trait_types
        token_attribute_keys: Map<u256, Vec<felt252>>,
        // IPFS gateway configuration
        ipfs_gateway: ByteArray,
        // Contract owner
        owner: ContractAddress,
        // Token existence mapping
        token_exists: Map<u256, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        MetadataUpdate: MetadataUpdate,
        AttributeAdded: AttributeAdded,
        AttributeRemoved: AttributeRemoved,
        GatewayUpdated: GatewayUpdated,
        AdminChanged: AdminChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct MetadataUpdate {
        token_id: u256,
        ipfs_hash: ByteArray,
        metadata_hash: felt252,
        updated_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct AttributeAdded {
        token_id: u256,
        trait_type: felt252,
        value: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct AttributeRemoved {
        token_id: u256,
        trait_type: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct GatewayUpdated {
        new_gateway: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    struct AdminChanged {
        token_id: u256,
        old_admin: ContractAddress,
        new_admin: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        owner: ContractAddress,
        initial_gateway: ByteArray,
    ) {
        self.name.write(name);
        self.symbol.write(symbol);
        self.owner.write(owner);
        self.ipfs_gateway.write(initial_gateway);
    }

    #[abi(embed_v0)]
    impl ERC721MetadataImpl of IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.symbol.read()
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            assert(self.token_exists.entry(token_id).read(), 'Token does not exist');
            let metadata = self.token_metadata.entry(token_id).read();
            self.construct_ipfs_url(metadata.ipfs_hash)
        }
    }

    #[abi(embed_v0)]
    impl MetadataManagerImpl of IMetadataManager<ContractState> {
        fn set_token_metadata(
            ref self: ContractState, token_id: u256, ipfs_hash: ByteArray, metadata_hash: felt252,
        ) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner can set metadata');
            assert(self.validate_ipfs_hash(ipfs_hash.clone()), 'Invalid IPFS hash');

            let current_time = get_block_timestamp();
            let metadata = TokenMetadata {
                ipfs_hash: ipfs_hash.clone(),
                metadata_hash,
                created_at: current_time,
                updated_at: current_time,
                admin: caller,
            };

            self.token_metadata.entry(token_id).write(metadata);
            self.token_exists.entry(token_id).write(true);

            self.emit(MetadataUpdate { token_id, ipfs_hash, metadata_hash, updated_by: caller });
        }

        fn get_token_metadata(self: @ContractState, token_id: u256) -> (ByteArray, felt252) {
            assert(self.token_exists.entry(token_id).read(), 'Token does not exist');
            let metadata = self.token_metadata.entry(token_id).read();
            (metadata.ipfs_hash, metadata.metadata_hash)
        }

        fn update_token_metadata(
            ref self: ContractState, token_id: u256, ipfs_hash: ByteArray, metadata_hash: felt252,
        ) {
            let caller = get_caller_address();
            assert(self.is_authorized(token_id, caller), 'Not authorized');
            assert(self.validate_ipfs_hash(ipfs_hash.clone()), 'Invalid IPFS hash');

            let mut metadata = self.token_metadata.entry(token_id).read();
            metadata.ipfs_hash = ipfs_hash.clone();
            metadata.metadata_hash = metadata_hash;
            metadata.updated_at = get_block_timestamp();

            self.token_metadata.entry(token_id).write(metadata);

            self.emit(MetadataUpdate { token_id, ipfs_hash, metadata_hash, updated_by: caller });
        }

        fn add_attribute(
            ref self: ContractState, token_id: u256, trait_type: felt252, value: felt252,
        ) {
            let caller = get_caller_address();
            assert(self.is_authorized(token_id, caller), 'Not authorized');
            assert(self.token_exists.entry(token_id).read(), 'Token does not exist');

            // Check if attribute already exists
            let existing_value = self.token_attributes.entry((token_id, trait_type)).read();
            if existing_value == 0 {
                // New attribute, add to keys array
                let mut keys = self.token_attribute_keys.entry(token_id);
                keys.append().write(trait_type);
            }

            self.token_attributes.entry((token_id, trait_type)).write(value);

            self.emit(AttributeAdded { token_id, trait_type, value });
        }

        fn remove_attribute(ref self: ContractState, token_id: u256, trait_type: felt252) {
            let caller = get_caller_address();
            assert(self.is_authorized(token_id, caller), 'Not authorized');
            assert(self.token_exists.entry(token_id).read(), 'Token does not exist');

            // Remove from storage
            self.token_attributes.entry((token_id, trait_type)).write(0);
            self.emit(AttributeRemoved { token_id, trait_type });
        }

        fn get_attribute(self: @ContractState, token_id: u256, trait_type: felt252) -> felt252 {
            assert(self.token_exists.entry(token_id).read(), 'Token does not exist');
            self.token_attributes.entry((token_id, trait_type)).read()
        }

        fn get_all_attributes(self: @ContractState, token_id: u256) -> Array<(felt252, felt252)> {
            assert(self.token_exists.entry(token_id).read(), 'Token does not exist');

            let keys = self.token_attribute_keys.entry(token_id);
            let mut attributes = array![];
            let mut i = 0;

            while i < keys.len() {
                let trait_type = keys.at(i).read();
                let value = self.get_attribute(token_id, trait_type);
                if value != 0 {
                    attributes.append((trait_type, value));
                }
                i += 1;
            };

            attributes
        }

        fn validate_metadata(self: @ContractState, token_id: u256) -> bool {
            if !self.token_exists.entry(token_id).read() {
                return false;
            }

            let metadata = self.token_metadata.entry(token_id).read();

            // Check if IPFS hash is valid
            if !self.validate_ipfs_hash(metadata.ipfs_hash) {
                return false;
            }

            true
        }

        fn validate_ipfs_hash(self: @ContractState, ipfs_hash: ByteArray) -> bool {
            // Basic validation - IPFS hash should not be zero
            // In a real implementation, you might want more sophisticated validation
            ipfs_hash != ""
        }

        fn construct_ipfs_url(self: @ContractState, ipfs_hash: ByteArray) -> ByteArray {
            let gateway: ByteArray = self.ipfs_gateway.read();
            let concatenator: ByteArray = "/";
            let url = ByteArrayTrait::concat(
                @ByteArrayTrait::concat(@gateway, @concatenator), @ipfs_hash,
            );
            url
        }

        fn get_gateway_url(self: @ContractState) -> ByteArray {
            self.ipfs_gateway.read()
        }

        fn set_gateway_url(ref self: ContractState, gateway_url: ByteArray) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner can set gateway');

            self.ipfs_gateway.write(gateway_url.clone());

            self.emit(GatewayUpdated { new_gateway: gateway_url });
        }

        fn is_authorized(self: @ContractState, token_id: u256, caller: ContractAddress) -> bool {
            if caller == self.owner.read() {
                return true;
            }

            if !self.token_exists.entry(token_id).read() {
                return false;
            }

            let metadata = self.token_metadata.entry(token_id).read();
            caller == metadata.admin
        }

        fn set_metadata_admin(ref self: ContractState, token_id: u256, admin: ContractAddress) {
            let caller = get_caller_address();
            assert(self.is_authorized(token_id, caller), 'Not authorized');

            let mut metadata = self.token_metadata.entry(token_id).read();
            let old_admin = metadata.admin;
            metadata.admin = admin;

            self.token_metadata.entry(token_id).write(metadata);

            self.emit(AdminChanged { token_id, old_admin, new_admin: admin });
        }

        fn get_metadata_admin(self: @ContractState, token_id: u256) -> ContractAddress {
            assert(self.token_exists.entry(token_id).read(), 'Token does not exist');
            let metadata = self.token_metadata.entry(token_id).read();
            metadata.admin
        }
    }

    // Additional helper functions
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _only_owner(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner allowed');
        }

        fn _token_exists(self: @ContractState, token_id: u256) -> bool {
            self.token_exists.entry(token_id).read()
        }

        fn _compute_metadata_hash(
            self: @ContractState, ipfs_hash: felt252, attributes: Array<(felt252, felt252)>,
        ) -> felt252 {
            // Simple hash computation for metadata integrity
            // In production, you might want to use a more sophisticated hashing algorithm
            let mut hash = ipfs_hash;
            let mut i = 0;
            while i < attributes.len() {
                let (trait_type, value) = *attributes.at(i);
                hash = hash + trait_type + value;
                i += 1;
            };
            hash
        }
    }
}

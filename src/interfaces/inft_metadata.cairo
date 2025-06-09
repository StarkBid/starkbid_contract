use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC721Metadata<TContractState> {
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn token_uri(self: @TContractState, token_id: u256) -> ByteArray;
}

#[starknet::interface]
pub trait IMetadataManager<TContractState> {
    // Core metadata functions
    fn set_token_metadata(
        ref self: TContractState, token_id: u256, ipfs_hash: ByteArray, metadata_hash: felt252,
    );
    fn get_token_metadata(self: @TContractState, token_id: u256) -> (ByteArray, felt252);
    fn update_token_metadata(
        ref self: TContractState, token_id: u256, ipfs_hash: ByteArray, metadata_hash: felt252,
    );

    // Attribute management
    fn add_attribute(ref self: TContractState, token_id: u256, trait_type: felt252, value: felt252);
    fn remove_attribute(ref self: TContractState, token_id: u256, trait_type: felt252);
    fn get_attribute(self: @TContractState, token_id: u256, trait_type: felt252) -> felt252;
    fn get_all_attributes(self: @TContractState, token_id: u256) -> Array<(felt252, felt252)>;

    // Validation functions
    fn validate_metadata(self: @TContractState, token_id: u256) -> bool;
    fn validate_ipfs_hash(self: @TContractState, ipfs_hash: ByteArray) -> bool;

    // URL construction
    fn construct_ipfs_url(self: @TContractState, ipfs_hash: ByteArray) -> ByteArray;
    fn get_gateway_url(self: @TContractState) -> ByteArray;
    fn set_gateway_url(ref self: TContractState, gateway_url: ByteArray);

    // Authorization
    fn is_authorized(self: @TContractState, token_id: u256, caller: ContractAddress) -> bool;
    fn set_metadata_admin(ref self: TContractState, token_id: u256, admin: ContractAddress);
    fn get_metadata_admin(self: @TContractState, token_id: u256) -> ContractAddress;
}

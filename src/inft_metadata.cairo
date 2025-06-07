use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC721Metadata<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn token_uri(self: @TContractState, token_id: u256) -> Array<felt252>;
}

#[starknet::interface]
pub trait IMetadataManager<TContractState> {
    // Core metadata functions
    fn set_token_metadata(
        ref self: TContractState, token_id: u256, ipfs_hash: felt252, metadata_hash: felt252,
    );
    fn get_token_metadata(self: @TContractState, token_id: u256) -> (felt252, felt252);
    fn update_token_metadata(
        ref self: TContractState, token_id: u256, ipfs_hash: felt252, metadata_hash: felt252,
    );

    // Attribute management
    fn add_attribute(ref self: TContractState, token_id: u256, trait_type: felt252, value: felt252);
    fn remove_attribute(ref self: TContractState, token_id: u256, trait_type: felt252);
    fn get_attribute(self: @TContractState, token_id: u256, trait_type: felt252) -> felt252;
    fn get_all_attributes(self: @TContractState, token_id: u256) -> Array<(felt252, felt252)>;

    // Validation functions
    fn validate_metadata(self: @TContractState, token_id: u256) -> bool;
    fn validate_ipfs_hash(self: @TContractState, ipfs_hash: felt252) -> bool;

    // URL construction
    fn construct_ipfs_url(self: @TContractState, ipfs_hash: felt252) -> Array<felt252>;
    fn get_gateway_url(self: @TContractState) -> Array<felt252>;
    fn set_gateway_url(ref self: TContractState, gateway_url: Array<felt252>);

    // Authorization
    fn is_authorized(self: @TContractState, token_id: u256, caller: ContractAddress) -> bool;
    fn set_metadata_admin(ref self: TContractState, token_id: u256, admin: ContractAddress);
    fn get_metadata_admin(self: @TContractState, token_id: u256) -> ContractAddress;
}

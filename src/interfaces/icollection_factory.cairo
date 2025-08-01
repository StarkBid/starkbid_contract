use starknet::{ContractAddress, ClassHash};
#[starknet::interface]
pub trait ICollectionFactory<TContractState> {
    fn declare_collection_class(ref self: TContractState, class_hash: ClassHash) -> bool;

    fn deploy_collection(
        ref self: TContractState, class_hash: ClassHash, arguments: Array<felt252>,
    ) -> (ContractAddress, u256);

    fn get_collection_address(self: @TContractState, collection_id: u256) -> ContractAddress;

    fn get_collection_creator(self: @TContractState, collection_id: u256) -> ContractAddress;

    fn is_class_declared(self: @TContractState, class_hash: ClassHash) -> bool;

    fn get_factory_owner(self: @TContractState) -> ContractAddress;

    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);

    // Access control
    fn grant_this_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn revoke_this_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn renounce_this_role(ref self: TContractState, role: felt252);
    fn has_this_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
    fn get_this_role_admin(self: @TContractState, role: felt252) -> felt252;
    fn get_this_role_member_count(self: @TContractState, role: felt252) -> u256;

    fn pause_factory(ref self: TContractState);
    fn unpause_factory(ref self: TContractState);
    fn is_factory_paused(self: @TContractState) -> bool;
}

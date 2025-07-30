use starknet::{ContractAddress, ClassHash};
#[starknet::interface]
trait ICollectionFactory<TContractState> {
    fn declare_collection_class(ref self: TContractState, class_hash: ClassHash) -> bool;

    fn deploy_collection(
        ref self: TContractState, class_hash: ClassHash, arguments: Array<felt252>,
    ) -> (ContractAddress, u256); 

    fn get_collection_address(self: @TContractState, collection_id: u256) -> ContractAddress;

    fn get_collection_creator(self: @TContractState, collection_id: u256) -> ContractAddress;

    fn is_class_declared(self: @TContractState, class_hash: ClassHash) -> bool;

    fn get_factory_owner(self: @TContractState) -> ContractAddress;

    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
}

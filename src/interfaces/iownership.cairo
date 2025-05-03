use starknet::ContractAddress;

#[starknet::interface]
pub trait IOwnership<TContractState> {
    fn transfer_asset_ownership(
        ref self: TContractState,
        asset: ContractAddress,
        token_id: u256,
        new_owner: ContractAddress,
    );
    fn get_asset_owner(
        self: @TContractState, asset: ContractAddress, token_id: u256,
    ) -> ContractAddress;
    fn get_asset_ownership_history(
        self: @TContractState, asset: ContractAddress, token_id: u256,
    ) -> Array<ContractAddress>;
}

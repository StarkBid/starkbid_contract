use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC721<TContractState> {
    fn transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256
    );
    
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    
    fn approve(
        ref self: TContractState,
        to: ContractAddress,
        token_id: u256
    );
}

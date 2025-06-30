use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;

    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;

    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

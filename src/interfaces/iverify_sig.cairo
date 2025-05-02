use starknet::ContractAddress;

#[starknet::interface]
pub trait IVerifySignature<TContractState> {
    fn verify_signature(
        ref self: TContractState, 
        claimed_address: ContractAddress,
        message: felt252,
        signature_r: felt252,
        signature_s: felt252
    ) -> bool;
    fn get_caller_address(self: @TContractState) -> ContractAddress;
}
use starknet::ContractAddress;

#[starknet::interface]
pub trait IHelloStarknet<TContractState> {
    fn increase_balance(ref self: TContractState, amount: felt252);
    fn get_balance(self: @TContractState) -> felt252;
    fn validate_wallet(self: @TContractState, address: ContractAddress) -> bool;
}

#[starknet::contract]
mod HelloStarknet {
    use core::num::traits::Zero;
    use starknet::ContractAddress;

    #[storage]
    struct Storage {
        balance: felt252, 
    }

    #[abi(embed_v0)]
    impl HelloStarknetImpl of super::IHelloStarknet<ContractState> {
        fn increase_balance(ref self: ContractState, amount: felt252) {
            assert(amount != 0, 'Amount cannot be 0');
            self.balance.write(self.balance.read() + amount);
        }

        fn get_balance(self: @ContractState) -> felt252 {
            self.balance.read()
        }

        fn validate_wallet(self: @ContractState, address: ContractAddress) -> bool {
            if address.is_zero() {
                return false;
            }
            true
        }
    }
}
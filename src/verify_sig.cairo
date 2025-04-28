use starknet::ContractAddress;

#[starknet::interface]
pub trait IVerifySignature<TContractState> {
    fn verify_signature(
        ref self: TContractState, 
        claimed_address: ContractAddress,
        message: Span<felt252>,
        signature_r: felt252,
        signature_s: felt252
    ) -> bool;
    fn get_nonce(self: @TContractState, user_address: ContractAddress) -> felt252;
    fn get_caller_address(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod VerifySignature {
    use core::num::traits::Zero;
use starknet::{
        get_caller_address, 
        get_block_timestamp,
        contract_address::ContractAddress,
        storage::Map,
    };
    use core::pedersen;
    use core::ecdsa::check_ecdsa_signature;
    use core::hash::{HashStateTrait};

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AuthenticationSuccess: AuthenticationSuccess,
        AuthenticationFailure: AuthenticationFailure,
    }

    #[derive(Drop, starknet::Event)]
    struct AuthenticationSuccess {
        user_address: ContractAddress,
        timestamp: u64
    }

    #[derive(Drop, starknet::Event)]
    struct AuthenticationFailure {
        claimed_address: ContractAddress,
        timestamp: u64
    }

    #[storage]
    struct Storage {
        user_nonce: Map<ContractAddress, felt252>,
    }

    #[abi(embed_v0)]
    pub impl VerifySignatureImpl of super::IVerifySignature<ContractState> {
        fn verify_signature(
            ref self: ContractState, 
            claimed_address: ContractAddress,
            message: Span<felt252>,
            signature_r: felt252,
            signature_s: felt252
        ) -> bool {
            assert(claimed_address.is_non_zero(), 'Invalid user address');
            let timestamp: u64 = get_block_timestamp();
            let current_nonce = self.user_nonce.read(claimed_address);
            
            // Hash the message array and nonce
            let mut state = pedersen::PedersenTrait::new(0);
            let mut i = 0;
            while i < message.len() {
                state = state.update(*message.at(i));
                i += 1;
            };
            state = state.update(current_nonce);
            let message_hash = state.finalize();
            
            // Verify the signature
            let is_valid = check_ecdsa_signature(
                message_hash,
                claimed_address.into(),
                signature_r,
                signature_s
            );
            
            if is_valid {
                self.user_nonce.write(claimed_address, current_nonce + 1);
                self.emit(AuthenticationSuccess { 
                    user_address: claimed_address, 
                    timestamp 
                });
                true
            } else {
                self.emit(AuthenticationFailure { 
                    claimed_address, 
                    timestamp 
                });
                false
            }
        }

        fn get_nonce(self: @ContractState, user_address: ContractAddress) -> felt252 {
            self.user_nonce.read(user_address)
        }
        
        fn get_caller_address(self: @ContractState) -> ContractAddress {
            get_caller_address()
        }
    }
}
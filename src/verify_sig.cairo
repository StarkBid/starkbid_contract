use starknet::ContractAddress;

#[starknet::contract]
pub mod VerifySignature {
    use core::num::traits::Zero;
    use starknet::{
        get_caller_address, 
        get_block_timestamp,
        contract_address::ContractAddress,
    };
    use core::ecdsa::check_ecdsa_signature;
    use crate::interfaces::iverify_sig::IVerifySignature;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Success: AuthenticationSuccess,
        Failure: AuthenticationFailure,
    }

    #[derive(Drop, starknet::Event)]
    struct AuthenticationSuccess {
        #[key]
        user_address: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct AuthenticationFailure {
        #[key]
        claimed_address: ContractAddress,
        timestamp: u64,
    }

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    pub impl VerifySignatureImpl of IVerifySignature<ContractState> {
        fn verify_signature(
            ref self: ContractState, 
            claimed_address: ContractAddress,
            message: felt252,
            signature_r: felt252,
            signature_s: felt252
        ) -> bool {
            assert(claimed_address.is_non_zero(), 'Invalid user address');
            let timestamp: u64 = get_block_timestamp();

            // Verify the signature
            let is_valid = check_ecdsa_signature(
                message,
                claimed_address.into(),
                signature_r,
                signature_s
            );

            println!("is valid {}", is_valid);
            
            if is_valid {
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
        
        fn get_caller_address(self: @ContractState) -> ContractAddress {
            get_caller_address()
        }
    }
}
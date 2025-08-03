// Interface definition
#[starknet::interface]
pub trait IPausable<TContractState> {
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn paused(self: @TContractState) -> bool;
}

// src/components/pausable.cairo
#[starknet::component]
pub mod PausableComponent {
    use core::num::traits::Zero;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        paused: bool,
        pauser: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Paused: Paused,
        Unpaused: Unpaused,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Paused {
        #[key]
        pub account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unpaused {
        #[key]
        pub account: ContractAddress,
    }


    pub mod Errors {
        pub const ALREADY_PAUSED: felt252 = 'Contract is already paused';
        pub const NOT_PAUSED: felt252 = 'Contract is not paused';
        pub const UNAUTHORIZED: felt252 = 'Caller is not the pauser';
        pub const ZERO_ADDRESS: felt252 = 'Zero address not allowed';
        pub const PAUSED: felt252 = 'Contract is paused';
    }

    // #[embeddable_as(PausableComponent)]
    #[abi(embed_v0)]
    pub impl Pausable<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
        // impl Pausable: PausableComponent::HasComponent<TContractState>,
    > of super::IPausable<ComponentState<TContractState>> {
        fn pause(ref self: ComponentState<TContractState>) {
            self._assert_only_pauser();
            self._assert_not_paused();

            self.paused.write(true);
            self.emit(Paused { account: get_caller_address() });
        }

        fn unpause(ref self: ComponentState<TContractState>) {
            self._assert_only_pauser();
            self._assert_paused();

            self.paused.write(false);
            self.emit(Unpaused { account: get_caller_address() });
        }

        fn paused(self: @ComponentState<TContractState>) -> bool {
            self.paused.read()
        }
    }

    #[abi(per_item)]
    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, pauser: ContractAddress) {
            assert(!pauser.is_zero(), Errors::ZERO_ADDRESS);
            self.paused.write(false);
            self.pauser.write(pauser);
        }

        fn _assert_paused(self: @ComponentState<TContractState>) {
            assert(self.paused.read(), Errors::NOT_PAUSED);
        }

        fn _assert_not_paused(self: @ComponentState<TContractState>) {
            assert(!self.paused.read(), Errors::PAUSED);
        }

        fn _assert_only_pauser(self: @ComponentState<TContractState>) {
            let caller = get_caller_address();
            let pauser = self.pauser.read();
            assert(caller == pauser, Errors::UNAUTHORIZED);
        }

        fn _when_not_paused(self: @ComponentState<TContractState>) {
            self._assert_not_paused();
        }

        fn _when_paused(self: @ComponentState<TContractState>) {
            self._assert_paused();
        }
    }
}


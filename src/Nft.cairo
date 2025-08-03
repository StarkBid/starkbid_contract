#[starknet::contract]
pub mod NftFactory {
    use crate::components::pausable::PausableComponent::InternalTrait;
    use crate::components::pausable::PausableComponent::Pausable;
    use crate::components::pausable::{PausableComponent, IPausable};
    use crate::interfaces::ierc721::IERC721Mintable;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::{ERC721Component, ERC721HooksEmptyImpl};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    // Pausable component
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);


    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;


    #[storage]
    struct Storage {
        owner: ContractAddress,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray
    ) {
        self.owner.write(owner);
        self.erc721.initializer(name, symbol, base_uri);
        self.pausable.initializer(pauser: owner);
    }

    #[abi(embed_v0)]
    impl NFTFactoryImpl of IERC721Mintable<ContractState> {
        fn mint(ref self: ContractState, token_id: u256) {
            self.pausable._assert_not_paused();
            self.erc721.mint(get_caller_address(), token_id);
        }

        fn burn(ref self: ContractState, token_id: u256) {
            let owner = self.erc721.owner_of(token_id);
            assert(owner == get_caller_address(), 'not owner');
            self.erc721.burn(token_id);
        }
    }
    #[abi(embed_v0)]
    impl PausableImpl of IPausable<ContractState> {
        fn pause(ref self: ContractState) {
            // Delegate to component
            self.pausable.pause();
        }

        fn unpause(ref self: ContractState) {
            self.pausable.unpause();
        }

        fn paused(self: @ContractState) -> bool {
            self.pausable.paused()
        }
    }
}

#[starknet::contract]
pub mod Ownership {
    use core::starknet::storage::{
        Map, MutableVecTrait, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
        Vec, VecTrait,
    };
    use crate::interfaces::iownership::IOwnership;
    use starknet::event::EventEmitter;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    #[storage]
    pub struct Storage {
        asset_owner: Map<(ContractAddress, u256), ContractAddress>, // (asset, token_id) -> owner
        asset_ownership_history: Map<
            (ContractAddress, u256), Vec<ContractAddress>,
        > // (asset, token_id) -> list(owners)
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnershipTransferred: OwnershipTransferred,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        asset: ContractAddress,
        token_id: u256,
        previous_owner: ContractAddress,
        new_owner: ContractAddress,
        timestamp: u64,
    }
    #[abi(embed_v0)]
    pub impl OwnershipImpl of IOwnership<ContractState> {
        //CORE FUNCTIONALITIES
        // @notice Transfer the ownership of an asset to another contract address
        /// @param asset Address of the NFT contract
        /// @param token_id token ID being listed
        /// @param new_owner the new owner of the asset
        fn transfer_asset_ownership(
            ref self: ContractState,
            asset: ContractAddress,
            token_id: u256,
            new_owner: ContractAddress,
        ) {
            let caller = get_caller_address();
            let asset_owner = self.asset_owner.entry((asset, token_id));
            let previous_owner = asset_owner.read();
            // Validate that the caller is the asset owner
            assert(caller == asset_owner.read(), 'Invalid Owner');
            assert(previous_owner != new_owner, 'Cannot transfer asset to self');
            asset_owner.write(new_owner);

            // add the new owner to the ownership history
            self.asset_ownership_history.entry((asset, token_id)).append().write(new_owner);
            // emit the OwnershipTransferred event
            self
                .emit(
                    OwnershipTransferred {
                        asset,
                        token_id,
                        previous_owner,
                        new_owner,
                        timestamp: get_block_timestamp(),
                    },
                );
        }
        // @notice Retrieve the owner of an asset
        /// @param asset Address of the NFT contract
        /// @param token_id token ID being listed
        /// @return owner The ContractAddress of the asset owner
        fn get_asset_owner(
            self: @ContractState, asset: ContractAddress, token_id: u256,
        ) -> ContractAddress {
            self.asset_owner.entry((asset, token_id)).read()
        }
        // @notice Retrieve the ownership history of an asset
        /// @param asset Address of the NFT contract
        /// @param token_id token ID being listed
        /// @return array<owner> A list of ContractAddresses signifying the ownership history of the
        /// asset
        fn get_asset_ownership_history(
            self: @ContractState, asset: ContractAddress, token_id: u256,
        ) -> Array<ContractAddress> {
            let history = self.asset_ownership_history.entry((asset, token_id));
            let mut array_history: Array<ContractAddress> = array![];
            for index in 0..history.len() {
                array_history.append(history.at(index).read());
            };
            array_history
        }
    }
}

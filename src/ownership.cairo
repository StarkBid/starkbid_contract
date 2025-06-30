#[starknet::contract]
pub mod Ownership {
    use core::num::traits::Zero;
    use core::starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use crate::interfaces::iownership::IOwnership;
    use starknet::event::EventEmitter;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address,};


    #[storage]
    pub struct Storage {
        asset_owner: Map<(ContractAddress, u256), ContractAddress>, // (asset, token_id) -> owner
        asset_ownership_history: Map<
            (ContractAddress, u256), Vec<ContractAddress>,
        >, // (asset, token_id) -> list(owners)
        // Royalty Storage
        royalty_settings: Map<
            (ContractAddress, u256), Vec<(ContractAddress, u8)>,
        >, // (asset, token_id) -> Vec[(recipient, percentage_share)]
        pending_withdrawals: Map<ContractAddress, u256>, // recipient_address -> amount_due
        platform_fee_percentage_bp: u8, // Platform fee in basis points (e.g., 500 for 5%)
        platform_fee_recipient: ContractAddress,
        contract_owner: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnershipTransferred: OwnershipTransferred,
        RoyaltySettingsUpdated: RoyaltySettingsUpdated,
        PlatformFeeInfoUpdated: PlatformFeeInfoUpdated,
        RoyaltiesDistributed: RoyaltiesDistributed,
        RoyaltyPortionCredited: RoyaltyPortionCredited,
        PlatformFeeCredited: PlatformFeeCredited,
        Withdrawal: WithdrawalEvent
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

    #[derive(Drop, starknet::Event)]
    struct RoyaltySettingsUpdated {
        #[key]
        asset: ContractAddress,
        #[key]
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PlatformFeeInfoUpdated {
        recipient: ContractAddress,
        fee_bp: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct RoyaltiesDistributed {
        #[key]
        asset: ContractAddress,
        #[key]
        token_id: u256,
        sale_price: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RoyaltyPortionCredited {
        recipient: ContractAddress,
        #[key]
        asset: ContractAddress,
        #[key]
        token_id: u256,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PlatformFeeCredited {
        recipient: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct WithdrawalEvent {
        recipient: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_platform_fee_recipient: ContractAddress,
        initial_platform_fee_bp: u8,
    ) {
        self.contract_owner.write(get_caller_address());
        self.platform_fee_recipient.write(initial_platform_fee_recipient);
        self.platform_fee_percentage_bp.write(initial_platform_fee_bp);
        assert(initial_platform_fee_bp <= 100_u8, 'Fee bp too high',);
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
            let asset_owner_entry = self.asset_owner.entry((asset, token_id));
            let previous_owner = asset_owner_entry.read();

            // Allow initial assignment if previous_owner is zero
            if previous_owner
                .is_zero() { // This is the first time ownership is being set for this asset.
            // No need to check caller against previous_owner if previous_owner is zero.
            } else {
                assert(caller == previous_owner, 'Invalid Owner');
            }
            assert(previous_owner != new_owner, 'Cannot transfer asset to self');
            assert(!new_owner.is_zero(), 'New owner cannot be zero');

            asset_owner_entry.write(new_owner);

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
            let history_vec = self.asset_ownership_history.entry((asset, token_id));
            let mut history_array = ArrayTrait::new();
            let len = history_vec.len();
            let mut i = 0;
            while i < len {
                history_array.append(history_vec.at(i).read());
                i += 1;
            };
            history_array
        }

        fn set_royalty_settings(
            ref self: ContractState,
            asset: ContractAddress,
            token_id: u256,
            recipients_config: Array<(ContractAddress, u8)>,
        ) {
            let caller = get_caller_address();
            let current_owner = self.asset_owner.entry((asset, token_id)).read();
            assert(caller == current_owner, 'Caller not asset owner');
            assert(!current_owner.is_zero(), 'Asset has no owner');

            let mut total_percentage: u16 = 0;
            let mut i = 0;
            let len = recipients_config.len();
            while i < len {
                let tuple_value = recipients_config.at(i);
                // Access tuple elements
                let (recipient, percentage) = tuple_value;
                assert(!recipient.is_zero(), 'Recipient cannot be zero');
                assert(*percentage > 0_u8 && *percentage <= 100_u8, 'Invalid percentage');
                total_percentage += (*percentage).into();
                i += 1;
            };
            assert(total_percentage <= 100_u16, 'Total percentage > 100');

            let mut storage_vec_path = self.royalty_settings.entry((asset, token_id));

            // Add new settings from the input array
            let mut j = 0;
            while j < len.into() {
                storage_vec_path.at(j).write(*recipients_config.at(i));
                j += 1;
            };

            self.emit(RoyaltySettingsUpdated { asset, token_id });
        }

        fn update_royalty_recipient(
            ref self: ContractState,
            asset: ContractAddress,
            token_id: u256,
            old_recipient: ContractAddress,
            new_recipient: ContractAddress,
        ) {
            let caller = get_caller_address();
            let current_owner = self.asset_owner.entry((asset, token_id)).read();
            assert(caller == current_owner, 'Caller not asset owner');
            assert(!current_owner.is_zero(), 'Asset has no owner');
            assert(!new_recipient.is_zero(), 'New recipient cannot be zero');

            let mut storage_vec = self.royalty_settings.entry((asset, token_id));
            let mut found = false;
            let mut i = 0;
            let len = storage_vec.len();
            while i < len {
                let mut recipient_info_path = storage_vec.at(i);
                let (current_addr, percentage) = recipient_info_path.read();
                if current_addr == old_recipient {
                    recipient_info_path.write((new_recipient, percentage));
                    found = true;
                    break;
                }
                i += 1;
            };
            assert(found, 'Old recipient not found');
            self.emit(RoyaltySettingsUpdated { asset, token_id });
        }

        fn set_platform_fee_info(
            ref self: ContractState, recipient: ContractAddress, fee_percentage: u8,
        ) {
            let caller = get_caller_address();
            assert(caller == self.contract_owner.read(), 'Caller not contract owner');
            assert!(!recipient.is_zero(), "Platform recipient cannot be zero");
            assert(fee_percentage <= 100, 'Platform fee % > 100');

            self.platform_fee_recipient.write(recipient);
            self.platform_fee_percentage_bp.write(fee_percentage); // Storing as direct percentage
            self.emit(PlatformFeeInfoUpdated { recipient, fee_bp: fee_percentage });
        }

        // Royalty Distribution
        fn distribute_sale_proceeds(
            ref self: ContractState, asset: ContractAddress, token_id: u256, sale_price: u256,
        ) {
            assert(sale_price > 0, 'Sale price must be positive');
            let platform_fee_recipient_addr = self.platform_fee_recipient.read();
            let platform_fee_percent = self.platform_fee_percentage_bp.read();

            let platform_fee_amount = sale_price * platform_fee_percent.into() / 100;
            let remaining_after_platform_fee = sale_price - platform_fee_amount;

            if platform_fee_amount > 0 {
                let current_platform_balance = self
                    .pending_withdrawals
                    .read(platform_fee_recipient_addr);
                self
                    .pending_withdrawals
                    .write(
                        platform_fee_recipient_addr, current_platform_balance + platform_fee_amount,
                    );
                self
                    .emit(
                        PlatformFeeCredited {
                            recipient: platform_fee_recipient_addr, amount: platform_fee_amount,
                        },
                    );
            }

            let royalty_configs_vec = self.royalty_settings.entry((asset, token_id));
            let mut i = 0;
            let len = royalty_configs_vec.len();
            while i < len {
                let (recipient, percentage) = royalty_configs_vec.at(i).read();
                let royalty_amount = remaining_after_platform_fee * percentage.into() / 100;

                if royalty_amount > 0 {
                    let current_recipient_balance = self.pending_withdrawals.read(recipient);
                    self
                        .pending_withdrawals
                        .write(recipient, current_recipient_balance + royalty_amount);
                    self
                        .emit(
                            RoyaltyPortionCredited {
                                recipient, asset, token_id, amount: royalty_amount,
                            },
                        );
                }
                i += 1;
            };
            self.emit(RoyaltiesDistributed { asset, token_id, sale_price });
        }

        // Withdrawal
        fn withdraw_funds(ref self: ContractState) {
            let caller = get_caller_address();
            let amount_to_withdraw = self.pending_withdrawals.read(caller);
            assert(amount_to_withdraw > 0, 'No funds to withdraw');

            self.pending_withdrawals.write(caller, 0);
            self.emit(WithdrawalEvent { recipient: caller, amount: amount_to_withdraw });
        }

        // View Functions
        fn get_pending_withdrawal_amount(self: @ContractState, recipient: ContractAddress) -> u256 {
            self.pending_withdrawals.read(recipient)
        }

        fn get_royalty_settings(
            self: @ContractState, asset: ContractAddress, token_id: u256,
        ) -> Array<(ContractAddress, u8)> {
            let storage_vec = self.royalty_settings.entry((asset, token_id));
            let mut result_array = ArrayTrait::new();
            let mut i = 0;
            let len = storage_vec.len();
            while i < len {
                result_array.append(storage_vec.at(i).read());
                i += 1;
            };
            result_array
        }

        fn get_platform_fee_info(self: @ContractState) -> (ContractAddress, u8) {
            (self.platform_fee_recipient.read(), self.platform_fee_percentage_bp.read())
        }

        fn get_contract_owner(self: @ContractState) -> ContractAddress {
            self.contract_owner.read()
        }
    }
}

#[starknet::contract]
pub mod Ownership {
    use core::num::traits::Zero;
    use core::starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };

    use crate::constants::{DEFAULT_ADMIN_ROLE, MARKETPLACE_ADMIN_ROLE, PAUSER_ROLE};
    use crate::interfaces::iownership::IOwnership;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::event::EventEmitter;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address,};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;


    #[storage]
    pub struct Storage {
        asset_owner: Map<(ContractAddress, u256), ContractAddress>,
        asset_ownership_history: Map<(ContractAddress, u256), Vec<ContractAddress>,>,
        royalty_settings: Map<(ContractAddress, u256), Vec<(ContractAddress, u8)>,>,
        pending_withdrawals: Map<ContractAddress, u256>,
        platform_fee_percentage_bp: u8,
        platform_fee_recipient: ContractAddress,
        contract_owner: ContractAddress,
        role_members: Map<felt252, Vec<ContractAddress>>, // role -> Vec of members
        member_active: Map<(felt252, ContractAddress), bool>, // Track active members
        system_paused: bool,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
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
        Withdrawal: WithdrawalEvent,
        SystemPaused: SystemPaused,
        SystemUnpaused: SystemUnpaused,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
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

    #[derive(Drop, starknet::Event)]
    struct SystemPaused {
        paused_by: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct SystemUnpaused {
        unpaused_by: ContractAddress,
        timestamp: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_platform_fee_recipient: ContractAddress,
        initial_platform_fee_bp: u8,
        admin: ContractAddress
    ) {
        self.contract_owner.write(admin);
        self.platform_fee_recipient.write(initial_platform_fee_recipient);
        self.platform_fee_percentage_bp.write(initial_platform_fee_bp);
        assert(initial_platform_fee_bp <= 100_u8, 'Fee bp too high',);

        // Initialize RBAC
        self.system_paused.write(false);
        self.accesscontrol.initializer();

        // Set up role hierarchy
        self.accesscontrol.set_role_admin(MARKETPLACE_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        self.accesscontrol.set_role_admin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        self.accesscontrol.set_role_admin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

        // Grant initial roles
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, admin);
        self.accesscontrol._grant_role(MARKETPLACE_ADMIN_ROLE, admin);
        self.accesscontrol._grant_role(PAUSER_ROLE, admin);

        // Initialize role member tracking
        self.role_members.entry(DEFAULT_ADMIN_ROLE).append().write(admin);
        self.role_members.entry(MARKETPLACE_ADMIN_ROLE).append().write(admin);

        self.member_active.write((DEFAULT_ADMIN_ROLE, admin), true);
        self.member_active.write((MARKETPLACE_ADMIN_ROLE, admin), true);
    }


    #[abi(embed_v0)]
    pub impl OwnershipImpl of IOwnership<ContractState> {
        fn transfer_asset_ownership(
            ref self: ContractState,
            asset: ContractAddress,
            token_id: u256,
            new_owner: ContractAddress,
        ) {
            let caller = get_caller_address();
            let asset_owner_entry = self.asset_owner.entry((asset, token_id));
            let previous_owner = asset_owner_entry.read();

            if previous_owner
                .is_zero() {} else {
                    assert(caller == previous_owner, 'Invalid Owner');
                }
            assert(previous_owner != new_owner, 'Cannot transfer asset to self');
            assert(!new_owner.is_zero(), 'New owner cannot be zero');

            asset_owner_entry.write(new_owner);

            self.asset_ownership_history.entry((asset, token_id)).append().write(new_owner);
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
        fn get_asset_owner(
            self: @ContractState, asset: ContractAddress, token_id: u256,
        ) -> ContractAddress {
            self.asset_owner.entry((asset, token_id)).read()
        }
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
                let (recipient, percentage) = tuple_value;
                assert(!recipient.is_zero(), 'Recipient cannot be zero');
                assert(*percentage > 0_u8 && *percentage <= 100_u8, 'Invalid percentage');
                total_percentage += (*percentage).into();
                i += 1;
            };
            assert(total_percentage <= 100_u16, 'Total percentage > 100');

            let mut storage_vec_path = self.royalty_settings.entry((asset, token_id));
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
            self.accesscontrol.assert_only_role(MARKETPLACE_ADMIN_ROLE);
            assert!(!recipient.is_zero(), "Platform recipient cannot be zero");
            assert(fee_percentage <= 100, 'Platform fee % > 100');

            self.platform_fee_recipient.write(recipient);
            self.platform_fee_percentage_bp.write(fee_percentage);
            self.emit(PlatformFeeInfoUpdated { recipient, fee_bp: fee_percentage });
        }

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

        fn withdraw_funds(ref self: ContractState) {
            let caller = get_caller_address();
            let amount_to_withdraw = self.pending_withdrawals.read(caller);
            assert(amount_to_withdraw > 0, 'No funds to withdraw');

            self.pending_withdrawals.write(caller, 0);
            self.emit(WithdrawalEvent { recipient: caller, amount: amount_to_withdraw });
        }

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

        fn grant_this_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            assert(!account.is_zero(), 'Zero address');
            let already_has_role = self.accesscontrol.has_role(role, account);
            self.accesscontrol.grant_role(role, account);
            if !already_has_role {
                self._add_role_member(role, account);
            }
        }

        fn revoke_this_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            if role == DEFAULT_ADMIN_ROLE {
                self._ensure_not_last_admin(account);
            }
            self.accesscontrol.revoke_role(role, account);
            self._remove_role_member(role, account);
        }

        fn renounce_this_role(ref self: ContractState, role: felt252) {
            let caller = get_caller_address();
            if role == DEFAULT_ADMIN_ROLE {
                self._ensure_not_last_admin(caller);
            }
            self.accesscontrol.renounce_role(role, caller);
            self._remove_role_member(role, caller);
        }

        fn has_this_role(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            self.accesscontrol.has_role(role, account)
        }

        fn get_this_role_admin(self: @ContractState, role: felt252) -> felt252 {
            self.accesscontrol.get_role_admin(role)
        }

        fn get_this_role_member_count(self: @ContractState, role: felt252) -> u256 {
            let role_vec = self.role_members.entry(role);
            let len = role_vec.len();
            let mut active_count = 0;
            let mut i = 0;

            while i < len {
                let member = role_vec.at(i).read();
                if self.member_active.read((role, member))
                    && self.accesscontrol.has_role(role, member) {
                    active_count += 1;
                }
                i += 1;
            };

            active_count.into()
        }

        fn pause_system(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.system_paused.write(true);
            self
                .emit(
                    SystemPaused {
                        paused_by: get_caller_address(), timestamp: get_block_timestamp()
                    }
                );
        }

        fn unpause_system(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.system_paused.write(false);
            self
                .emit(
                    SystemUnpaused {
                        unpaused_by: get_caller_address(), timestamp: get_block_timestamp()
                    }
                );
        }

        fn is_system_paused(self: @ContractState) -> bool {
            self.system_paused.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Adds a member to role tracking
        fn _add_role_member(ref self: ContractState, role: felt252, account: ContractAddress) {
            // Check if member already exists in role members
            if !self._is_member_in_role(role, account) {
                self.role_members.entry(role).append().write(account);
            }
            // Mark as active
            self.member_active.write((role, account), true);
        }

        /// Removes a member from role tracking
        fn _remove_role_member(ref self: ContractState, role: felt252, account: ContractAddress) {
            self.member_active.write((role, account), false);
        }

        /// Check if an account is in a role's member list
        fn _is_member_in_role(
            self: @ContractState, role: felt252, account: ContractAddress
        ) -> bool {
            self.member_active.read((role, account)) && self.accesscontrol.has_role(role, account)
        }

        /// Ensures that removing an account from a role won't leave zero admins
        fn _ensure_not_last_admin(ref self: ContractState, account: ContractAddress) {
            let admin_count = self.get_this_role_member_count(DEFAULT_ADMIN_ROLE);
            assert(admin_count > 1, 'Cannot remove last admin');
            assert(self.accesscontrol.has_role(DEFAULT_ADMIN_ROLE, account), 'Account not admin');
        }

        /// Safety check for critical operations
        fn _assert_admin_or_higher(ref self: ContractState, required_role: felt252) {
            let caller = get_caller_address();
            let has_required_role = self.accesscontrol.has_role(required_role, caller);
            let is_admin = self.accesscontrol.has_role(DEFAULT_ADMIN_ROLE, caller);
            assert(has_required_role || is_admin, 'Insufficient permissions');
        }
    }
}

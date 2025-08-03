#[starknet::contract]
pub mod Offer {
    use core::num::traits::Zero;
    use core::traits::TryInto;
    use crate::components::pausable::PausableComponent::InternalTrait;
    use crate::components::pausable::PausableComponent::Pausable;
    use crate::components::pausable::{PausableComponent, IPausable};

    use crate::constants::{DEFAULT_ADMIN_ROLE, MARKETPLACE_ADMIN_ROLE, PAUSER_ROLE};
    use crate::interfaces::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use crate::interfaces::ierc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use crate::interfaces::ioffer::{IOffer, Offer as OfferStruct, OfferStatus};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;

    use starknet::event::EventEmitter;
    use starknet::storage::{Map, StoragePathEntry, MutableVecTrait, Vec, VecTrait};
    use starknet::syscalls::send_message_to_l1_syscall;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    // Pausable component
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);

    const ZERO_ADDRESS: felt252 = 0;
    const BASIS_POINTS: u256 = 10000;


    #[storage]
    struct Storage {
        offers: Map<u256, OfferStruct>,
        next_offer_id: u256,
        royalties: Map<ContractAddress, (ContractAddress, u256)>,
        // RBAC member tracking
        role_members: Map<felt252, Vec<ContractAddress>>, // role -> Vec of members
        member_active: Map<(felt252, ContractAddress), bool>, // Track active members
        // Offer system pause state
        offers_paused: bool,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OfferCreated: OfferCreated,
        OfferAccepted: OfferAccepted,
        OfferCancelled: OfferCancelled,
        RoyaltyPaid: RoyaltyPaid,
        OffersPaused: OffersPaused,
        OffersUnpaused: OffersUnpaused,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct OfferCreated {
        #[key]
        offer_id: u256,
        nft_contract: ContractAddress,
        token_id: u256,
        offerer: ContractAddress,
        payment_token: ContractAddress,
        offer_amount: u256,
        expiration: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct OfferAccepted {
        #[key]
        offer_id: u256,
        acceptor: ContractAddress,
        payment_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct OfferCancelled {
        #[key]
        offer_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RoyaltyPaid {
        #[key]
        nft_contract: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct OffersPaused {
        paused_by: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct OffersUnpaused {
        unpaused_by: ContractAddress,
        timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        assert(!admin.is_zero(), 'address is zero');
        self.next_offer_id.write(1.into());
        self.offers_paused.write(false);

        // Initialize RBAC
        self.accesscontrol.initializer();

        // Set up role hierarchy - DEFAULT_ADMIN_ROLE manages all other roles
        self.accesscontrol.set_role_admin(MARKETPLACE_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        self.accesscontrol.set_role_admin(PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        self.accesscontrol.set_role_admin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);

        // Grant initial roles
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, admin);
        self.accesscontrol._grant_role(MARKETPLACE_ADMIN_ROLE, admin);

        // Initialize role member tracking for BOTH roles
        self.role_members.entry(DEFAULT_ADMIN_ROLE).append().write(admin);
        self.role_members.entry(MARKETPLACE_ADMIN_ROLE).append().write(admin);

        // Mark both as active
        self.member_active.write((DEFAULT_ADMIN_ROLE, admin), true);
        self.member_active.write((MARKETPLACE_ADMIN_ROLE, admin), true);
        let deployer = get_caller_address();
        self.pausable.initializer(deployer);
    }

    #[abi(embed_v0)]
    impl OfferImpl of IOffer<ContractState> {
        fn create_offer(
            ref self: ContractState,
            nft_contract: ContractAddress,
            token_id: u256,
            payment_token: ContractAddress,
            offer_amount: u256,
            expiration: u64,
        ) -> u256 {
            self.pausable._assert_not_paused();
            assert(!self.offers_paused.read(), 'Offers Paused');

            assert(offer_amount > 0.into(), 'Invalid offer amount');
            assert(expiration > get_block_timestamp(), 'Invalid expiration');

            let caller = get_caller_address();
            let offer_id = self.next_offer_id.read();
            let (royalty_recipient, royalty_percentage) = self.get_royalty_info(nft_contract);

            let offer = OfferStruct {
                id: offer_id,
                nft_contract,
                token_id,
                offerer: caller,
                payment_token,
                offer_amount,
                expiration,
                status: OfferStatus::Active(()),
                royalty_recipient,
                royalty_percentage,
            };

            if !payment_token.is_zero() {
                let erc20 = IERC20Dispatcher { contract_address: payment_token };
                let success = erc20.transfer_from(caller, get_contract_address(), offer_amount);
                assert(success, 'ERC20 transfer failed');
            }

            self.offers.write(offer_id, offer);
            self.next_offer_id.write(offer_id + 1.into());

            self
                .emit(
                    OfferCreated {
                        offer_id,
                        nft_contract,
                        token_id,
                        offerer: caller,
                        payment_token,
                        offer_amount,
                        expiration,
                    }
                );

            offer_id
        }

        fn accept_offer(ref self: ContractState, offer_id: u256) {
            self.pausable._assert_not_paused();
            assert(!self.offers_paused.read(), 'Offers Paused');
            let offer = self.offers.read(offer_id);
            let caller = get_caller_address();

            assert(offer.status == OfferStatus::Active(()), 'Offer not active');
            assert(get_block_timestamp() <= offer.expiration, 'Offer expired');

            let royalty_amount = if offer.royalty_percentage > 0.into() {
                (offer.offer_amount * offer.royalty_percentage) / BASIS_POINTS
            } else {
                0.into()
            };

            let payment_amount = offer.offer_amount - royalty_amount;

            let nft = IERC721Dispatcher { contract_address: offer.nft_contract };
            assert(nft.owner_of(offer.token_id) == caller, 'Not NFT owner');

            let updated_offer = OfferStruct { status: OfferStatus::Accepted(()), ..offer };
            self.offers.write(offer_id, updated_offer);

            nft.transfer_from(caller, offer.offerer, offer.token_id);

            if !offer.payment_token.is_zero() {
                let erc20 = IERC20Dispatcher { contract_address: offer.payment_token };
                let success = erc20.transfer(caller, payment_amount);
                assert(success, 'Payment transfer failed');
            } else {
                let _ = caller;
                let _ = payment_amount;
            }

            if royalty_amount > 0.into() {
                if !offer.payment_token.is_zero() {
                    let erc20 = IERC20Dispatcher { contract_address: offer.payment_token };
                    let success = erc20.transfer(offer.royalty_recipient, royalty_amount);
                    assert(success, 'Royalty transfer failed');
                } else {
                    let _ = offer.royalty_recipient;
                    let _ = royalty_amount;
                }

                self
                    .emit(
                        RoyaltyPaid {
                            nft_contract: offer.nft_contract,
                            recipient: offer.royalty_recipient,
                            amount: royalty_amount,
                        }
                    );
            }

            self.emit(OfferAccepted { offer_id, acceptor: caller, payment_amount, });
        }

        fn cancel_offer(ref self: ContractState, offer_id: u256) {
            self.pausable._assert_not_paused();
            let offer = self.offers.read(offer_id);
            let caller = get_caller_address();

            assert(caller == offer.offerer, 'Not offer creator');
            assert(offer.status == OfferStatus::Active(()), 'Offer not active');
            let updated_offer = OfferStruct { status: OfferStatus::Cancelled(()), ..offer };
            self.offers.write(offer_id, updated_offer);
            let offer_for_payment = offer;
            if !offer_for_payment.payment_token.is_zero() {
                let erc20 = IERC20Dispatcher { contract_address: offer_for_payment.payment_token };
                let success = erc20.transfer(caller, offer_for_payment.offer_amount);
                assert(success, 'Refund transfer failed');
            }

            self.emit(OfferCancelled { offer_id });
        }

        fn get_offer(self: @ContractState, offer_id: u256) -> OfferStruct {
            self.offers.read(offer_id)
        }

        fn get_offer_status(self: @ContractState, offer_id: u256) -> OfferStatus {
            self.offers.read(offer_id).status
        }

        fn is_offer_active(self: @ContractState, offer_id: u256) -> bool {
            let offer = self.offers.read(offer_id);
            offer.status == OfferStatus::Active(()) && get_block_timestamp() <= offer.expiration
        }

        fn set_royalty_info(
            ref self: ContractState,
            nft_contract: ContractAddress,
            recipient: ContractAddress,
            percentage: u256
        ) {
            self.accesscontrol.assert_only_role(MARKETPLACE_ADMIN_ROLE);
            assert(percentage <= BASIS_POINTS, 'Invalid percentage');
            self.royalties.write(nft_contract, (recipient, percentage));
        }

        fn get_royalty_info(
            self: @ContractState, nft_contract: ContractAddress
        ) -> (ContractAddress, u256) {
            self.royalties.read(nft_contract)
        }

        fn grant_this_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            assert(!account.is_zero(), 'account address is zero');

            // Check if user already has role before granting
            let already_has_role = self.accesscontrol.has_role(role, account);

            self.accesscontrol.grant_role(role, account);

            // Only add to tracking if they didn't already have the role
            if !already_has_role {
                self._add_role_member(role, account);
            }
        }

        fn revoke_this_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            // Safety check for critical roles
            if role == DEFAULT_ADMIN_ROLE {
                self._ensure_not_last_admin(account);
            }

            self.accesscontrol.revoke_role(role, account);
            self._remove_role_member(role, account);
        }

        fn renounce_this_role(ref self: ContractState, role: felt252) {
            let caller = get_caller_address();

            // Safety check for critical roles
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
                // Count only if marked active AND actually has the role
                if self.member_active.read((role, member))
                    && self.accesscontrol.has_role(role, member) {
                    active_count += 1;
                }
                i += 1;
            };

            active_count.into()
        }

        fn pause_offers(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.offers_paused.write(true);

            self
                .emit(
                    OffersPaused {
                        paused_by: get_caller_address(), timestamp: get_block_timestamp()
                    }
                );
        }

        fn unpause_offers(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.offers_paused.write(false);

            self
                .emit(
                    OffersUnpaused {
                        unpaused_by: get_caller_address(), timestamp: get_block_timestamp()
                    }
                );
        }

        fn are_offers_paused(self: @ContractState) -> bool {
            self.offers_paused.read()
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

        /// Batch role operations with safety checks
        fn _safe_batch_revoke_roles(
            ref self: ContractState, roles: Array<felt252>, account: ContractAddress
        ) {
            let mut i = 0;
            let len = roles.len();

            // First pass: check if any critical roles would be left empty
            while i < len {
                let role = *roles.at(i);
                if role == DEFAULT_ADMIN_ROLE {
                    self._ensure_not_last_admin(account);
                }
                i += 1;
            };

            // Second pass: safely revoke all roles
            i = 0;
            while i < len {
                let role = *roles.at(i);
                if self.accesscontrol.has_role(role, account) {
                    self.accesscontrol.revoke_role(role, account);
                    self._remove_role_member(role, account);
                }
                i += 1;
            };
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

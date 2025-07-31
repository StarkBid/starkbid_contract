#[starknet::contract]
pub mod Marketplace {
    use core::num::traits::Zero;
    use core::starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, MutableVecTrait, Vec, VecTrait,
        StoragePathEntry
    };
    use crate::constants::{DEFAULT_ADMIN_ROLE, MARKETPLACE_ADMIN_ROLE, PAUSER_ROLE};
    use crate::interfaces::imarketplace::{IMarketplace, Listing, ListingStatus, ListingType};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        listings: Map<u256, Listing>,
        next_listing_id: u256,
        active_listing_count: u256,
        role_members: Map<felt252, Vec<ContractAddress>>, // role -> Vec of members
        member_active: Map<(felt252, ContractAddress), bool>,
        marketplace_paused: bool,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ListingCreated: ListingCreated,
        ListingSold: ListingSold,
        ListingCancelled: ListingCancelled,
        BidPlaced: BidPlaced,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct ListingCreated {
        #[key]
        listing_id: u256,
        seller: ContractAddress,
        asset_contract: ContractAddress,
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ListingSold {
        #[key]
        listing_id: u256,
        buyer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ListingCancelled {
        #[key]
        listing_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct BidPlaced {
        #[key]
        listing_id: u256,
        bidder: ContractAddress,
        bid_amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.next_listing_id.write(1.into());
        self.active_listing_count.write(0.into());
        self.marketplace_paused.write(false);

        // Initialize RBAC
        self.accesscontrol.initializer();

        // Set up role hierarchy
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
    }

    #[abi(embed_v0)]
    pub impl MarketplaceImpl of IMarketplace<ContractState> {
        fn create_listing(
            ref self: ContractState,
            asset_contract: ContractAddress,
            token_id: u256,
            price: u256,
            listing_type: ListingType,
            duration: u64,
        ) -> u256 {
            assert(!self.marketplace_paused.read(), 'Marketplace paused');
            let caller = get_caller_address();
            let current_time = get_block_timestamp();
            let listing_id = self.next_listing_id.read();

            assert(price > 0.into(), 'Invalid price');
            assert(duration > 0, 'Invalid duration');

            let listing = Listing {
                id: listing_id,
                seller: caller,
                asset_contract,
                token_id,
                price,
                start_time: current_time,
                end_time: current_time + duration,
                listing_type,
                status: ListingStatus::Active(()),
                highest_bidder: caller,
                highest_bid: 0.into(),
            };

            self.listings.write(listing_id, listing);
            self.next_listing_id.write(listing_id + 1.into());
            self.active_listing_count.write(self.active_listing_count.read() + 1.into());

            self.emit(ListingCreated { listing_id, seller: caller, asset_contract, token_id });
            listing_id
        }

        fn purchase_listing(ref self: ContractState, listing_id: u256) {
            assert(!self.marketplace_paused.read(), 'Marketplace paused');
            let caller = get_caller_address();
            let mut listing = self.listings.read(listing_id);

            assert(listing.status == ListingStatus::Active(()), 'Inactive');
            assert(listing.listing_type == ListingType::FixedPrice(()), 'Not fixed price');
            assert(get_block_timestamp() <= listing.end_time, 'Expired');

            listing.status = ListingStatus::Sold(());
            self.listings.write(listing_id, listing);
            self.active_listing_count.write(self.active_listing_count.read() - 1.into());

            self.emit(ListingSold { listing_id, buyer: caller });
        }


        fn cancel_listing(ref self: ContractState, listing_id: u256) {
            let caller = get_caller_address();
            let mut listing = self.listings.read(listing_id);

            assert(caller == listing.seller, 'Unauthorized');
            assert(listing.status == ListingStatus::Active(()), 'Inactive');

            listing.status = ListingStatus::Cancelled(());
            self.listings.write(listing_id, listing);
            self.active_listing_count.write(self.active_listing_count.read() - 1.into());

            self.emit(ListingCancelled { listing_id });
        }

        fn update_listing_price(ref self: ContractState, listing_id: u256, new_price: u256) {
            let caller = get_caller_address();
            let mut listing = self.listings.read(listing_id);
            assert(caller == listing.seller, 'Not the seller');
            assert(listing.status == ListingStatus::Active(()), 'Listing is not active');
            assert(
                listing.listing_type == ListingType::FixedPrice(()), 'Not a fixed price listing',
            );
            assert(new_price > 0.into(), 'Price must be greater than 0');
            listing.price = new_price;
            self.listings.write(listing_id, listing);
        }

        fn place_bid(ref self: ContractState, listing_id: u256, bid_amount: u256) {
            let caller = get_caller_address();
            let mut listing = self.listings.read(listing_id);

            assert(listing.status == ListingStatus::Active(()), 'Inactive');
            assert(listing.listing_type == ListingType::Auction(()), 'Not auction');
            assert(get_block_timestamp() <= listing.end_time, 'Auction ended');
            assert(bid_amount > listing.highest_bid, 'Low bid');

            listing.highest_bidder = caller;
            listing.highest_bid = bid_amount;
            self.listings.write(listing_id, listing);

            self.emit(BidPlaced { listing_id, bidder: caller, bid_amount });
        }

        fn finalize_auction(ref self: ContractState, listing_id: u256) {
            let mut listing = self.listings.read(listing_id);

            assert(listing.status == ListingStatus::Active(()), 'Inactive');
            assert(listing.listing_type == ListingType::Auction(()), 'Not auction');
            assert(get_block_timestamp() > listing.end_time, 'Auction active');

            self.active_listing_count.write(self.active_listing_count.read() - 1.into());

            if listing.highest_bid > 0.into() {
                listing.status = ListingStatus::Sold(());
                self.emit(ListingSold { listing_id, buyer: listing.highest_bidder });
            } else {
                listing.status = ListingStatus::Cancelled(());
                self.emit(ListingCancelled { listing_id });
            }
            self.listings.write(listing_id, listing);
        }

        fn batch_create_listings(
            ref self: ContractState,
            asset_contracts: Array<ContractAddress>,
            token_ids: Array<u256>,
            prices: Array<u256>,
            listing_types: Array<ListingType>,
            durations: Array<u64>,
        ) -> Array<u256> {
            let len = asset_contracts.len();
            assert(token_ids.len() == len, 'Length mismatch');
            assert(prices.len() == len, 'Length mismatch');
            assert(listing_types.len() == len, 'Length mismatch');
            assert(durations.len() == len, 'Length mismatch');

            let mut ids = ArrayTrait::new();
            let mut i: u32 = 0;
            while i < len {
                ids
                    .append(
                        self
                            .create_listing(
                                *asset_contracts.at(i),
                                *token_ids.at(i),
                                *prices.at(i),
                                *listing_types.at(i),
                                *durations.at(i),
                            ),
                    );
                i += 1;
            };
            ids
        }

        fn batch_cancel_listings(ref self: ContractState, listing_ids: Array<u256>) {
            let len = listing_ids.len();
            let mut i: u32 = 0;
            while i < len {
                self.cancel_listing(*listing_ids.at(i));
                i += 1;
            }
        }

        fn batch_finalize_auctions(ref self: ContractState, listing_ids: Array<u256>) {
            let current_time = get_block_timestamp();
            let len = listing_ids.len();
            let mut i: u32 = 0;
            while i < len {
                let listing_id = *listing_ids.at(i);
                let listing = self.listings.read(listing_id);
                if listing.end_time < current_time {
                    self.finalize_auction(listing_id);
                }
                i += 1;
            }
        }


        fn get_listing(self: @ContractState, listing_id: u256) -> Listing {
            self.listings.read(listing_id)
        }


        fn get_listing_status(self: @ContractState, listing_id: u256) -> ListingStatus {
            self.listings.read(listing_id).status
        }

        fn is_listing_active(self: @ContractState, listing_id: u256) -> bool {
            let listing = self.listings.read(listing_id);
            listing.status == ListingStatus::Active(()) && get_block_timestamp() <= listing.end_time
        }

        fn pause_marketplace(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.marketplace_paused.write(true);
        }

        fn unpause_marketplace(ref self: ContractState) {
            self.accesscontrol.assert_only_role(PAUSER_ROLE);
            self.marketplace_paused.write(false);
        }

        fn grant_this_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            assert(!account.is_zero(), 'account is zero address');
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
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Adds a member to role tracking
        fn _add_role_member(ref self: ContractState, role: felt252, account: ContractAddress) {
            // Check if member already exists role members
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
}

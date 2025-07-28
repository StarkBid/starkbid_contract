#[starknet::contract]
pub mod Marketplace {
    use core::starknet::storage::{Map, StoragePointerWriteAccess};
    use crate::interfaces::imarketplace::{IMarketplace, Listing, ListingStatus, ListingType};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

    #[storage]
    struct Storage {
        listings: Map<u256, Listing>,
        next_listing_id: u256,
        active_listing_count: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ListingCreated: ListingCreated,
        ListingSold: ListingSold,
        ListingCancelled: ListingCancelled,
        BidPlaced: BidPlaced,
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
    fn constructor(ref self: ContractState) {
        self.next_listing_id.write(1.into());
        self.active_listing_count.write(0.into());
    }

    #[abi(embed_v0)]
    pub impl MarketplaceImpl of IMarketplace<ContractState> {
        //CORE FUNCTIONALITIES

        /// @notice Creates a new marketplace listing
        /// @param asset_contract Address of the NFT contract
        /// @param token_id token ID being listed
        /// @param price Listing price
        /// @param listing_type FixedPrice or Auction
        /// @param duration Duration of listing in seconds
        /// @return listing_id The ID of the newly created listing
        fn create_listing(
            ref self: ContractState,
            asset_contract: ContractAddress,
            token_id: u256,
            price: u256,
            listing_type: ListingType,
            duration: u64,
        ) -> u256 {
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


        /// @notice Purchases a fixed-price listing
        /// @param listing_id The ID of the listing to purchase
        /// Note: Transfers NFT to buyer and marks listing as sold
        fn purchase_listing(ref self: ContractState, listing_id: u256) {
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


        /// @notice Cancels an active listing
        /// @param listing_id The ID of the listing to cancel
        /// Note: Only listing seller can cancel
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

        /// @notice Updates price of a fixed-price listing
        /// @param listing_id The ID of the listing to update
        /// @param new_price New listing price
        /// Note: Only seller can update price
        fn update_listing_price(ref self: ContractState, listing_id: u256, new_price: u256) {
            let caller = get_caller_address();
            let mut listing = self.listings.read(listing_id);

            // Validate permissions and state
            assert(caller == listing.seller, 'Not the seller');
            assert(listing.status == ListingStatus::Active(()), 'Listing is not active');
            assert(
                listing.listing_type == ListingType::FixedPrice(()), 'Not a fixed price listing',
            );
            assert(new_price > 0.into(), 'Price must be greater than 0');

            // Update price
            listing.price = new_price;
            self.listings.write(listing_id, listing);
        }

        // Auction functionality

        /// @notice Places a bid on an auction listing
        /// @param listing_id The ID of the auction listing
        /// @param bid_amount The bid amount (in wei)
        /// Note: Bid must be higher than current highest bid
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


        /// @notice Finalizes an ended auction
        /// @param listing_id The ID of the auction to finalize
        /// Note: Transfers NFT to highest bidder if any bids were placed
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

        // Batch operations for gas optimization
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


        // View functions

        /// @notice Gets full listing details
        /// @param listing_id The ID of the listing to query
        /// @return Listing struct with all details
        fn get_listing(self: @ContractState, listing_id: u256) -> Listing {
            self.listings.read(listing_id)
        }


        // @notice Gets current status of a listing
        /// @param listing_id The ID of the listing to check
        /// @return Current listing status (Active/Sold/Cancelled)
        fn get_listing_status(self: @ContractState, listing_id: u256) -> ListingStatus {
            self.listings.read(listing_id).status
        }


        /// @notice Checks if listing is active and not expired
        /// @param listing_id The ID of the listing to check
        /// @return true if listing is active and not expired
        fn is_listing_active(self: @ContractState, listing_id: u256) -> bool {
            let listing = self.listings.read(listing_id);
            listing.status == ListingStatus::Active(()) && get_block_timestamp() <= listing.end_time
        }
    }
}

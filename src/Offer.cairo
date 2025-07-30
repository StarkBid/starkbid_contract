#[starknet::contract]
pub mod Offer {
    use core::num::traits::Zero;
    use core::starknet::storage::Map;
    use core::traits::TryInto;

    use crate::interfaces::ierc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use crate::interfaces::ierc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use crate::interfaces::ioffer::{IOffer, Offer as OfferStruct, OfferStatus};

    use starknet::event::EventEmitter;
    use starknet::syscalls::send_message_to_l1_syscall;
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};

    const ZERO_ADDRESS: felt252 = 0;
    const BASIS_POINTS: u256 = 10000;

    #[storage]
    struct Storage {
        offers: Map<u256, OfferStruct>,
        next_offer_id: u256,
        royalties: Map<ContractAddress, (ContractAddress, u256)>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OfferCreated: OfferCreated,
        OfferAccepted: OfferAccepted,
        OfferCancelled: OfferCancelled,
        RoyaltyPaid: RoyaltyPaid,
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

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.next_offer_id.write(1.into());
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
            assert(percentage <= BASIS_POINTS, 'Invalid percentage');
            self.royalties.write(nft_contract, (recipient, percentage));
        }

        fn get_royalty_info(
            self: @ContractState, nft_contract: ContractAddress
        ) -> (ContractAddress, u256) {
            self.royalties.read(nft_contract)
        }
    }
}

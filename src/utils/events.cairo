use snforge_std::{assert_event_emitted, start_cheat_caller_address, stop_cheat_caller_address};
use starkbid_contract::src::nft::{initialize_nft, transfer_nft};
use starkbid_contract::contracts::marketplace::{create_listing, buy_listing, place_bid};

#[test]
fn test_mint_event() {
    let nft_contract = init_nft_contract();
    let token_id = 1;
    let metadata = 12345;

    start_cheat_caller_address(nft_contract.contract_address, seller());
    nft_contract.initialize_nft(token_id, seller(), metadata);
    stop_cheat_caller_address(nft_contract.contract_address);

    assert_event_emitted!(MintEvent, |event| {
        event.minter == seller() && event.token_id == token_id && event.metadata == metadata
    });
}

#[test]
fn test_transfer_event() {
    let nft_contract = init_nft_contract();
    let token_id = 1;

    start_cheat_caller_address(nft_contract.contract_address, seller());
    nft_contract.transfer_nft(token_id, buyer());
    stop_cheat_caller_address(nft_contract.contract_address);

    assert_event_emitted!(TransferEvent, |event| {
        event.from == seller() && event.to == buyer() && event.token_id == token_id
    });
}

#[test]
fn test_buy_event() {
    let marketplace_contract = init_marketplace_contract();
    let listing_id = 1;
    let token_id = 1;
    let price = 1000;

    start_cheat_caller_address(marketplace_contract.contract_address, seller());
    marketplace_contract.create_listing(listing_id, seller(), token_id, price);
    stop_cheat_caller_address(marketplace_contract.contract_address);

    start_cheat_caller_address(marketplace_contract.contract_address, buyer());
    marketplace_contract.buy_listing(listing_id, buyer());
    stop_cheat_caller_address(marketplace_contract.contract_address);

    assert_event_emitted!(BuyEvent, |event| {
        event.buyer == buyer() && event.seller == seller() && event.token_id == token_id && event.price == price
    });
}
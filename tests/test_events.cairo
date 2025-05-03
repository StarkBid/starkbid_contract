use snforge_std::{assert_event_emitted, start_cheat_caller_address, stop_cheat_caller_address};
use starkbid_contract::src::nft::{initialize_nft, transfer_nft, get_metadata, get_bulk_metadata};
use starkbid_contract::contracts::marketplace::{create_listing, buy_listing, place_bid};

#[test]
fn test_mint_event() {
    let nft_contract = init_nft_contract();
    let token_id = 1;
    let metadata = Metadata {
        name: "Collectible Name",
        description: "Description",
        creator: "Creator",
        image_uri: "https://image.uri",
    };

    start_cheat_caller_address(nft_contract.contract_address, seller());
    nft_contract.initialize_nft(token_id, seller(), metadata);
    stop_cheat_caller_address(nft_contract.contract_address);

    assert_event_emitted!(MintEvent, |event| {
        event.minter == seller() && event.token_id == token_id
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

#[test]
fn test_get_metadata() {
    let nft_contract = init_nft_contract();
    let token_id = 1;
    let metadata = Metadata {
        name: "Collectible Name",
        description: "Description",
        creator: "Creator",
        image_uri: "https://image.uri",
    };

    start_cheat_caller_address(nft_contract.contract_address, seller());
    nft_contract.initialize_nft(token_id, seller(), metadata);
    stop_cheat_caller_address(nft_contract.contract_address);

    let retrieved_metadata = nft_contract.get_metadata(token_id);
    assert(
        retrieved_metadata == metadata,
        "Metadata does not match the expected values",
    );
}

#[test]
fn test_get_bulk_metadata() {
    let nft_contract = init_nft_contract();
    let token_ids = [1, 2, 3];
    let metadata_list = [
        Metadata {
            name: "Collectible 1",
            description: "Description 1",
            creator: "Creator 1",
            image_uri: "https://image1.uri",
        },
        Metadata {
            name: "Collectible 2",
            description: "Description 2",
            creator: "Creator 2",
            image_uri: "https://image2.uri",
        },
        Metadata {
            name: "Collectible 3",
            description: "Description 3",
            creator: "Creator 3",
            image_uri: "https://image3.uri",
        },
    ];

    start_cheat_caller_address(nft_contract.contract_address, seller());
    for i in 0..token_ids.len() {
        nft_contract.initialize_nft(token_ids[i], seller(), metadata_list[i]);
    }
    stop_cheat_caller_address(nft_contract.contract_address);

    let retrieved_metadata_list = nft_contract.get_bulk_metadata(token_ids);
    assert(
        retrieved_metadata_list == metadata_list,
        "Bulk metadata does not match the expected values",
    );
}
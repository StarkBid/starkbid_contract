struct NFT {
    id: felt,
    owner: felt,
    metadata: felt,
}


#[storage]
struct Storage {
    nfts: Dict<felt, NFT>,
}


#[external]
fn initialize_nft(ref self: Storage, id: felt, owner: felt, metadata: felt) {
    let nft = NFT { id: id, owner: owner, metadata: metadata };

    self.nfts.write(id, nft);
}


#[external]
fn get_nft(ref self: Storage, id: felt) -> NFT {
    let nft = self.nfts.read(id);
    return nft;
}

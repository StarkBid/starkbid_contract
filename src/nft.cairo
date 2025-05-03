use starknet::ContractAddress;

struct NFT {
    id: felt,
    owner: felt,
    metadata: felt,
}

struct Metadata {
    name: felt,
    description: felt,
    creator: felt,
    image_uri: felt,
}

#[storage]
struct Storage {
    nfts: Dict<felt, NFT>,
    metadata: Dict<felt, Metadata>, 
}

#[external]
fn initialize_nft(ref self: Storage, id: felt, owner: felt, metadata: Metadata) {
    let nft = NFT { id: id, owner: owner, metadata: 0 };  
    self.nfts.write(id, nft);
    self.metadata.write(id, metadata);  
}

#[external]
fn get_nft(ref self: Storage, id: felt) -> NFT {
    let nft = self.nfts.read(id);
    return nft;
}

#[view]
fn get_metadata(self: @Storage, id: felt) -> Metadata {
    self.metadata.read(id)  
}

#[view]
fn get_bulk_metadata(self: @Storage, ids: Array<felt>) -> Array<Metadata> {
    let mut result = ArrayTrait::new();
    for id in ids {
        result.append(self.metadata.read(*id)); 
    }
    result
}
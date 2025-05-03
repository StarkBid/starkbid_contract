use starknet::ContractAddress;
use starknet::get_block_timestamp;
use starknet::crypto::verify_signature;

#[storage]
struct Storage {
    nonces: Map<ContractAddress, u256>,
    expiration_times: Map<ContractAddress, u64>, 
    authenticated_users: Map<ContractAddress, bool>, 
}

#[event]
#[derive(Drop, starknet::Event)]
enum AuthEvent {
    AuthenticationAttempt: AuthenticationAttempt,
    AuthenticationSuccess: AuthenticationSuccess,
    AuthenticationFailure: AuthenticationFailure,
}

#[derive(Drop, starknet::Event)]
struct AuthenticationAttempt {
    #[key]
    wallet: ContractAddress,
    nonce: u256,
}

#[derive(Drop, starknet::Event)]
struct AuthenticationSuccess {
    #[key]
    wallet: ContractAddress,
}

#[derive(Drop, starknet::Event)]
struct AuthenticationFailure {
    #[key]
    wallet: ContractAddress,
    reason: felt,
}

#[external]
fn generate_challenge(ref self: Storage, wallet: ContractAddress) -> u256 {
    let current_time = get_block_timestamp();
    let nonce = current_time.into();  
    let expiration_time = current_time + 300; 

    self.nonces.write(wallet, nonce);
    self.expiration_times.write(wallet, expiration_time);

    self.emit(AuthEvent::AuthenticationAttempt { wallet, nonce });
    nonce
}

#[external]
fn verify_challenge(
    ref self: Storage,
    wallet: ContractAddress,
    nonce: u256,
    signature: Array<felt>,
) -> bool {
    let stored_nonce = self.nonces.read(wallet);
    let expiration_time = self.expiration_times.read(wallet);
    let current_time = get_block_timestamp();

    // Check if the nonce is valid and not expired
    assert(stored_nonce == nonce, 'Invalid nonce');
    assert(current_time <= expiration_time, 'Nonce expired');

    // Verify the signature
    let is_valid = verify_signature(wallet, nonce, signature);
    if is_valid {
        self.authenticated_users.write(wallet, true);
        self.emit(AuthEvent::AuthenticationSuccess { wallet });
        return true;
    } else {
        self.emit(AuthEvent::AuthenticationFailure { wallet, reason: 'Invalid signature' });
        return false;
    }
}

#[view]
fn is_authenticated(self: @Storage, wallet: ContractAddress) -> bool {
    self.authenticated_users.read(wallet) == true
}
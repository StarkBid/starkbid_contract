use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starkbid_contract::constants::{DEFAULT_ADMIN_ROLE, MARKETPLACE_ADMIN_ROLE, PAUSER_ROLE};
use starkbid_contract::interfaces::iownership::{IOwnershipDispatcher, IOwnershipDispatcherTrait};
use starknet::{ContractAddress, contract_address_const};

// Helper to initialize contract
fn deploy_contract() -> IOwnershipDispatcher {
    let contract_class = declare("Ownership").unwrap().contract_class();
    let mut constructor_args = array![];

    PLATFORM_RECIPIENT().serialize(ref constructor_args);
    5_u8.serialize(ref constructor_args);
    ADMIN().serialize(ref constructor_args);

    let (contract_address, _) = contract_class.deploy(@constructor_args).unwrap();
    IOwnershipDispatcher { contract_address }
}

fn ADMIN() -> ContractAddress {
    contract_address_const::<'admin'>()
}

fn PLATFORM_RECIPIENT() -> ContractAddress {
    contract_address_const::<'platform'>()
}

fn ASSET_CONTRACT() -> ContractAddress {
    contract_address_const::<'ASSET'>()
}

fn OWNER_CONTRACT() -> ContractAddress {
    contract_address_const::<'OWNER'>()
}
fn NEW_OWNER_CONTRACT() -> ContractAddress {
    contract_address_const::<'NEW_OWNER'>()
}

fn USER_1() -> ContractAddress {
    contract_address_const::<'user1'>()
}

fn USER_2() -> ContractAddress {
    contract_address_const::<'user2'>()
}

fn UNAUTHORIZED_USER() -> ContractAddress {
    0x444.try_into().unwrap()
}

fn test_transfer_ownership_successful() {
    let ownership_dispatcher = deploy_contract();
    let token_id: u256 = 1;
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
    // verify asset owner
    let asset_owner = ownership_dispatcher.get_asset_owner(ASSET_CONTRACT(), token_id);
    let asset_ownership_history = ownership_dispatcher
        .get_asset_ownership_history(ASSET_CONTRACT(), token_id);
    assert(asset_owner == OWNER_CONTRACT(), 'Invalid Owner');
    assert(asset_ownership_history.len() == 1, 'Invalid history length');
    assert(*asset_ownership_history.at(0) == OWNER_CONTRACT(), 'Invalid history data');

    // Change owner to another contract
    start_cheat_caller_address(ownership_dispatcher.contract_address, OWNER_CONTRACT());
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, NEW_OWNER_CONTRACT());
    stop_cheat_caller_address(ownership_dispatcher.contract_address);

    // Check if new_owner is the owner
    // verify new asset owner
    let asset_owner = ownership_dispatcher.get_asset_owner(ASSET_CONTRACT(), token_id);
    let asset_ownership_history = ownership_dispatcher
        .get_asset_ownership_history(ASSET_CONTRACT(), token_id);
    assert(asset_owner == NEW_OWNER_CONTRACT(), 'Invalid Owner');
    assert(asset_ownership_history.len() == 2, 'Invalid history length');
    assert(*asset_ownership_history.at(0) == OWNER_CONTRACT(), 'Invalid history data at index 0');
    assert(
        *asset_ownership_history.at(1) == NEW_OWNER_CONTRACT(), 'Invalid history data at index 1',
    );
}

fn test_transfer_ownership_fails_with_invalid_owner() {
    let ownership_dispatcher = deploy_contract();
    let token_id: u256 = 1;
    // This won't fail because the current owner of this asset
    // is a zero address and the caller is a zero address
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
    // This wull fail because the current owner of this asset
    // is the owner_contract and the caller is a zero address
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, NEW_OWNER_CONTRACT());
}

fn test_transfer_ownership_fails_with_same_owner() {
    let ownership_dispatcher = deploy_contract();
    let token_id: u256 = 1;
    // This won't fail because the current owner of this asset
    // is a zero address and the caller is a zero address
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
    // This wull fail because the current owner of this asset
    // is the owner_contract and the new_owner is the owner_contract
    ownership_dispatcher.transfer_asset_ownership(ASSET_CONTRACT(), token_id, OWNER_CONTRACT());
}

#[test]
fn test_initial_admin_setup() {
    let ownership = deploy_contract();

    // Check that admin has the required roles
    assert!(ownership.has_this_role(DEFAULT_ADMIN_ROLE, ADMIN()), "Admin missing default role");
    assert!(
        ownership.has_this_role(MARKETPLACE_ADMIN_ROLE, ADMIN()), "Admin missing marketplace role"
    );

    // Check role member counts
    assert(
        ownership.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 1, 'Wrong default admin count'
    );
    assert!(
        ownership.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 1,
        "Wrong marketplace admin count"
    );
    assert(ownership.get_this_role_member_count(PAUSER_ROLE) == 0, 'Wrong pauser count');

    // Check role admin relationships
    assert(
        ownership.get_this_role_admin(DEFAULT_ADMIN_ROLE) == DEFAULT_ADMIN_ROLE,
        'Wrong default admin'
    );
    assert(
        ownership.get_this_role_admin(MARKETPLACE_ADMIN_ROLE) == DEFAULT_ADMIN_ROLE,
        'Wrong marketplace admin'
    );
    assert(ownership.get_this_role_admin(PAUSER_ROLE) == DEFAULT_ADMIN_ROLE, 'Wrong pauser admin');
}

#[test]
fn test_grant_role_success() {
    let ownership = deploy_contract();

    // Admin grants marketplace admin role to USER_1
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    stop_cheat_caller_address(ownership.contract_address);

    // Verify role was granted
    assert(ownership.has_this_role(MARKETPLACE_ADMIN_ROLE, USER_1()), 'Role not granted');
    assert(ownership.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 2, 'Wrong member count');
}

#[test]
fn test_grant_role_duplicate_no_effect() {
    let ownership = deploy_contract();

    // Grant role twice
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1()); // Duplicate
    stop_cheat_caller_address(ownership.contract_address);

    // Member count should still be 2 (admin + user1)
    assert(
        ownership.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 2,
        'Duplicate role affected count'
    );
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_grant_role_unauthorized() {
    let ownership = deploy_contract();

    // Unauthorized user tries to grant role
    start_cheat_caller_address(ownership.contract_address, UNAUTHORIZED_USER());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
#[should_panic(expected: ('Zero address',))]
fn test_grant_role_zero_address() {
    let ownership = deploy_contract();

    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, contract_address_const::<0>());
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_revoke_role_success() {
    let ownership = deploy_contract();

    // First grant a role
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());

    // Then revoke it
    ownership.revoke_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    stop_cheat_caller_address(ownership.contract_address);

    // Verify role was revoked
    assert(!ownership.has_this_role(MARKETPLACE_ADMIN_ROLE, USER_1()), 'Role not revoked');
    assert!(
        ownership.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 1,
        "Wrong member count after revoke"
    );
}

#[test]
#[should_panic(expected: ('Cannot remove last admin',))]
fn test_revoke_last_admin_fails() {
    let ownership = deploy_contract();

    // Try to revoke the last admin
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.revoke_this_role(DEFAULT_ADMIN_ROLE, ADMIN());
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_revoke_last_admin_with_backup_succeeds() {
    let ownership = deploy_contract();

    start_cheat_caller_address(ownership.contract_address, ADMIN());
    // First add a backup admin
    ownership.grant_this_role(DEFAULT_ADMIN_ROLE, USER_1());

    // Now we can revoke the original admin
    ownership.revoke_this_role(DEFAULT_ADMIN_ROLE, ADMIN());
    stop_cheat_caller_address(ownership.contract_address);

    // Verify the change
    assert(!ownership.has_this_role(DEFAULT_ADMIN_ROLE, ADMIN()), 'Original admin not revoked');
    assert(ownership.has_this_role(DEFAULT_ADMIN_ROLE, USER_1()), 'Backup admin missing');
    assert(ownership.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 1, 'Wrong admin count');
}

#[test]
fn test_renounce_role_success() {
    let ownership = deploy_contract();

    // Grant role to user
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    stop_cheat_caller_address(ownership.contract_address);

    // User renounces their own role
    start_cheat_caller_address(ownership.contract_address, USER_1());
    ownership.renounce_this_role(MARKETPLACE_ADMIN_ROLE);
    stop_cheat_caller_address(ownership.contract_address);

    // Verify role was renounced
    assert(!ownership.has_this_role(MARKETPLACE_ADMIN_ROLE, USER_1()), 'Role not renounced');
    assert(
        ownership.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 1,
        'Wrong count after renounce'
    );
}

#[test]
#[should_panic(expected: ('Cannot remove last admin',))]
fn test_renounce_last_admin_fails() {
    let ownership = deploy_contract();

    // Admin tries to renounce their admin role (they're the last one)
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.renounce_this_role(DEFAULT_ADMIN_ROLE);
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_admin_can_manage_all_roles() {
    let ownership = deploy_contract();

    start_cheat_caller_address(ownership.contract_address, ADMIN());

    // Admin can grant all role types
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    ownership.grant_this_role(PAUSER_ROLE, USER_2());
    ownership.grant_this_role(DEFAULT_ADMIN_ROLE, USER_1());

    stop_cheat_caller_address(ownership.contract_address);

    // Verify all roles were granted
    assert(
        ownership.has_this_role(MARKETPLACE_ADMIN_ROLE, USER_1()), 'Marketplace role not granted'
    );
    assert(ownership.has_this_role(PAUSER_ROLE, USER_2()), 'Pauser role not granted');
    assert(ownership.has_this_role(DEFAULT_ADMIN_ROLE, USER_1()), 'Admin role not granted');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_marketplace_admin_cannot_grant_admin_role() {
    let ownership = deploy_contract();

    // Grant marketplace admin role to USER_1
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    stop_cheat_caller_address(ownership.contract_address);

    // USER_1 (marketplace admin) tries to grant DEFAULT_ADMIN_ROLE
    start_cheat_caller_address(ownership.contract_address, USER_1());
    ownership.grant_this_role(DEFAULT_ADMIN_ROLE, USER_2());
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_platform_fee_management_by_marketplace_admin() {
    let ownership = deploy_contract();
    let new_recipient = contract_address_const::<'new_recipient'>();

    // Grant USER_1 marketplace admin role
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    stop_cheat_caller_address(ownership.contract_address);

    // USER_1 can now manage platform fees
    start_cheat_caller_address(ownership.contract_address, USER_1());
    ownership.set_platform_fee_info(new_recipient, 3_u8);
    stop_cheat_caller_address(ownership.contract_address);

    let (recipient, fee) = ownership.get_platform_fee_info();
    assert(recipient == new_recipient, 'Platform recipient not updated');
    assert(fee == 3_u8, 'Platform fee not updated');
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_platform_fee_unauthorized_user() {
    let ownership = deploy_contract();
    let new_recipient = contract_address_const::<'new_recipient'>();

    // Unauthorized user tries to set platform fee
    start_cheat_caller_address(ownership.contract_address, UNAUTHORIZED_USER());
    ownership.set_platform_fee_info(new_recipient, 10_u8);
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_system_pause_by_pauser() {
    let ownership = deploy_contract();
    let PAUSER_USER = contract_address_const::<'pauser_user'>();

    // Grant pauser role to USER_1
    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.grant_this_role(PAUSER_ROLE, PAUSER_USER);
    stop_cheat_caller_address(ownership.contract_address);

    // Pauser can pause the system
    start_cheat_caller_address(ownership.contract_address, PAUSER_USER);
    ownership.pause_system();
    assert(ownership.is_system_paused(), 'System should be paused');

    // Pauser can unpause the system
    ownership.unpause_system();
    assert(!ownership.is_system_paused(), 'System should be unpaused');
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_system_pause_by_admin() {
    let ownership = deploy_contract();

    start_cheat_caller_address(ownership.contract_address, ADMIN());
    ownership.pause_system();
    assert(ownership.is_system_paused(), 'System should be paused');

    ownership.unpause_system();
    assert(!ownership.is_system_paused(), 'System should be unpaused');
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is missing role',))]
fn test_system_pause_unauthorized() {
    let ownership = deploy_contract();

    // Unauthorized user tries to pause system
    start_cheat_caller_address(ownership.contract_address, UNAUTHORIZED_USER());
    ownership.pause_system();
    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_multiple_role_assignments() {
    let ownership = deploy_contract();

    start_cheat_caller_address(ownership.contract_address, ADMIN());

    // Grant multiple roles to the same user
    ownership.grant_this_role(MARKETPLACE_ADMIN_ROLE, USER_1());
    ownership.grant_this_role(PAUSER_ROLE, USER_1());

    stop_cheat_caller_address(ownership.contract_address);

    // Verify user has both roles
    assert(ownership.has_this_role(MARKETPLACE_ADMIN_ROLE, USER_1()), 'Missing marketplace role');
    assert(ownership.has_this_role(PAUSER_ROLE, USER_1()), 'Missing pauser role');

    // User with marketplace admin role can manage platform fees
    start_cheat_caller_address(ownership.contract_address, USER_1());
    ownership.set_platform_fee_info(contract_address_const::<'new_platform'>(), 7_u8);

    // User with pauser role can pause system
    ownership.pause_system();
    assert(ownership.is_system_paused(), 'System should be paused');

    stop_cheat_caller_address(ownership.contract_address);
}

#[test]
fn test_role_member_count_accuracy() {
    let ownership = deploy_contract();

    start_cheat_caller_address(ownership.contract_address, ADMIN());

    // Initial state: 1 default admin, 1 marketplace admin, 0 pausers
    assert(
        ownership.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 1, 'Wrong initial admin count'
    );
    assert(
        ownership.get_this_role_member_count(MARKETPLACE_ADMIN_ROLE) == 1,
        'Wrong initial marketplace count'
    );
    assert(ownership.get_this_role_member_count(PAUSER_ROLE) == 0, 'Wrong initial pauser count');

    // Add members
    ownership.grant_this_role(PAUSER_ROLE, USER_1());
    ownership.grant_this_role(PAUSER_ROLE, USER_2());
    ownership.grant_this_role(DEFAULT_ADMIN_ROLE, USER_1());

    // Check counts
    assert(
        ownership.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 2,
        'Wrong admin count after grants'
    );
    assert(
        ownership.get_this_role_member_count(PAUSER_ROLE) == 2, 'Wrong pauser count after grants'
    );

    // Remove members
    ownership.revoke_this_role(PAUSER_ROLE, USER_1());

    // Check counts after removal
    assert(
        ownership.get_this_role_member_count(PAUSER_ROLE) == 1, 'Wrong pauser count after revoke'
    );
    assert(
        ownership.get_this_role_member_count(DEFAULT_ADMIN_ROLE) == 2,
        'Admin count should be unchanged'
    );

    stop_cheat_caller_address(ownership.contract_address);
}

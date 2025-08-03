#[starknet::contract]
mod CollectionFactory {
    use core::num::traits::Zero;
    use core::poseidon::PoseidonTrait;
    use crate::components::pausable::PausableComponent::InternalTrait;
    use crate::components::pausable::PausableComponent::Pausable;
    use crate::components::pausable::{Pausable, IPausable};
    use crate::constants::{DEFAULT_ADMIN_ROLE, COLLECTION_CREATOR_ROLE, MARKETPLACE_ADMIN_ROLE};
    use crate::interfaces::icollection_factory::ICollectionFactory;
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::storage::{Map, StoragePathEntry, MutableVecTrait, Vec, VecTrait};
    use starknet::{
        ContractAddress, ClassHash, get_caller_address, get_contract_address, deploy_syscall,
        SyscallResultTrait, get_block_timestamp
    };

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    // Pausable component
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;


    #[storage]
    struct Storage {
        owner: ContractAddress,
        collections: Map<u256, ContractAddress>,
        collection_creators: Map<u256, ContractAddress>,
        declared_classes: Map<ClassHash, bool>,
        collection_counter: u256,
        role_members: Map<felt252, Vec<ContractAddress>>, // role -> Vec of members
        member_active: Map<(felt252, ContractAddress), bool>, // Track active members
        factory_paused: bool,
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
        CollectionCreated: CollectionCreated,
        ClassDeclared: ClassDeclared,
        OwnershipTransferred: OwnershipTransferred,
        FactoryPaused: FactoryPaused,
        FactoryUnpaused: FactoryUnpaused,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct CollectionCreated {
        #[key]
        collection_id: u256,
        #[key]
        creator: ContractAddress,
        contract_address: ContractAddress,
        class_hash: ClassHash,
        name: ByteArray,
        symbol: ByteArray,
        royalty_percentage: u16,
    }

    #[derive(Drop, starknet::Event)]
    struct ClassDeclared {
        #[key]
        class_hash: ClassHash,
        declared_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct FactoryPaused {
        #[key]
        paused_by: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    struct FactoryUnpaused {
        #[key]
        unpaused_by: ContractAddress,
        timestamp: u64,
    }
    pub mod Errors {
        const ZERO_ADDRESS: felt252 = 'Zero address not allowed';
        const CLASS_NOT_DECLARED: felt252 = 'Class hash not declared';
        const CLASS_ALREADY_DECLARED: felt252 = 'Class hash already declared';
        const COLLECTION_NOT_FOUND: felt252 = 'Collection not found';
        const FACTORY_PAUSED: felt252 = 'Factory paused';
        const CANNOT_GRANT_ZERO_ADDRESS: felt252 = 'account is zero address';
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        assert(!owner.is_zero(), Errors::ZERO_ADDRESS);
        self.owner.write(owner);
        self.collection_counter.write(0);
        self.factory_paused.write(false);

        // Initialize RBAC
        self.accesscontrol.initializer();

        // Set up role hierarchy - DEFAULT_ADMIN_ROLE manages all other roles
        self.accesscontrol.set_role_admin(MARKETPLACE_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        self.accesscontrol.set_role_admin(COLLECTION_CREATOR_ROLE, DEFAULT_ADMIN_ROLE);
        self
            .accesscontrol
            .set_role_admin(DEFAULT_ADMIN_ROLE, DEFAULT_ADMIN_ROLE); // Self-management

        // Grant initial roles
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, owner);
        self.accesscontrol._grant_role(MARKETPLACE_ADMIN_ROLE, owner);

        // Initialize role member tracking for BOTH roles
        self.role_members.entry(DEFAULT_ADMIN_ROLE).append().write(owner);
        self.role_members.entry(MARKETPLACE_ADMIN_ROLE).append().write(owner);

        // Mark both as active
        self.member_active.write((DEFAULT_ADMIN_ROLE, owner), true);
        self.member_active.write((MARKETPLACE_ADMIN_ROLE, owner), true);
        self.pausable.initializer(pauser: owner);
    }

    #[abi(embed_v0)]
    impl CollectionFactoryImpl of ICollectionFactory<ContractState> {
        fn declare_collection_class(ref self: ContractState, class_hash: ClassHash) -> bool {
            // Add pause protection
            self.pausable._assert_not_paused();
            assert(!self.factory_paused.read(), Errors::FACTORY_PAUSED);
            self.accesscontrol.assert_only_role(MARKETPLACE_ADMIN_ROLE);

            self._assert_only_owner();

            assert(!self.declared_classes.read(class_hash), Errors::CLASS_ALREADY_DECLARED);
            self.declared_classes.write(class_hash, true);
            self.emit(ClassDeclared { class_hash, declared_by: get_caller_address() });

            true
        }

        fn deploy_collection(
            ref self: ContractState, class_hash: ClassHash, arguments: Array<felt252>,
        ) -> (ContractAddress, u256) {
            // Add pause protection
            self.pausable._assert_not_paused();
            assert(!self.factory_paused.read(), Errors::FACTORY_PAUSED);
            self.accesscontrol.assert_only_role(COLLECTION_CREATOR_ROLE);

            self._assert_class_declared(class_hash);
            let creator = get_caller_address();
            let salt = PoseidonTrait::new()
                .update_with(get_block_timestamp())
                .update_with(get_block_number())
                .finalize();

            let (contract_address, _) = deploy_syscall(class_hash, salt, arguments.span(), false)
                .unwrap();

            let collection_id = self.collection_counter.read();

            self.collections.write(collection_id, contract_address);
            self.collection_creators.write(collection_id, creator);
            self.collection_counter.write(collection_id + 1);
            self.emit(CollectionCreated { collection_id, creator, contract_address, class_hash });

            (contract_address, collection_id)
        }

        fn get_collection_address(self: @ContractState, collection_id: u256) -> ContractAddress {
            let address = self.collections.read(collection_id);
            assert(!address.is_zero(), Errors::COLLECTION_NOT_FOUND);
            address
        }
        fn get_collection_creator(self: @ContractState, collection_id: u256) -> ContractAddress {
            let creator = self.collection_creators.read(collection_id);
            assert(!creator.is_zero(), Errors::COLLECTION_NOT_FOUND);
            creator
        }

        fn is_class_declared(self: @ContractState, class_hash: ClassHash) -> bool {
            self.declared_classes.read(class_hash)
        }

        fn get_factory_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            self._assert_only_owner();
            assert(!new_owner.is_zero(), Errors::ZERO_ADDRESS);

            let previous_owner = self.owner.read();
            self.owner.write(new_owner);

            self.emit(OwnershipTransferred { previous_owner, new_owner, });
        }

        /// Access Control
        fn grant_this_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            assert(!account.is_zero(), Errors::CANNOT_GRANT_ZERO_ADDRESS);

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

        /// PAUSE FUNCTIONALITY

        fn pause_factory(ref self: ContractState) {
            self.accesscontrol.assert_only_role(MARKETPLACE_ADMIN_ROLE);
            self.factory_paused.write(true);

            self
                .emit(
                    FactoryPaused {
                        paused_by: get_caller_address(), timestamp: get_block_timestamp()
                    }
                );
        }

        fn unpause_factory(ref self: ContractState) {
            self.accesscontrol.assert_only_role(MARKETPLACE_ADMIN_ROLE);
            self.factory_paused.write(false);

            self
                .emit(
                    FactoryUnpaused {
                        unpaused_by: get_caller_address(), timestamp: get_block_timestamp()
                    }
                );
        }

        fn is_factory_paused(self: @ContractState) -> bool {
            self.factory_paused.read()
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
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _assert_only_owner(ref self: ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'Caller is not owner');
        }
        fn _assert_class_declared(ref self: ContractState, class_hash: ClassHash) {
            assert(self.declared_classes.read(class_hash), Errors::CLASS_NOT_DECLARED);
        }

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
}

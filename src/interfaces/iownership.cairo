use starknet::ContractAddress;

#[starknet::interface]
pub trait IOwnership<TContractState> {
    fn transfer_asset_ownership(
        ref self: TContractState,
        asset: ContractAddress,
        token_id: u256,
        new_owner: ContractAddress,
    );
    fn get_asset_owner(
        self: @TContractState, asset: ContractAddress, token_id: u256,
    ) -> ContractAddress;
    fn get_asset_ownership_history(
        self: @TContractState, asset: ContractAddress, token_id: u256,
    ) -> Array<ContractAddress>;

    // Royalty Management
    fn set_royalty_settings(
        ref self: TContractState,
        asset: ContractAddress,
        token_id: u256,
        recipients_config: Array<(ContractAddress, u8)>,
    );
    fn update_royalty_recipient(
        ref self: TContractState,
        asset: ContractAddress,
        token_id: u256,
        old_recipient: ContractAddress,
        new_recipient: ContractAddress,
    );
    fn set_platform_fee_info(
        ref self: TContractState, recipient: ContractAddress, fee_percentage: u8,
    );

    // Royalty Distribution
    fn distribute_sale_proceeds(
        ref self: TContractState, asset: ContractAddress, token_id: u256, sale_price: u256,
    );

    // Withdrawal
    fn withdraw_funds(ref self: TContractState);

    // View Functions
    fn get_pending_withdrawal_amount(self: @TContractState, recipient: ContractAddress) -> u256;
    fn get_royalty_settings(
        self: @TContractState, asset: ContractAddress, token_id: u256,
    ) -> Array<(ContractAddress, u8)>;
    fn get_platform_fee_info(self: @TContractState) -> (ContractAddress, u8);
    fn get_contract_owner(self: @TContractState) -> ContractAddress;
}

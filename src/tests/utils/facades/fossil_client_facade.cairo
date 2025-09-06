use crate::fossil_client::interface::{
    IFossilClientDispatcher, IFossilClientSafeDispatcher, IFossilClientDispatcherTrait,
    IFossilClientSafeDispatcherTrait
};
use crate::tests::utils::helpers::setup::{
    FOSSIL_PROCESSOR, FOSSIL_CLIENT_OWNER, PITCHLAKE_VERIFIER
};
use starknet::testing::set_contract_address;
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
// add this and tests

// test only fossil processor can call the client (fossil_callback)

// test only the client can call the vault (fossil_client_callback)

#[derive(Copy, Drop)]
struct FossilClientFacade {
    contract_address: starknet::ContractAddress
}

#[generate_trait]
impl FossilClientFacadeImpl of FossilClientFacadeTrait {
    /// Helpers
    fn dispatcher(self: FossilClientFacade) -> IFossilClientDispatcher {
        IFossilClientDispatcher { contract_address: self.contract_address }
    }

    fn safe_dispatcher(self: FossilClientFacade) -> IFossilClientSafeDispatcher {
        IFossilClientSafeDispatcher { contract_address: self.contract_address }
    }

    /// Getters
    fn get_verifier(self: FossilClientFacade) -> starknet::ContractAddress {
        self.dispatcher().get_verifier()
    }

    fn is_verifier_set(self: FossilClientFacade) -> bool {
        self.dispatcher().is_verifier_set()
    }

    fn owner(self: FossilClientFacade) -> starknet::ContractAddress {
        IOwnableDispatcher { contract_address: self.contract_address }.owner()
    }

    /// Entrypoints
    fn fossil_callback(self: FossilClientFacade, request: Span<felt252>, result: Span<felt252>) {
        set_contract_address(self.owner());
        self.dispatcher().fossil_callback(request, result);
    }

    fn initialize_verifier(self: FossilClientFacade, verifier: starknet::ContractAddress) {
        set_contract_address(FOSSIL_CLIENT_OWNER());
        self.dispatcher().initialize_verifier(verifier);
    }

    #[feature("safe_dispatcher")]
    fn fossil_callback_expect_error(
        self: FossilClientFacade, request: Span<felt252>, result: Span<felt252>, error: felt252
    ) {
        let safe = self.safe_dispatcher();
        safe.fossil_callback(request, result).expect_err(error);
    }

    #[feature("safe_dispatcher")]
    fn initialize_verifier_expect_error(
        self: FossilClientFacade, verifier: starknet::ContractAddress, error: felt252
    ) {
        let safe = self.safe_dispatcher();
        safe.initialize_verifier(verifier).expect_err(error);
    }
}


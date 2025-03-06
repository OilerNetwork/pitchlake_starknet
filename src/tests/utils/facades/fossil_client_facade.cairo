use crate::fossil_client::interface::{
    IFossilClientDispatcher, IFossilClientSafeDispatcher, IFossilClientDispatcherTrait,
    IFossilClientSafeDispatcherTrait, FossilCallbackReturn
};
use crate::tests::utils::helpers::setup::FOSSIL_PROCESSOR;
use starknet::testing::set_contract_address;
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

    /// Entrypoints
    fn fossil_callback(
        self: FossilClientFacade, request: Span<felt252>, result: Span<felt252>
    ) -> FossilCallbackReturn {
        set_contract_address(FOSSIL_PROCESSOR());
        self.dispatcher().fossil_callback(request, result)
    }

    #[feature("safe_dispatcher")]
    fn fossil_callback_expect_error(
        self: FossilClientFacade, request: Span<felt252>, result: Span<felt252>, error: felt252
    ) {
        let safe = self.safe_dispatcher();
        safe.fossil_callback(request, result).expect_err(error);
    }
}


use starknet::{ContractAddress,};
use pitch_lake_starknet::{lp_token::{ILPToken, ILPTokenDispatcher, ILPTokenDispatcherTrait},};

#[derive(Drop)]
struct LPTokenFacade {
    lp_token_dispatcher: ILPTokenDispatcher,
}

#[generate_trait]
impl LPTokenFacadeImpl of LPTokenFacadeTrait {
    /// Reads /// 
    fn contract_address(ref self: LPTokenFacade) -> ContractAddress {
        self.lp_token_dispatcher.contract_address
    }
/// Writes ///

// @note token -> position & position -> token should be a vault entry point

/// Helpers ///
}


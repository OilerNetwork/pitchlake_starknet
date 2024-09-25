use starknet::ContractAddress;
use pitch_lake::{
    fact_registry::{
        contract::{FactRegistry},
        interface::{
            JobRequest, JobRequestParams, IFactRegistryDispatcher, IFactRegistryDispatcherTrait,
        }
    },
    vault::interface::{FossilDataPoints}, library::utils::generate_job_id
};


#[derive(Drop, Copy)]
pub struct FactRegistryFacade {
    contract_address: ContractAddress
}

#[generate_trait]
pub impl FactRegsitryFacadeImpl of FactRegistryFacadeTrait {
    // Helpers
    fn get_dispatcher(self: @FactRegistryFacade) -> IFactRegistryDispatcher {
        IFactRegistryDispatcher { contract_address: *self.contract_address }
    }

    fn get_fact(self: @FactRegistryFacade, job_id: felt252) -> Span<felt252> {
        self.get_dispatcher().get_fact(job_id)
    }

    fn set_fact(
        self: @FactRegistryFacade, job_request: JobRequest, fossil_data_points: FossilDataPoints
    ) {
        let mut data: Array<felt252> = Default::default();
        fossil_data_points.serialize(ref data);
        self.get_dispatcher().set_fact(job_request, data.span());
    }
}


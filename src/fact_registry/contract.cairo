#[starknet::contract]
pub mod FactRegistry {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess,};
    use starknet::storage::{Map, StoragePathEntry};
    use pitch_lake::fact_registry::interface::{IFactRegistry, JobRequest, JobRequestParams};
    use pitch_lake::library::utils::generate_job_id;

    const FACT_SIZE: usize = 5; // (u256, u128, u256)

    #[storage]
    struct Storage {
        facts: Map<felt252, Map<usize, felt252>>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl FactRegistryImpl of IFactRegistry<ContractState> {
        fn get_fact(self: @ContractState, job_id: felt252) -> Span<felt252> {
            let mut fact: Array<felt252> = array![];

            for i in 0..FACT_SIZE {
                fact.append(self.facts.entry(job_id).entry(i).read());
            };

            fact.span()
        }

        fn set_fact(
            ref self: ContractState, job_request: JobRequest, job_data: Span<felt252>
        ) -> felt252 {
            /// Proving would happen first ... ///

            let job_id = generate_job_id(@job_request);

            for i in 0..FACT_SIZE {
                self.facts.entry(job_id).entry(i).write(*job_data.at(i));
            };

            job_id
        }
    }
}

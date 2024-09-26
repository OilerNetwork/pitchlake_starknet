#[starknet::interface]
trait IFactRegistry<TContractState> {
    fn get_fact(self: @TContractState, job_id: felt252) -> Span<felt252>;
    fn set_fact(
        ref self: TContractState, job_request: JobRequest, job_data: Span<felt252>
    ) -> felt252;
}

#[derive(Copy, Destruct, Serde)]
struct JobRequest {
    identifiers: Span<felt252>,
    params: JobRequestParams,
}

#[derive(Drop, Copy, Serde)]
struct JobRequestParams {
    twap: (u64, u64),
    volatility: (u64, u64),
    reserve_price: (u64, u64),
}

#[derive(Copy, Drop, PartialEq)]
struct JobRange {
    twap_range: u64,
    volatility_range: u64,
    reserve_price_range: u64
}

#[starknet::interface]
pub trait IFactRegistry<TContractState> {
    fn get_fact(self: @TContractState, job_id: felt252) -> Span<felt252>;
    fn set_fact(
        ref self: TContractState, job_request: JobRequest, job_data: Span<felt252>
    ) -> felt252;
}

#[derive(Copy, Destruct, Serde)]
pub struct JobRequest {
    pub identifiers: Span<felt252>,
    pub params: JobRequestParams,
}

#[derive(Drop, Copy, Serde)]
pub struct JobRequestParams {
    pub twap: (u64, u64),
    pub volatility: (u64, u64),
    pub reserve_price: (u64, u64),
}

#[derive(Copy, Drop, PartialEq)]
pub struct JobRange {
    twap_range: u64,
    volatility_range: u64,
    reserve_price_range: u64
}


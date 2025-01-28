use pitch_lake::fossil_client::interface::{L1Data, JobRequest, FossilResult};
use pitch_lake::tests::utils::facades::vault_facade::{VaultFacade, VaultFacadeTrait};
use pitch_lake::tests::utils::helpers::general_helpers::to_gwei;

fn get_mock_l1_data() -> L1Data {
    L1Data { twap: to_gwei(33) / 100, volatility: 1009, reserve_price: to_gwei(11) / 10 }
}

fn get_mock_result() -> FossilResult {
    FossilResult { proof: array![].span(), l1_data: get_mock_l1_data() }
}

fn get_mock_result_serialized() -> Span<felt252> {
    let mut result_serialized = array![];
    get_mock_result().serialize(ref result_serialized);
    result_serialized.span()
}

fn get_request(ref vault: VaultFacade) -> JobRequest {
    vault.get_request_to_settle_round()
}

fn get_request_serialized(ref vault: VaultFacade) -> Span<felt252> {
    let mut request_serialized = array![];
    get_request(ref vault).serialize(ref request_serialized);
    request_serialized.span()
}
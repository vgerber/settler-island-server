mod common;

use common::{start, test_config, Client};

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_frame_far_above_the_message_limit_closes_the_socket() {
    let address = start(test_config()).await;
    let (mut client, _) = Client::welcomed(address, "Flooder").await;

    client.send_raw_unchecked("x".repeat(200 * 1024)).await;

    assert!(client.closed_by_server().await);
}

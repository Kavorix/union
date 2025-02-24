module IBC::Core {
    use std::signer;
    use std::vector;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::table::{Self, Table};
    use std::event;
    use std::bcs;
    use std::object;
    use std::string::{Self, String};
    use std::hash;
    use std::timestamp;

    use std::string_utils;
    use std::from_bcs;
    use IBC::IBCCommitment::{Self, Capability};
    use IBC::LightClient;
    use IBC::height::{Self, Height};
    use IBC::connection_end::{Self, ConnectionEnd};
    use IBC::channel::{Self, Channel};
    use IBC::packet::{Self, Packet};

    const CLIENT_TYPE_COMETBLS: vector<u8> = b"cometbls";

    const CHAN_STATE_UNINITIALIZED: u8 = 0;
    const CHAN_STATE_INIT: u8 = 1;
    const CHAN_STATE_TRYOPEN: u8 = 2;
    const CHAN_STATE_OPEN: u8 = 3;
    const CHAN_STATE_CLOSED: u8 = 4;

    const CHAN_ORDERING_NONE: u8 = 0;
    const CHAN_ORDERING_UNORDERED: u8 = 1;
    const CHAN_ORDERING_ORDERED: u8 = 2;

    const CONN_STATE_UNSPECIFIED: u64 = 0;
    const CONN_STATE_INIT: u64 = 1;
    const CONN_STATE_TRYOPEN: u64 = 2;
    const CONN_STATE_OPEN: u64 = 3;

    const VAULT_SEED: vector<u8> = b"IBC_VAULT_SEED";

    const E_NOT_ENOUGH_PERMISSIONS_TO_INITIALIZE: u64 = 1001;
    const E_CLIENT_NOT_FOUND: u64 = 1002;
    const E_VERSION_MUST_BE_UNSET: u64 = 1006;
    const E_UNSUPPORTED_VERSION: u64 = 1007;
    const E_INVALID_CONNECTION_STATE: u64 = 1008;
    const E_CONNECTION_ALREADY_EXISTS: u64 = 1009;
    const E_INVALID_PROOF: u64 = 1010;
    const E_CONN_NOT_SINGLE_HOP: u64 = 1011;
    const E_CONN_NOT_SINGLE_VERSION: u64 = 1012;
    const E_UNSUPPORTED_FEATURE: u64 = 1013;
    const E_CAPABILITY_ALREADY_CLAIMED: u64 = 1014;
    const E_PORT_ID_MUST_BE_LOWERCASE: u64 = 1015;
    const E_INVALID_CHANNEL_STATE: u64 = 1016;
    const E_COUNTERPARTY_CHANNEL_NOT_EMPTY: u64 = 1017;
    const E_INVALID_TIMEOUT_HEIGHT: u64 = 1018;
    const E_LATEST_TIMESTAMP_NOT_FOUND: u64 = 1019;
    const E_UNAUTHORIZED: u64 = 1020;
    const E_INVALID_TIMEOUT_TIMESTAMP: u64 = 1021;
    const E_LATEST_HEIGHT_NOT_FOUND: u64 = 1022; 
    const E_SOURCE_AND_COUNTERPARTY_PORT_MISMATCH: u64 = 1023;
    const E_SOURCE_AND_COUNTERPARTY_CHANNEL_MISMATCH: u64 = 1022;   
    const E_TIMESTAMP_TIMEOUT: u64 = 1023;   
    const E_HEIGHT_TIMEOUT: u64 = 1024;   
    const E_PACKET_ALREADY_RECEIVED: u64 = 1025;   
    const E_PACKET_SEQUENCE_NEXT_SEQUENCE_MISMATCH: u64 = 1026; 
    const E_UNKNOWN_CHANNEL_ORDERING: u64 = 1027;    
    const E_CONNECTION_DOES_NOT_EXIST: u64 = 1028;
    const E_ACKNOWLEDGEMENT_IS_EMPTY: u64 = 1028;
    const E_ACKNOWLEDGEMENT_ALREADY_EXISTS: u64 = 1029;
    const E_DESTINATION_AND_COUNTERPARTY_PORT_MISMATCH: u64 = 1030;
    const E_DESTINATION_AND_COUNTERPARTY_CHANNEL_MISMATCH: u64 = 1031;
    const E_PACKET_COMMITMENT_NOT_FOUND: u64 = 1032;
    const E_INVALID_PACKET_COMMITMENT: u64 = 1033;
    const E_TIMESTAMP_TIMEOUT_NOT_REACHED: u64 = 1034;
    const E_TIMEOUT_HEIGHT_NOT_REACHED: u64 = 1035;
    const E_INVALID_UPDATE: u64 = 1036;
    const E_NEXT_SEQUENCE_MUST_BE_GREATER_THAN_TIMEOUT_SEQUENCE: u64 = 1037;
    const E_CLIENT_NOT_ACTIVE: u64 = 1038;
    const E_UNKNOWN_CLIENT_TYPE: u64 = 1039;     

    #[event]
    struct ClientCreatedEvent has copy, drop, store {
        client_id: String,
    }

    #[event]
    struct ClientUpdated has copy, drop, store {
        client_id: String,
        height: Height,
    }

    #[event]
    struct ConnectionOpenInit has copy, drop, store {
        connection_id: String,
        client_id: String,
        counterparty_client_id: String,
    }    

    #[event]
    struct ChannelOpenInit has copy, drop, store {
        port_id: String,
        channel_id: String,
        counterparty_port_id: String,
        connection_id: String,
        version: String
    }    
    
    #[event]
    struct ChannelOpenTry has copy, drop, store {
        port_id: String,
        channel_id: String,
        counterparty_port_id: String,
        counterparty_channel_id: String,
        connection_id: String,
        version: String
    }
    
    #[event]
    struct ChannelOpenAck has copy, drop, store {
        port_id: String,
        channel_id: String,
        counterparty_port_id: String,
        counterparty_channel_id: String,
        connection_id: String
    }

    #[event]
    struct ChannelOpenConfirm has copy, drop, store {
        port_id: String,
        channel_id: String,
        counterparty_port_id: String,
        counterparty_channel_id: String,
        connection_id: String
    }
    
    #[event]
    struct ConnectionOpenTry has copy, drop, store {
        connection_id: String,
        client_id: String,
        counterparty_client_id: String,
        counterparty_connection_id: String,
    }

    #[event]
    struct ConnectionOpenAck has copy, drop, store {
        connection_id: String,
        client_id: String,
        counterparty_client_id: String,
        counterparty_connection_id: String,
    }

    #[event]
    struct ConnectionOpenConfirm has copy, drop, store {
        connection_id: String,
        client_id: String,
        counterparty_client_id: String,
        counterparty_connection_id: String,
    }

    #[event]
    struct SendPacket has drop, store {
        sequence: u64,
        source_port: String,
        source_channel: String,
        timeout_height: height::Height,
        timeout_timestamp: u64,
        data: vector<u8>, 
    }    
    
    #[event]
    struct RecvPacket has drop, store {
        packet: Packet
    }    

    #[event]
    struct TimeoutPacket has drop, store {
        packet: Packet
    }

    #[event]
    struct WriteAcknowledgement has drop, store {
        packet: Packet,
        acknowledgement: vector<u8>
    }   
    
    #[event]
    struct AcknowledgePacket has drop, store {
        packet: Packet,
        acknowledgement: vector<u8>
    }    
    

    struct ChannelPort has copy, drop, store {
        port_id: String,
        channel_id: String,
    }

    // Resource to hold the global state
    struct IBCStore has key {
        client_impls: SmartTable<String, address>,
        client_registry: SmartTable<String, address>,
        commitments: Table<vector<u8>, vector<u8>>,
        connections: SmartTable<String, ConnectionEnd>,
        channels: SmartTable<ChannelPort, Channel>, 
        capabilities: SmartTable<Capability, address>,
    }


    // Sample setter for `capabilities`
    public fun set_capability(capability: Capability, addr: address) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        smart_table::upsert(&mut store.capabilities, capability, addr);
    }

    struct SignerRef has key {
        self_ref: object::ExtendRef,
    }

    #[view]
    public fun client_state(client_id: String): vector<u8> {
        LightClient::get_client_state(client_id)
    }

    #[view]
    public fun consensus_state(client_id: String, revision_number: u64, revision_height: u64): vector<u8> {
        LightClient::get_consensus_state(client_id, height::new(revision_number, revision_height))
    }

    #[view]
    public fun get_vault_addr(): address {
        object::create_object_address(&@IBC, VAULT_SEED)
    }

    public fun set_connection(connection_id: String, connection: ConnectionEnd) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        smart_table::upsert(&mut store.connections, connection_id, connection);
    }

    public fun set_channel(port_id: String, channel_id: String, channel: Channel) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let channel_port = ChannelPort{port_id, channel_id};

        smart_table::upsert(&mut store.channels, channel_port, channel);
    }

    // Setter for Commitments
    public fun set_commitment(key: vector<u8>, value: vector<u8>) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        table::upsert(&mut store.commitments, key, value);
    }

    // Getter for Commitments
    public fun get_commitment(key: vector<u8>): vector<u8> acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let commitment = table::borrow_with_default(&store.commitments, key, &vector::empty<u8>());
        *commitment
    }

    // Getter for Commitments
    public fun get_channel_from_store(key: String, channel_id: String): Channel acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let channel_port = ChannelPort{port_id: key, channel_id};
        let channel = smart_table::borrow(&store.channels, channel_port);

        *channel
    }


    // Getter for Commitments
    public fun get_capability_from_store(capability: Capability): address acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let capability_addr = smart_table::borrow(&store.capabilities, capability);

        *capability_addr
    }

    // Setter for nextChannelSequence in Commitments
    public fun set_next_channel_sequence(sequence: u64) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        table::upsert(&mut store.commitments, b"nextChannelSequence", bcs::to_bytes(&sequence));
    }

    // Getter for nextChannelSequence in Commitments
    public fun get_next_channel_sequence(): u64 acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let next_sequence_bytes = table::borrow_with_default(&store.commitments, b"nextChannelSequence", &bcs::to_bytes<u64>(&0));
        from_bcs::to_u64(*next_sequence_bytes)
    }


    // Initializes the IBCStore resource in the signer's account
    fun init_module(account: &signer)  {
        assert!(signer::address_of(account) == @IBC, E_NOT_ENOUGH_PERMISSIONS_TO_INITIALIZE);
        let vault_constructor_ref = &object::create_named_object(account, VAULT_SEED);
        let vault_signer = &object::generate_signer(vault_constructor_ref);

        let merkle_root = LightClient::new_merkle_root(vector::empty());
        let encoded = std::bcs::to_bytes(&merkle_root);
        let merkle_root = std::from_bcs::from_bytes<LightClient::MerkleRoot>(encoded);
        std::debug::print(&merkle_root);

        let store = IBCStore {
            client_registry: smart_table::new(),
            commitments: table::new(),
            client_impls: smart_table::new(),
            connections: smart_table::new(),
            channels: smart_table::new<ChannelPort, Channel>(),
            capabilities: smart_table::new(),
        };

        move_to(vault_signer, store);

        move_to(vault_signer, SignerRef {
            self_ref: object::generate_extend_ref(vault_constructor_ref)
        });
    }

    // Function to generate a client identifier
    public fun generate_client_identifier(client_type: String): String acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        let next_sequence = table::borrow_with_default(&store.commitments, b"nextClientSequence", &bcs::to_bytes<u64>(&0u64));
        let next_sequence = from_bcs::to_u64(*next_sequence);

        table::upsert(&mut store.commitments, b"nextClientSequence", bcs::to_bytes<u64>(&(next_sequence + 1)));

        string_utils::format2(&b"{}-{}", client_type, next_sequence)
    }


    /// Create a client with an initial client and consensus state
    public entry fun create_client(
        client_type: String,
        client_state: vector<u8>,
        consensus_state: vector<u8>,
    ) acquires IBCStore, SignerRef {
        // NOTE(aeryz): At this point, we don't need to have a routing mechanism because it will introduce
        // additional gas cost. We should only enforce the use of `cometbls` for the `client_type`
        assert!(string::bytes(&client_type) == &b"cometbls", E_UNKNOWN_CLIENT_TYPE);

        let client_id = generate_client_identifier(client_type);
        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        let (status_code, client_state, consensus_state) = LightClient::create_client(
            &get_ibc_signer(),
            client_id, 
            client_state, 
            consensus_state,
        );
    
        assert!(status_code == 0, status_code);

        // TODO(aeryz): fetch these status from proper exported consts
        assert!(LightClient::status(&client_id) == 0, E_CLIENT_NOT_ACTIVE);

        // Update commitments
        table::upsert(&mut store.commitments, IBCCommitment::client_state_commitment_key(client_id), hash::sha2_256(client_state));

        let latest_height = LightClient::latest_height(client_id);

        table::upsert(
            &mut store.commitments,
            IBCCommitment::consensus_state_commitment_key(client_id, latest_height),
            hash::sha2_256(consensus_state)
        );

        event::emit(
            ClientCreatedEvent {
                client_id
            },
        );
    }

    public entry fun connection_open_init(
        client_id: String,
        version_identifier: String,
        version_features: vector<String>,
        counterparty_client_id: String,
        counterparty_connection_id: String,
        counterparty_prefix: vector<u8>,
        delay_period: u64,
    ) acquires IBCStore {
        let version = connection_end::new_version(version_identifier, version_features);
        let counterparty = connection_end::new_counterparty(counterparty_client_id, counterparty_connection_id, counterparty_prefix);

        assert!(LightClient::status(&client_id) == 0, E_CLIENT_NOT_ACTIVE);

        let connection_id = generate_connection_identifier();
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let connection = connection_end::new(
            client_id,
            vector::empty<connection_end::Version>(),
            CONN_STATE_INIT,
            delay_period,
            counterparty
        );

        if (vector::is_empty(connection_end::version_features(&version))) {
            connection_end::set_versions(&mut connection, get_compatible_versions());
        } else {
            if (!is_supported_version(&get_compatible_versions(), &version)) {
                abort E_UNSUPPORTED_VERSION
            };

            connection_end::set_versions(&mut connection, vector<connection_end::Version>[version]);
        };

        smart_table::upsert(&mut store.connections, connection_id, connection);

        update_connection_commitment(store, connection_id, connection);

        event::emit(
                ConnectionOpenInit {
                    connection_id: connection_id,
                    client_id: client_id,
                    counterparty_client_id: *connection_end::conn_counterparty_client_id(&connection)
                },
            );
    }

    public entry fun connection_open_try(
        counterparty_client_id: String,
        counterparty_connection_id: String,
        counterparty_prefix: vector<u8>,
        delay_period: u64,
        client_id: String,
        client_state_bytes: vector<u8>,
        counterparty_version_identifiers: vector<String>,
        counterparty_version_features: vector<vector<String>>,
        proof_init: vector<u8>,
        proof_client: vector<u8>,
        proof_height_revision_num: u64,
        proof_height_revision_height: u64,
    ) acquires IBCStore {
        let counterparty = connection_end::new_counterparty(counterparty_client_id, counterparty_connection_id, counterparty_prefix);
        let counterparty_versions = connection_end::new_versions(counterparty_version_identifiers, counterparty_version_features);
        let proof_height = height::new(proof_height_revision_num, proof_height_revision_height);

        assert!(LightClient::status(&client_id) == 0, E_CLIENT_NOT_ACTIVE);

        // Generate a new connection identifier
        let connection_id = generate_connection_identifier();

        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        // Retrieve the connection from the store
        let connection = smart_table::borrow_mut_with_default(
            &mut store.connections,
            connection_id,
            connection_end::new(
                client_id,
                vector[pick_version(&get_compatible_versions(), &counterparty_versions)],
                CONN_STATE_TRYOPEN,
                delay_period,
                counterparty
            )
        );

        // Create the expected connection
        let expected_connection = connection_end::new(
            *connection_end::conn_counterparty_client_id(connection),
            counterparty_versions,
            CONN_STATE_INIT,
            delay_period,
            connection_end::new_counterparty(client_id, string::utf8(b""), b"ibc")
        );

        // Verify the connection state
        let err = verify_connection_state(
            connection,
            proof_height,
            proof_init,
            *connection_end::counterparty_connection_id(&counterparty),
            expected_connection
        ); 
        assert!(err == 0, E_INVALID_PROOF);
        

        let counterparty_client_id = connection_end::conn_counterparty_client_id(connection);

        // Verify the client state
        let err = verify_client_state(
            connection,
            proof_height,
            IBCCommitment::client_state_commitment_key(*counterparty_client_id),
            proof_client,
            client_state_bytes
        );
        assert!(err == 0, E_INVALID_PROOF);

        event::emit(
            ConnectionOpenTry {
                connection_id,
                client_id: client_id,
                counterparty_client_id: *connection_end::conn_counterparty_client_id(connection),
                counterparty_connection_id: *connection_end::conn_counterparty_connection_id(connection),
            },
        );

        update_connection_commitment(store, connection_id, *connection);
    }

    public entry fun connection_open_ack(
        connection_id: String,
        client_state_bytes: vector<u8>,
        version_identifier: String,
        version_features: vector<String>,
        proof_try: vector<u8>,
        proof_client: vector<u8>,
        counterparty_connection_id: String,
        proof_height_revision_num: u64,
        proof_height_revision_height: u64,
    ) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let version = connection_end::new_version(version_identifier, version_features);
        let proof_height = height::new(proof_height_revision_num, proof_height_revision_height);

        if (!smart_table::contains(&store.connections, connection_id)) {
            abort E_CONNECTION_DOES_NOT_EXIST
        };

        let connection = smart_table::borrow_mut(
            &mut store.connections,
            connection_id,
        );

        if (connection_end::state(connection) != CONN_STATE_INIT) {
            abort E_INVALID_CONNECTION_STATE
        };

        if (!is_supported_version(connection_end::versions(connection), &version)) {
            abort E_UNSUPPORTED_VERSION
        };

        let expected_counterparty = connection_end::new_counterparty(
            *connection_end::client_id(connection),
            connection_id,
            b"ibc",
        );

        let expected_connection = connection_end::new(
            *connection_end::conn_counterparty_client_id(connection),
            vector::singleton(version),
            CONN_STATE_TRYOPEN,
            connection_end::delay_period(connection),
            expected_counterparty
        );

        let err = verify_connection_state(
            connection,
            proof_height,
            proof_try,
            counterparty_connection_id,
            expected_connection
        );
        assert!(err == 0, E_INVALID_PROOF);

        let counterparty_client_id = *connection_end::conn_counterparty_client_id(connection);

        let err = verify_client_state(
            connection,
            proof_height,
            IBCCommitment::client_state_commitment_key(counterparty_client_id),
            proof_client,
            client_state_bytes
        );
        assert!(err == 0, E_INVALID_PROOF);

        connection_end::set_state(connection, CONN_STATE_OPEN);

        let conn_versions = *connection_end::versions(connection);
        copy_versions(&vector::singleton(version), &mut conn_versions);
        connection_end::set_versions(connection, conn_versions);
        connection_end::set_conn_counterparty_connection_id(connection, counterparty_connection_id);

        event::emit(
            ConnectionOpenAck {
                connection_id,
                client_id: *connection_end::client_id(connection),
                counterparty_client_id: *connection_end::conn_counterparty_client_id(connection),
                counterparty_connection_id: *connection_end::conn_counterparty_connection_id(connection),
            },
        );

        update_connection_commitment(store, connection_id, *connection);
    }

    public entry fun connection_open_confirm(
        connection_id: String,
        proof_ack: vector<u8>,
        proof_height_revision_num: u64,
        proof_height_revision_height: u64,
    ) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let proof_height = height::new(proof_height_revision_num, proof_height_revision_height);

        let connection = smart_table::borrow_mut(
            &mut store.connections,
            connection_id,
        );

        if (connection_end::state(connection) != CONN_STATE_TRYOPEN) {
            abort E_INVALID_CONNECTION_STATE
        };

        let expected_counterparty = connection_end::new_counterparty(
            *connection_end::client_id(connection),
            connection_id,
            b"ibc",
        );

        let expected_connection = connection_end::new(
            *connection_end::conn_counterparty_client_id(connection),
            *connection_end::versions(connection),
            CONN_STATE_OPEN,
            connection_end::delay_period(connection),
            expected_counterparty
        );

        let counterparty_conn_id = *connection_end::conn_counterparty_connection_id(connection);

        let err = verify_connection_state(
            connection,
            proof_height,
            proof_ack,
            counterparty_conn_id,
            expected_connection
        );
        assert!(err == 0, E_INVALID_PROOF);

        connection_end::set_state(connection, CONN_STATE_OPEN);

        event::emit(
            ConnectionOpenConfirm {
                connection_id,
                client_id: *connection_end::client_id(connection),
                counterparty_client_id: *connection_end::conn_counterparty_client_id(connection),
                counterparty_connection_id: *connection_end::conn_counterparty_connection_id(connection),
            },
        );

        update_connection_commitment(store, connection_id, *connection);
    }

    public entry fun update_client(client_id: String, client_message: vector<u8>) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        if (!table::contains(&store.commitments, IBCCommitment::client_state_commitment_key(client_id))) {
            abort E_CLIENT_NOT_FOUND
        };

        let (client_state, consensus_states, heights, err) = LightClient::update_client(
            client_id,
            client_message
        );

        assert!(err == 0, err);

        let heights_len = vector::length(&heights); 

        assert!(
            !vector::is_empty(&consensus_states) 
                && !vector::is_empty(&heights) 
                && heights_len == vector::length(&consensus_states), 
            E_INVALID_UPDATE
        );
        
        table::upsert(&mut store.commitments, IBCCommitment::client_state_commitment_key(client_id), hash::sha2_256(client_state));

        let i = 0;
        while (i < heights_len) {
            let height = *vector::borrow(&heights, i);

            table::upsert(
                &mut store.commitments,
                IBCCommitment::consensus_state_commitment_key(client_id, height),
                hash::sha2_256(*vector::borrow(&consensus_states, i))
            );

            event::emit(ClientUpdated {
                client_id,
                height,
            });

            i = i + 1;
        };
    }

    public fun channel_open_init(
        ibc_app: &signer, // this is the caller which should be the `ibc_app`
        port_id: String,
        connection_hops: vector<String>,
        ordering: u8,
        counterparty: channel::Counterparty,
        version: String,
    ): (Channel, u64) acquires IBCStore {
        if (!is_lowercase(&port_id)) {
            abort E_PORT_ID_MUST_BE_LOWERCASE
        };

        let (connection_id, _) = ensure_connection_feature(
            connection_hops,
            ordering,
        );

        if (!string::is_empty(channel::counterparty_channel_id(&counterparty))) {
            abort E_COUNTERPARTY_CHANNEL_NOT_EMPTY
        };

        let channel_id = generate_channel_identifier();

        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        let channel_port = ChannelPort{port_id, channel_id};
        let channel = channel::new(CHAN_STATE_INIT, ordering, counterparty, connection_hops, version);
        smart_table::upsert(&mut store.channels, channel_port, channel);
        
        table::upsert(
            &mut store.commitments,
            IBCCommitment::next_sequence_send_commitment_key(port_id, channel_id),
            bcs::to_bytes(&1)
        );

        table::upsert(
            &mut store.commitments,
            IBCCommitment::next_sequence_recv_commitment_key(port_id, channel_id),
            bcs::to_bytes(&1)
        );

        table::upsert(
            &mut store.commitments,
            IBCCommitment::next_sequence_ack_commitment_key(port_id, channel_id),
            bcs::to_bytes(&1)
        );

        event::emit(
            ChannelOpenInit {
                port_id: port_id,
                channel_id: channel_id,
                counterparty_port_id: *channel::chan_counterparty_port_id(&channel),
                connection_id: connection_id,
                version: *channel::version(&channel)
            },
        );
        update_channel_commitment(port_id, channel_id);

        claim_capability(
            port_id, 
            channel_id,
            signer::address_of(ibc_app),
        );

        (channel, 0)
    }

    public fun channel_open_try(
        ibc_app: &signer,
        port_id: String,
        connection_hops: vector<String>,
        ordering: u8,
        counterparty: channel::Counterparty,
        counterparty_version: String,
        version: String,
        proof_init: vector<u8>,
        proof_height: height::Height
    ): (Channel, u64) acquires IBCStore {
        let (connection_id, connection) = ensure_connection_feature(connection_hops, ordering);
        
        let expected_counterparty = channel::new_counterparty(port_id, string::utf8(b""));
        let expected_channel = channel::new(
            CHAN_STATE_INIT,
            ordering,
            expected_counterparty,
            get_counterparty_hops(*vector::borrow(&connection_hops, 0)),
            counterparty_version
        );

        let err = verify_channel_state(
            &connection,
            proof_height,
            proof_init,
            *channel::counterparty_port_id(&counterparty),
            *channel::counterparty_channel_id(&counterparty),
            bcs::to_bytes(&expected_channel)
        );
        assert!(err == 0, E_INVALID_PROOF);

        let channel_id = generate_channel_identifier();

        event::emit(
            ChannelOpenTry {
                port_id,
                channel_id,
                counterparty_port_id: *channel::counterparty_port_id(&counterparty),
                counterparty_channel_id: *channel::counterparty_channel_id(&counterparty),
                connection_id,
                version: counterparty_version
            },
        );

        let channel_port = ChannelPort { port_id, channel_id };
        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        let channel = channel::new(CHAN_STATE_TRYOPEN, ordering, counterparty, connection_hops, version);
        smart_table::upsert(&mut store.channels, channel_port, channel);

        table::upsert(
            &mut store.commitments,
            IBCCommitment::next_sequence_send_commitment_key(port_id, channel_id),
            bcs::to_bytes(&1)
        );

        table::upsert(
            &mut store.commitments,
            IBCCommitment::next_sequence_recv_commitment_key(port_id, channel_id),
            bcs::to_bytes(&1)
        );

        table::upsert(
            &mut store.commitments,
            IBCCommitment::next_sequence_ack_commitment_key(port_id, channel_id),
            bcs::to_bytes(&1)
        );

        update_channel_commitment(port_id, channel_id);

        claim_capability(
            port_id,
            channel_id,
            signer::address_of(ibc_app),
        );

        (channel, 0)
    }

    // TODO(aeryz): should we verify the caller here?
    public fun channel_open_ack(
        ibc_app: &signer, // this is the caller which should be the `ibc_app`
        port_id: String,
        channel_id: String,
        counterparty_channel_id: String,
        counterparty_version: String,
        proof_try: vector<u8>,
        proof_height: height::Height
    ) acquires IBCStore {
        // Retrieve the channel from the store
        let channel_port = ChannelPort { port_id, channel_id };
        let chan = *smart_table::borrow(&borrow_global<IBCStore>(get_vault_addr()).channels, channel_port);

        if (!authenticate_capability(ibc_app, port_id, channel_id)) {
            abort E_UNAUTHORIZED
        };

        if (channel::state(&chan) != CHAN_STATE_INIT) {
            abort E_INVALID_CHANNEL_STATE
        };

        let connection = ensure_connection_state(*vector::borrow(channel::connection_hops(&chan), 0));

        let expected_counterparty = channel::new_counterparty(port_id, channel_id);
        let expected_channel = channel::new(
            CHAN_STATE_INIT,
            channel::ordering(&chan),
            expected_counterparty,
            get_counterparty_hops(*vector::borrow(channel::connection_hops(&chan), 0)),
            counterparty_version
        );

        let err = verify_channel_state(
            &connection,
            proof_height,
            proof_try,
            *channel::chan_counterparty_port_id(&chan),
            counterparty_channel_id,
            bcs::to_bytes(&expected_channel)
        );
        assert!(err == 0, E_INVALID_PROOF);

        update_channel_commitment(port_id, channel_id);

        channel::set_state(&mut chan, CHAN_STATE_OPEN);
        channel::set_version(&mut chan, counterparty_version);
        channel::set_chan_counterparty_channel_id(&mut chan, counterparty_channel_id);

        smart_table::upsert(&mut borrow_global_mut<IBCStore>(get_vault_addr()).channels, channel_port, chan);

        event::emit(
            ChannelOpenAck {
                port_id,
                channel_id,
                counterparty_port_id: *channel::chan_counterparty_port_id(&chan),
                counterparty_channel_id,
                connection_id: *vector::borrow(channel::connection_hops(&chan), 0)
            },
        );
    }

    public fun channel_open_confirm(
        ibc_app: &signer,
        port_id: String,
        channel_id: String,
        proof_ack: vector<u8>,
        proof_height: height::Height
    ) acquires IBCStore {
        // Retrieve the channel from the store
        let channel_port = ChannelPort { port_id, channel_id };
        let channel = *smart_table::borrow(&borrow_global<IBCStore>(get_vault_addr()).channels, channel_port);

        if (!authenticate_capability(ibc_app, port_id, channel_id)) {
            abort E_UNAUTHORIZED
        };

        if (channel::state(&channel) != CHAN_STATE_TRYOPEN) {
            abort E_INVALID_CHANNEL_STATE
        };

        let connection = ensure_connection_state(*vector::borrow(channel::connection_hops(&channel), 0));

        let expected_counterparty = channel::new_counterparty(port_id, channel_id);
        let expected_channel = channel::new(
            CHAN_STATE_OPEN,
            channel::ordering(&channel),
            expected_counterparty,
            get_counterparty_hops(*vector::borrow(channel::connection_hops(&channel), 0)),
            *channel::version(&channel),
        );

        let err = verify_channel_state(
            &connection,
            proof_height,
            proof_ack,
            *channel::chan_counterparty_port_id(&channel),
            *channel::chan_counterparty_channel_id(&channel),
            bcs::to_bytes(&expected_channel)
        );
        assert!(err == 0, E_INVALID_PROOF);

        channel::set_state(&mut channel, CHAN_STATE_OPEN);
        update_channel_commitment(port_id, channel_id);

        smart_table::upsert(&mut borrow_global_mut<IBCStore>(get_vault_addr()).channels, channel_port, channel);

        event::emit(
            ChannelOpenConfirm {
                port_id,
                channel_id,
                counterparty_port_id: *channel::chan_counterparty_port_id(&channel),
                counterparty_channel_id: *channel::chan_counterparty_channel_id(&channel),
                connection_id: *vector::borrow(channel::connection_hops(&channel), 0)
            },
        );
    }

    // ========= UTILS and VIEW functions ========= //

    public fun get_ibc_signer(): signer acquires SignerRef {
        let vault = borrow_global<SignerRef>(get_vault_addr());
        object::generate_signer_for_extending(&vault.self_ref)
    }


    public fun default_ibc_version(): connection_end::Version {
        connection_end::new_version(
            string::utf8(b"1"),
            vector<String>[string::utf8(b"ORDER_ORDERED"), string::utf8(b"ORDER_UNORDERED")],
        )
    }

    public fun set_supported_versions(
        supported_versions: vector<connection_end::Version>,
        dst: &mut vector<connection_end::Version>
    ) {
        assert!(vector::length(dst) == 0, E_VERSION_MUST_BE_UNSET);
        vector::append(dst, supported_versions);
    }

    public fun is_supported_version(
        supported_versions: &vector<connection_end::Version>,
        version: &connection_end::Version
    ): bool {
        let (supported_version, found) = find_supported_version(supported_versions, version);
        if(found && verify_proposed_version(&supported_version, version)) {
            return true
        };
        false
        // found && verify_proposed_version(&supported_version, version)
    }

    public fun get_feature_set_intersection(
        source_features: &vector<String>,
        counterparty_features: &vector<String>
    ): vector<String> {
        let feature_set = vector::empty<String>();
        let source_len = vector::length(source_features);
        let i = 0;
        while (i < source_len) {
            let feature = vector::borrow(source_features, i);
            if (vector::contains(counterparty_features, feature)) {
                vector::push_back(&mut feature_set, *feature);
            };
            i = i + 1;
        };
        feature_set
    }


    public fun pick_version(
        supported_versions: &vector<connection_end::Version>,
        counterparty_versions: &vector<connection_end::Version>
    ): connection_end::Version  {
        let supported_len = vector::length(supported_versions);
        let i = 0;
        while (i < supported_len) {
            let supported_version = vector::borrow(supported_versions, i);
            let (counterparty_version, found) = find_supported_version(counterparty_versions, supported_version);
            if (found) {
                let feature_set = get_feature_set_intersection(connection_end::version_features(supported_version), connection_end::version_features(&counterparty_version));
                if (vector::length(&feature_set) > 0) {
                    return connection_end::new_version(*connection_end::version_identifier(supported_version), feature_set)
                };
            };
            i = i + 1;
        };
        abort E_UNSUPPORTED_VERSION
    }

    public fun copy_version(src: &connection_end::Version, dst: &mut connection_end::Version) {
        connection_end::set_version_identifier(dst, *connection_end::version_identifier(src));
        let src_len = vector::length(connection_end::version_features(src));
        let dst_len = vector::length(connection_end::version_features(dst));
        let i = 0;
        let dst_features = connection_end::version_features_mut(dst);
        while (i < src_len) {
            if (i < dst_len) {
                let src_feature = vector::borrow(connection_end::version_features(src), i);
                let dst_feature = vector::borrow_mut(dst_features, i);
                *dst_feature = *src_feature;
            } else {
                let src_feature = vector::borrow(connection_end::version_features(src), i);
                vector::push_back(dst_features, *src_feature);
            };
            i = i + 1;
        };
        while (i < dst_len) {
            vector::remove(dst_features, i);
            i = i + 1;
        }
    }

    public fun copy_versions(src: &vector<connection_end::Version>, dst: &mut vector<connection_end::Version>) {
        let src_len = vector::length(src);
        let dst_len = vector::length(dst);
        if (src_len == dst_len) {
            let i = 0;
            while (i < src_len) {
                let src_version = vector::borrow(src, i);
                let dst_version = vector::borrow_mut(dst, i);
                copy_version(src_version, dst_version);
                i = i + 1;
            };
        } else if (src_len > dst_len) {
            let i = 0;
            while (i < dst_len) {
                let src_version = vector::borrow(src, i);
                let dst_version = vector::borrow_mut(dst, i);
                copy_version(src_version, dst_version);
                i = i + 1;
            };
            let j = dst_len;
            while (j < src_len) {
                let src_version = vector::borrow(src, j);
                vector::push_back(dst, *src_version);
                j = j + 1;
            };
        } else {
            let i = 0;
            while (i < src_len) {
                let src_version = vector::borrow(src, i);
                let dst_version = vector::borrow_mut(dst, i);
                copy_version(src_version, dst_version);
                i = i + 1;
            };
            let j = src_len;
            while (j < dst_len) {
                vector::remove(dst, j);
                j = j + 1;
            };
        }
    }


    public fun find_supported_version(
        supported_versions: &vector<connection_end::Version>,
        version: &connection_end::Version
    ): (connection_end::Version, bool) {
        let found_version = connection_end::default_version();
        let found = false;
        let len_supported_versions = vector::length(supported_versions);
        let i = 0;
        while(i < len_supported_versions) {
            let v = vector::borrow(supported_versions, i);
            if (connection_end::version_identifier(v) == connection_end::version_identifier(version)) {
                found_version = *v;
                found = true;
                break
            };
            i = i + 1;
        };
        (found_version, found)
    }

    public fun verify_proposed_version(
        supported_version: &connection_end::Version,
        proposed_version: &connection_end::Version
    ): bool {
        let is_supported = false;
        if(connection_end::version_identifier(supported_version) == connection_end::version_identifier(proposed_version)) {
            let len_proposed_version = vector::length(connection_end::version_features(proposed_version));
            let i = 0;
            while(i < len_proposed_version) {
                let feature = vector::borrow(connection_end::version_features(proposed_version), i);
                is_supported = vector::contains(connection_end::version_features(supported_version), feature);
                if(!is_supported) {
                    break
                };
                i = i + 1;
            };
        };
        is_supported
    }

    public fun verify_client_state(
        connection: &ConnectionEnd,
        height: height::Height,
        path: vector<u8>,
        proof: vector<u8>,
        client_state_bytes: vector<u8>
    ): u64 {
        LightClient::verify_membership(
            *connection_end::client_id(connection),
            height,
            proof,
            *connection_end::conn_counterparty_key_prefix(connection),
            path,
            client_state_bytes
        )
    }

    public fun verify_connection_state(
        connection: &ConnectionEnd,
        height: height::Height,
        proof: vector<u8>,
        connection_id: String,
        counterparty_connection: ConnectionEnd
    ): u64 {
        LightClient::verify_membership(
            *connection_end::client_id(connection),
            height,
            proof,
            *connection_end::conn_counterparty_key_prefix(connection),
            bcs::to_bytes(&IBCCommitment::connection_path(connection_id)),
            connection_end::encode_proto(counterparty_connection)
        )
    }

    public fun verify_commitment(
        connection: &ConnectionEnd,
        height: Height,
        proof: vector<u8>,
        path: String,
        commitment: vector<u8>,
    ): u64 {
        LightClient::verify_membership(
            *connection_end::client_id(connection),
            height,
            proof,
            *connection_end::conn_counterparty_key_prefix(connection),
            *string::bytes(&path),
            commitment
        )
    }

    public fun generate_connection_identifier(): String acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let next_sequence_bytes = table::borrow_with_default(
            &store.commitments,
            b"nextConnectionSequence",
            &bcs::to_bytes<u64>(&0)
        );
        let next_sequence = from_bcs::to_u64(*next_sequence_bytes);
        table::upsert(
            &mut store.commitments,
            b"nextConnectionSequence",
            bcs::to_bytes(&(next_sequence + 1))
        );

        string_utils::format1(&b"connection-{}", next_sequence)
    }

    public fun update_connection_commitment(store: &mut IBCStore, connection_id: String, connection: ConnectionEnd) {
        let encoded_connection = connection_end::encode_proto(connection);
        let key = IBCCommitment::connection_commitment_key(connection_id);
        let hash = hash::sha2_256(encoded_connection);
        table::upsert(&mut store.commitments, key, hash);
    }

    public fun get_compatible_versions(): vector<connection_end::Version> {
        vector<connection_end::Version>[default_ibc_version()]
    }

    // Returns connection by `connection_id`. Aborts if the connection does not exist.
    #[view]
    public fun get_connection(connection_id: String): ConnectionEnd acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());

        *smart_table::borrow(
            &store.connections,
            connection_id,
        )
    }

    // Getter function to retrieve a connection commitment by its ID
    #[view]
    public fun get_connection_commitment(connection_id: String): vector<u8> acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let key = IBCCommitment::connection_commitment_key(connection_id);
        *table::borrow(
            &store.commitments,
            key,
        )
    }

    public fun verify_supported_feature(version: &connection_end::Version, feature: String): bool {
        let i = 0;
        while (i < vector::length(connection_end::version_features(version))) {
            if (*vector::borrow(connection_end::version_features(version), i) == feature) {
                return true
            };
            i = i + 1;
        };
        false
    }

    public fun to_string(ordering: u8): String {
        let return_val = string::utf8(b"ORDER_INVALID");
        if (ordering == 1) { // Order.ORDER_UNORDERED
            return_val = string::utf8(b"ORDER_UNORDERED");
        } else if (ordering == 2) { // Order.ORDER_ORDERED
            return_val = string::utf8(b"ORDER_ORDERED");
        };
        return_val
    }


    public fun get_counterparty_hops(connection_id: String): vector<String> acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let connection = smart_table::borrow(
            &store.connections,
            connection_id,
        );
        let hops = vector::empty<String>();
        vector::push_back(&mut hops, *connection_end::conn_counterparty_connection_id(connection));
        hops
    }

    public fun generate_channel_identifier(): String acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let next_sequence_bytes = table::borrow_with_default(
            &store.commitments,
            b"nextChannelSequence",
            &bcs::to_bytes<u64>(&0)
        );
        let next_sequence = from_bcs::to_u64(*next_sequence_bytes);
        let identifier = string::utf8(b"channel-");
        string::append(&mut identifier, string_utils::to_string(&next_sequence));
        let new_sequence = next_sequence + 1;
        table::upsert(
            &mut store.commitments,
            b"nextChannelSequence",
            bcs::to_bytes(&new_sequence)
        );
        identifier
    }

    public fun ensure_connection_state(connection_id: String): ConnectionEnd acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let connection = smart_table::borrow(
            &store.connections,
            connection_id,
        );
        if (connection_end::state(connection) != CONN_STATE_OPEN) {
            abort E_INVALID_CONNECTION_STATE
        };
        *connection
    }

    // TODO(aeryz): borrow instead of copy
    public fun ensure_connection_feature(connection_hops: vector<String>, ordering: u8): (String, ConnectionEnd) acquires IBCStore {
        if (vector::length(&connection_hops) != 1) {
            abort E_CONN_NOT_SINGLE_HOP
        };
        let connection_id = *vector::borrow(&connection_hops, 0);
        let connection = ensure_connection_state(connection_id);
        if (vector::length(connection_end::versions(&connection)) != 1) {
            abort E_CONN_NOT_SINGLE_VERSION
        };
        let version = *vector::borrow(connection_end::versions(&connection), 0);
        if (!verify_supported_feature(&version, to_string(ordering))) {
            abort E_UNSUPPORTED_FEATURE
        };
        (connection_id, connection)
    }

    // TODO: Here the implementation returns false if there is any uppercase character in the string
    // eg: "portId" will return false but "port-0" will return true. Is this correct way to check?
    public fun is_lowercase(s: &String): bool {
        let bytes = bcs::to_bytes(s);
        let i = 1; // First byte is the length of the string
        while (i < vector::length(&bytes)) {
            let byte = *vector::borrow(&bytes, i);
            // if (byte < 0x61 || byte > 0x7A) { // ASCII values for 'a' and 'z'
            //     return false;
            // };
            if (byte > 0x40 && byte < 0x5b) {
                return false
            };
            i = i + 1;
        };
        true
    }
    
    public fun update_channel_commitment(port_id: String, channel_id: String) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let channel_port = ChannelPort{port_id:port_id, channel_id};
        let channel = smart_table::borrow(
            &store.channels,
            channel_port
        );

        let encoded = channel::encode_proto(*channel);
        let key = IBCCommitment::channel_commitment_key(port_id, channel_id);
        table::upsert(&mut store.commitments, key, hash::sha2_256(encoded));
    }


    public fun verify_channel_state(
        connection: &ConnectionEnd,
        height: height::Height,
        proof: vector<u8>,
        port_id: String,
        channel_id: String,
        channel_bytes: vector<u8>
    ): u64 {
        let path = IBCCommitment::channel_commitment_key(port_id, channel_id);
        LightClient::verify_membership(
            *connection_end::client_id(connection),
            height,
            proof,
            *connection_end::conn_counterparty_key_prefix(connection),
            path,
            channel_bytes
        )
    }

    public fun claim_capability(port_id: String, channel_id: String, addr: address) acquires IBCStore {
        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let default_addr: address = @0x0;
        let capability = IBCCommitment::channel_capability(port_id, channel_id);
        let existing_addr = smart_table::borrow_with_default(
            &store.capabilities,
            capability,
            &default_addr
        );
        if (*existing_addr != default_addr) {
            abort E_CAPABILITY_ALREADY_CLAIMED
        };
        smart_table::upsert(&mut store.capabilities, capability, addr);
    }

    public fun create_new_table(): SmartTable<String, SmartTable<String, Channel>> {
        let channel_table = smart_table::new<String, SmartTable<String, Channel>>();
        channel_table
    }

    // Ensures that the channel state is open
    public fun ensure_channel_state(
        port_id: String,
        channel_id: String
    ): Channel acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let channel_port = ChannelPort { port_id, channel_id };
        let channel = smart_table::borrow(&store.channels, channel_port);

        if (channel::state(channel) != CHAN_STATE_OPEN) {
            abort E_INVALID_CHANNEL_STATE
        };
        *channel
    }

    // Authenticates the capability
    public fun authenticate_capability(
        caller: &signer,
        port_id: String,
        channel_id: String,
    ): bool acquires IBCStore {
        let store = borrow_global<IBCStore>(get_vault_addr());
        let capability_addr = smart_table::borrow_with_default(
            &store.capabilities,
            IBCCommitment::channel_capability(port_id, channel_id),
            &@0x0
        );
        signer::address_of(caller) == *capability_addr
    }

    // Sends a packet
    public fun send_packet(
        caller: &signer,
        source_channel: String,
        timeout_height: height::Height,
        timeout_timestamp: u64,
        data: vector<u8>
    ): u64 acquires IBCStore {
        let caller_addr = signer::address_of(caller);
        let source_port = string_utils::to_string(&caller_addr);
        // let source_port = &signer::address_of(borrow_global<SignerRef>(get_vault_addr()).signer_ref));

        // Authenticate capability
        if (!authenticate_capability(caller, source_port, source_channel)) {
            abort E_UNAUTHORIZED
        };

        let channel = ensure_channel_state(source_port, source_channel);

        let client_id = *vector::borrow(channel::connection_hops(&channel), 0);

        let latest_height = LightClient::latest_height(client_id);
    
        if (height::get_revision_height(&latest_height) == 0) {
            abort E_LATEST_HEIGHT_NOT_FOUND
        };
        if (!height::is_zero(&timeout_height) && height::gte(&latest_height, &timeout_height)) {
            abort E_INVALID_TIMEOUT_HEIGHT
        };

        let latest_timestamp = LightClient::get_timestamp_at_height(client_id, latest_height);
        if (latest_timestamp == 0) {
            abort E_LATEST_TIMESTAMP_NOT_FOUND
        };
        if (timeout_timestamp != 0 && latest_timestamp >= timeout_timestamp) {
            abort E_INVALID_TIMEOUT_TIMESTAMP
        };

        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        let packet_sequence = from_bcs::to_u64(
            *table::borrow_with_default(
                &store.commitments,
                IBCCommitment::next_sequence_send_commitment_key(source_port, source_channel),
                &bcs::to_bytes(&0u64)
            )
        );
        table::upsert(
            &mut store.commitments,
            IBCCommitment::next_sequence_send_commitment_key(source_port, source_channel),
            bcs::to_bytes(&(packet_sequence + 1))
        );

        table::upsert(
            &mut store.commitments,
            IBCCommitment::packet_commitment_key(source_port, source_channel, packet_sequence),            
            packet::commitment_from_parts(timeout_timestamp, timeout_height, data),
        );

        event::emit(SendPacket {
            sequence: packet_sequence,
            source_port,
            source_channel,
            timeout_height,
            timeout_timestamp,
            data
        });

        packet_sequence
    }

    /// Receives and processes an IBC packet
    ///
    /// Note that any sanity check failures will result in this function to be aborted in order for caller's
    /// storage to be reverted. This will result in acks won't be able to written.
    public fun recv_packet(
        caller: &signer,
        msg_port_id: String,
        msg_channel_id: String,
        msg_packet: Packet,
        msg_proof: vector<u8>,
        msg_proof_height: height::Height,
        acknowledgement: vector<u8>
    ) acquires IBCStore {
        if (!authenticate_capability(caller, msg_port_id, msg_channel_id)) {
            abort E_UNAUTHORIZED
        };

        let channel = ensure_channel_state(msg_port_id, msg_channel_id);

        if (packet::source_port(&msg_packet) != channel::chan_counterparty_port_id(&channel)) {
            abort E_SOURCE_AND_COUNTERPARTY_PORT_MISMATCH
        };

        if (packet::source_channel(&msg_packet) != channel::chan_counterparty_channel_id(&channel)) {
            abort E_SOURCE_AND_COUNTERPARTY_CHANNEL_MISMATCH
        };

        let connection_hop = *vector::borrow(channel::connection_hops(&channel), 0);
        let store = borrow_global<IBCStore>(get_vault_addr());
        
        let connection = smart_table::borrow(
            &store.connections,
            connection_hop,
        );
        
        if (connection_end::state(connection) != CONN_STATE_OPEN) {
            abort E_INVALID_CONNECTION_STATE
        };

        if (height::get_revision_height(&packet::timeout_height(&msg_packet)) != 0 && (timestamp::now_seconds() * 1000000000 >= height::get_revision_height(&packet::timeout_height(&msg_packet)))) {
            abort E_HEIGHT_TIMEOUT
        };

        let current_timestamp = timestamp::now_seconds() * 1000000000; // 1e9
        if (packet::timeout_timestamp (&msg_packet)!= 0 && (current_timestamp >= packet::timeout_timestamp(&msg_packet))) {
            abort E_TIMESTAMP_TIMEOUT
        };


        let err = verify_commitment(
            connection,
            msg_proof_height,
            msg_proof,
            IBCCommitment::packet_commitment_path(*packet::source_port(&msg_packet), *packet::source_channel(&msg_packet), packet::sequence(&msg_packet)),
            packet::commitment(&msg_packet),
        );
        
        if (err != 0) {
            abort err
        };

        let store = borrow_global_mut<IBCStore>(get_vault_addr());

        if (channel::ordering(&channel) == CHAN_ORDERING_UNORDERED) {
            let receipt_commitment_key = IBCCommitment::packet_receipt_commitment_key(*packet::destination_port(&msg_packet), *packet::destination_channel(&msg_packet), packet::sequence(&msg_packet));
            let receipt = table::borrow_with_default(&store.commitments, receipt_commitment_key, &bcs::to_bytes(&0u8));
            if (*receipt != bcs::to_bytes(&0u8)) {
                abort E_PACKET_ALREADY_RECEIVED
            };
            table::upsert(&mut store.commitments, receipt_commitment_key, bcs::to_bytes(&1u8));
        } else if (channel::ordering(&channel) == CHAN_ORDERING_ORDERED) { // ORDER_ORDERED
            let expected_recv_sequence = from_bcs::to_u64(
                *table::borrow_with_default(
                    &store.commitments,
                    IBCCommitment::next_sequence_recv_commitment_key(*packet::destination_port(&msg_packet), *packet::destination_channel(&msg_packet)),
                    &bcs::to_bytes(&0u64)
                )
            );
            if (expected_recv_sequence != packet::sequence(&msg_packet)) {
                abort E_PACKET_SEQUENCE_NEXT_SEQUENCE_MISMATCH
            };
            table::upsert(
                &mut store.commitments,
                IBCCommitment::next_sequence_recv_commitment_key(*packet::destination_port(&msg_packet), *packet::destination_channel(&msg_packet)),
                bcs::to_bytes(&(expected_recv_sequence + 1))
            );
        } else {
            abort E_UNKNOWN_CHANNEL_ORDERING
        };

        if (vector::length(&acknowledgement) > 0) {
            write_ack_impl(msg_packet, acknowledgement);
        };

        event::emit(RecvPacket {
            packet: msg_packet
        });
    }

    public fun write_acknowledgement(
        caller: &signer,
        packet: packet::Packet,
        acknowledgement: vector<u8>
    ) acquires IBCStore {
        if (!authenticate_capability(caller, *packet::destination_port(&packet), *packet::destination_channel(&packet))) {
            abort E_UNAUTHORIZED
        };
        write_ack_impl(packet, acknowledgement);
    }

    public fun write_ack_impl(
        packet: packet::Packet,
        acknowledgement: vector<u8>
    ) acquires IBCStore {
        if (vector::length(&acknowledgement) == 0) {
            abort E_ACKNOWLEDGEMENT_IS_EMPTY
        };

        ensure_channel_state(*packet::destination_port(&packet), *packet::destination_channel(&packet));

        let store = borrow_global_mut<IBCStore>(get_vault_addr());
        let ack_commitment_key = IBCCommitment::packet_acknowledgement_commitment_key(
            *packet::destination_port(&packet),
            *packet::destination_channel(&packet),
            packet::sequence(&packet)
        );
        let ack_commitment = table::borrow_with_default(
            &store.commitments,
            ack_commitment_key,
            &bcs::to_bytes(&0u8)
        );
        if (*ack_commitment != bcs::to_bytes(&0u8)) {
            abort E_ACKNOWLEDGEMENT_ALREADY_EXISTS
        };
        table::upsert(&mut store.commitments, ack_commitment_key, hash::sha2_256(acknowledgement));

        event::emit(WriteAcknowledgement {
            packet,
            acknowledgement
        });
    }

    public fun acknowledge_packet(
        caller: &signer,
        packet: packet::Packet,
        acknowledgement: vector<u8>,
        proof: vector<u8>,
        proof_height: height::Height
    ) acquires IBCStore {
        let port_id = *packet::source_port(&packet);
        let channel_id = *packet::source_channel(&packet);
        
        if (!authenticate_capability(caller, port_id, channel_id)) {
            abort E_UNAUTHORIZED
        };

        let channel = ensure_channel_state(port_id, channel_id);

        if (port_id != *channel::chan_counterparty_port_id(&channel)) {
            abort E_DESTINATION_AND_COUNTERPARTY_PORT_MISMATCH
        };
        if (channel_id != *channel::chan_counterparty_channel_id(&channel)) {
            abort E_DESTINATION_AND_COUNTERPARTY_CHANNEL_MISMATCH
        };

        let connection = ensure_connection_state(*vector::borrow(channel::connection_hops(&channel), 0));

        let packet_commitment_key = IBCCommitment::packet_commitment_key(port_id, channel_id, packet::sequence(&packet));
        let expected_packet_commitment = get_commitment(packet_commitment_key);

        if (vector::length(&expected_packet_commitment) == 0) {
            abort E_PACKET_COMMITMENT_NOT_FOUND
        };

        if (expected_packet_commitment != packet::commitment(&packet)) {
            abort E_INVALID_PACKET_COMMITMENT
        };

        let err = verify_commitment(
            &connection,
            proof_height,
            proof,
            IBCCommitment::packet_acknowledgement_commitment_path(
                *packet::destination_port(&packet),
                *packet::destination_channel(&packet),
                packet::sequence(&packet)
            ),
            hash::sha2_256(acknowledgement)
        );

        if (err != 0) {
            abort err
        };

        if (channel::ordering(&channel) == CHAN_ORDERING_ORDERED) {
            let expected_ack_sequence = from_bcs::to_u64(
                *table::borrow_with_default(
                    &borrow_global<IBCStore>(get_vault_addr()).commitments,
                    IBCCommitment::next_sequence_ack_commitment_key(port_id, channel_id),
                    &bcs::to_bytes(&0u64)
                )
            );

            if (expected_ack_sequence != packet::sequence(&packet)) {
                abort E_PACKET_SEQUENCE_NEXT_SEQUENCE_MISMATCH
            };

            table::upsert(
                &mut borrow_global_mut<IBCStore>(get_vault_addr()).commitments,
                IBCCommitment::next_sequence_ack_commitment_key(port_id, channel_id),
                bcs::to_bytes(&(expected_ack_sequence + 1))
            );
        };

        table::remove(&mut borrow_global_mut<IBCStore>(get_vault_addr()).commitments, packet_commitment_key);
        
        event::emit(AcknowledgePacket {
            packet,
            acknowledgement
        });
    }

    public fun timeout_packet(
        port_id: String,
        channel_id: String,
        packet: Packet,
        proof: vector<u8>,
        proof_height: height::Height,
        next_sequence_recv: u64
    ) acquires IBCStore {
        let channel = ensure_channel_state(port_id, channel_id);

        if (*packet::destination_port(&packet) != *channel::chan_counterparty_port_id(&channel)) {
            std::debug::print(packet::destination_port(&packet));
            std::debug::print(channel::chan_counterparty_port_id(&channel));
            abort E_DESTINATION_AND_COUNTERPARTY_PORT_MISMATCH
        };
        if (*packet::destination_channel(&packet) != *channel::chan_counterparty_channel_id(&channel)) {
            abort E_DESTINATION_AND_COUNTERPARTY_CHANNEL_MISMATCH
        };

        let connection_hop = *vector::borrow(channel::connection_hops(&channel), 0);
        let connection = ensure_connection_state(connection_hop);

        let packet_commitment_key = IBCCommitment::packet_commitment_key(
            *packet::source_port(&packet),
            *packet::source_channel(&packet),
            packet::sequence(&packet)
        );
        let expected_packet_commitment = get_commitment(packet_commitment_key);
        if (vector::length(&expected_packet_commitment) == 0) {
            abort E_PACKET_COMMITMENT_NOT_FOUND
        };

        let packet_commitment = packet::commitment(&packet);
        if (expected_packet_commitment != packet_commitment) {
            abort E_INVALID_PACKET_COMMITMENT
        };

        let proof_timestamp = LightClient::get_timestamp_at_height(
            *connection_end::client_id(&connection),
            proof_height
        );
        if (proof_timestamp == 0) {
            abort E_LATEST_TIMESTAMP_NOT_FOUND
        };

        if (packet::timeout_timestamp(&packet) != 0 && packet::timeout_timestamp(&packet) >= proof_timestamp) {
            abort E_TIMESTAMP_TIMEOUT_NOT_REACHED
        };
        if (!height::is_zero(&packet::timeout_height(&packet)) && height::gte(&packet::timeout_height(&packet), &proof_height)) {
            abort E_TIMEOUT_HEIGHT_NOT_REACHED
        };

        if (channel::ordering(&channel) == CHAN_ORDERING_ORDERED) {
            if (next_sequence_recv <= packet::sequence(&packet)) {
                abort E_NEXT_SEQUENCE_MUST_BE_GREATER_THAN_TIMEOUT_SEQUENCE
            };
            let err = verify_commitment(
                &connection,
                proof_height,
                proof,
                IBCCommitment::next_sequence_recv_commitment_path(
                    *packet::destination_port(&packet),
                    *packet::destination_channel(&packet)
                ),
                bcs::to_bytes(&next_sequence_recv)
            );
            if (err != 0) {
                abort E_INVALID_PROOF
            };
            channel::set_state(&mut channel, CHAN_STATE_CLOSED);
        } else if (channel::ordering(&channel) == CHAN_ORDERING_UNORDERED) {
            let err = verify_absent_commitment(
                &connection,
                proof_height,
                proof,
                IBCCommitment::packet_receipt_commitment_path(
                    *packet::destination_port(&packet),
                    *packet::destination_channel(&packet),
                    packet::sequence(&packet)
                )
            );
            if (err != 0) {
                abort E_INVALID_PROOF
            };
        } else {
            abort E_UNKNOWN_CHANNEL_ORDERING
        };

        table::remove(&mut borrow_global_mut<IBCStore>(get_vault_addr()).commitments, packet_commitment_key);

        event::emit(TimeoutPacket { packet });
    }

    public fun verify_absent_commitment(
        connection: &ConnectionEnd,
        height: height::Height,
        proof: vector<u8>,
        path: String
    ): u64 {
        LightClient::verify_non_membership(
            *connection_end::client_id(connection),
            height,
            proof,
            *connection_end::conn_counterparty_key_prefix(connection),
            *string::bytes(&path)
        )
    }
}   

module IBC::groth16_verifier {    
    use std::bn254_algebra::{Fr, FormatFrMsb, FormatFrLsb, G1, FormatG1Uncompr,FormatG1Compr, G2, Gt, FormatG2Compr};
    use std::crypto_algebra::{deserialize, serialize, zero, add, scalar_mul, multi_pairing, Element, eq};
    use std::option;
    use std::vector;
    use std::from_bcs;
    use std::aptos_hash;
    use std::hash;
    use std::bcs;
    use std::string::{Self, String};

    const ALPHA_G1: vector<u8> = x"99a818c167016f7f6d02d84005a5ed1f7c6c19c4ddf15733b67acc0129076709ff810d9d3374808069c1ea1e5d263a90cf8181b98b415805797176357acec708";
    const BETA_G2: vector<u8> = x"742884ea18a00ef31874d5fc5511b18fa9391dc69b971b898a2dbfc644033f15656dc92f1f94dc170026cd80212e5160d2539e7e8b40885d1d60b770d25f3599";
    const GAMMA_G2: vector<u8> = x"19b6719e42c42ed1df46fa08c870c5241a52913b65d9b43679e089c2e0bb1622cf3a489ca7927f4f81400a2ebd739a935bceb3224264eff8e248311ae96be7a0";
    const DELTA_G2: vector<u8> = x"eb044ddb951e9b28eda7da93aba341ef2c96a4d6182ca785a32018c9c803d405fcb9f04a31c988a2f5a64710ffafe101831d6147259b54e45d47e0d1184c5e29";
    const PEDERSEN_G: vector<u8> = x"5ae56dc014a8137712f4584658ba6f7e390cc39892f97e56ca859887d8d8f0138719bd9ffa2bba963951da2e08ba92ffc1049ba2f1fd7d7f03b02c13f8f67d25";
    const PEDERSEN_G_ROOT_SIGMA_NEG: vector<u8> = x"af5b4e30123a344339321dd621b5fdf9cd9870625928fa07235f011cdf04a1026863cae2f2b0c0ce457e81ad25a068fb1cb86026096be8e3f75c55a741e1bfaf";
    const GAMMA_ABC_G1: vector<vector<u8>> = vector[x"81925330941d53d8cec1c44210f6c882fee82c4ae97cb64b4f864327e54318270624cb7325a89fea7ad2cbde478a7ba38eca18bba1f024f672b1f89cc6423325" ,
    x"ca4b125d5e1a2ec0e22672434fbe9ca0e3ca15b0c20e16e9020ed6f471be0d0b0ce070b6a8b95f687014d83de09f9efe33caaf16aa92e5ec888376d3eb9a0b13"
    , x"c790c4a1918ab12e7e3c36005b2f5cbcf5408ced98033571760c7cf4d5939e02d9f1ee6a9c13b6ebbe2e11dab23f5600040fcb833bb5798faecf9d451005f12c"];
    const HMAC_O: vector<u8> = x"1F333139281E100F5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C5C";
    const HMAC_I: vector<u8> = x"75595B5342747A653636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636";
    const PRIME_R_MINUS_ONE: vector<u8> = x"000000f093f5e1439170b97948e833285d588181b64550b829a031e1724e6430";
    const COMPR_G1_SIZE: u64 = 32;
    const COMPR_G2_SIZE: u64 = 64;

    struct Proof has drop {
        a: Element<G1>,
        b: Element<G2>,
        c: Element<G1>,
    }

    struct ZKP has drop {
        proof: Proof,
        proof_commitment: Element<G1>,
        proof_commitment_pok: Element<G1>,
    }

    public fun verify_zkp(chain_id: &String, trusted_validators_hash: &vector<u8>, light_header_hash: vector<u8>, zkp: &ZKP): bool {
        let inputs_hash: vector<u8> = vector::empty();
        let i = 0;
        while (i < 32 - string::length(chain_id)) {
            vector::push_back(&mut inputs_hash, 0);
            i = i + 1;
        };
        vector::append(&mut inputs_hash, *string::bytes(chain_id));
        vector::append(&mut inputs_hash, light_header_hash);
        vector::append(&mut inputs_hash, *trusted_validators_hash);

        let inputs_hash = hash::sha2_256(inputs_hash);

        let x = vector::borrow_mut(&mut inputs_hash, 0);
        *x = 0;

        let inputs_hash = option::extract(&mut deserialize<Fr, FormatFrMsb>(&inputs_hash));
        let commitment_hash = hash_commitment(&zkp.proof_commitment);
        let hmac = bcs::to_bytes(&commitment_hash);
        let commitment_hash = option::extract(&mut deserialize<Fr, FormatFrLsb>(&hmac));

        let alpha_g1 = option::extract(&mut deserialize<G1, FormatG1Uncompr>(&ALPHA_G1));

        let beta_g2 = option::extract(&mut deserialize<G2, FormatG2Compr>(&BETA_G2));

        let gamma_g2 = option::extract(&mut deserialize<G2, FormatG2Compr>(&GAMMA_G2));
        let delta_g2 = option::extract(&mut deserialize<G2, FormatG2Compr>(&DELTA_G2));
        let pedersen_g = option::extract(&mut deserialize<G2, FormatG2Compr>(&PEDERSEN_G));
        let pedersen_g_root_sigma_neg = option::extract(&mut deserialize<G2, FormatG2Compr>(&PEDERSEN_G_ROOT_SIGMA_NEG));

        let gamma_abc_1 = option::extract(&mut deserialize<G1, FormatG1Uncompr>(vector::borrow(&mut GAMMA_ABC_G1, 0)));
        let gamma_abc_2 = option::extract(&mut deserialize<G1, FormatG1Uncompr>(vector::borrow(&mut GAMMA_ABC_G1, 1)));
        let gamma_abc_3 = option::extract(&mut deserialize<G1, FormatG1Uncompr>(vector::borrow(&mut GAMMA_ABC_G1, 2)));

        // TODO(aeryz): why is this unused?
        let _res = serialize<Fr, FormatFrLsb>(&commitment_hash);

        let msm_inner = add(&add<G1>(&gamma_abc_1, &zkp.proof_commitment), &scalar_mul<G1, Fr>(&gamma_abc_2, &inputs_hash));
        let public_inputs_msm = add<G1>(&msm_inner, &scalar_mul<G1, Fr>(&gamma_abc_3, &commitment_hash));
        let res = serialize<G1, FormatG1Uncompr>(&public_inputs_msm);
        vector::reverse_slice(&mut res, 0, 32);
        vector::reverse_slice(&mut res, 32, 64);

        let res = multi_pairing<G1, G2, Gt>(
            &vector<Element<G1>>[
                zkp.proof.a, public_inputs_msm, zkp.proof.c, alpha_g1
            ],
            &vector<Element<G2>>[
                zkp.proof.b, gamma_g2, delta_g2, beta_g2
            ]
        );

        if (!eq<Gt>(&res, &zero<Gt>())) {
            return false
        };

        let res = multi_pairing<G1, G2, Gt>(
            &vector<Element<G1>>[
                zkp.proof_commitment, zkp.proof_commitment_pok
            ],
            &vector<Element<G2>>[
                pedersen_g, pedersen_g_root_sigma_neg
            ]
        );

        eq<Gt>(&res, &zero<Gt>())        
    }

    public fun parse_zkp(buf: vector<u8>): ZKP {
        let cursor = 0;

        let a = std::option::extract(&mut deserialize<G1, FormatG1Compr>(&vector::slice(&buf, cursor, cursor + COMPR_G1_SIZE)));
        cursor = cursor + COMPR_G1_SIZE;

        let b = std::option::extract(&mut deserialize<G2, FormatG2Compr>(&vector::slice(&buf, cursor, cursor + COMPR_G2_SIZE)));
        cursor = cursor + COMPR_G2_SIZE;

        let c = std::option::extract(&mut deserialize<G1, FormatG1Compr>(&vector::slice(&buf, cursor, cursor + COMPR_G1_SIZE)));
        cursor = cursor + COMPR_G1_SIZE;

        let proof_commitment = std::option::extract(&mut deserialize<G1, FormatG1Compr>(&vector::slice(&buf, cursor, cursor + COMPR_G1_SIZE)));
        cursor = cursor + COMPR_G1_SIZE;

        let proof_commitment_pok = std::option::extract(&mut deserialize<G1, FormatG1Compr>(&vector::slice(&buf, cursor, cursor + COMPR_G1_SIZE)));

        ZKP {
            proof: Proof {
                a, b, c
            },
            proof_commitment,
            proof_commitment_pok,
        }
    }

   fun hmac_keccak(message: &vector<u8>): vector<u8> {
        let inner = HMAC_I;
        vector::append(&mut inner, *message);
        let outer = HMAC_O;
        vector::append(&mut outer, aptos_hash::keccak256(inner));

        aptos_hash::keccak256(outer)
    }

    fun hash_commitment(proof_commitment: &Element<G1>): u256 {
        let buffer = serialize<G1, FormatG1Uncompr>(proof_commitment);
        vector::reverse_slice(&mut buffer, 0, 32);
        vector::reverse_slice(&mut buffer, 32, 64);
        let hmac = hmac_keccak(&buffer);
        vector::reverse(&mut hmac);

        let prime_r_minus_one = from_bcs::to_u256(PRIME_R_MINUS_ONE);
        let hmac = from_bcs::to_u256(hmac);

        (hmac % prime_r_minus_one) + 1
    }
    

}

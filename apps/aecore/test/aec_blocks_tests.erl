%%%-------------------------------------------------------------------
%%% @copyright (C) 2017, Aeternity Anstalt
%%%-------------------------------------------------------------------

-module(aec_blocks_tests).

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-include("common.hrl").
-include("blocks.hrl").

-define(TEST_MODULE, aec_blocks).

new_block_test_() ->
    {setup,
     fun() ->
             meck:new(aec_txs_trees, [passthrough]),
             meck:new(aec_trees, [passthrough]),
             meck:expect(aec_txs_trees, from_txs, 1, fake_txs_tree),
             meck:expect(
               aec_txs_trees, root_hash,
               fun(fake_txs_tree) ->
                       {ok, <<"fake_txs_tree_hash">>}
               end),
             meck:expect(aec_trees, hash, 1, <<>>)
     end,
     fun(_) ->
             ?assert(meck:validate(aec_txs_trees)),
             ?assert(meck:validate(aec_trees)),
             meck:unload(aec_txs_trees),
             meck:unload(aec_trees)
     end,
     {"Generate new block with given txs and 0 nonce",
      fun() ->
              PrevBlock = #block{height = 11, target = 17,
                                 version = ?GENESIS_VERSION},
              BlockHeader = ?TEST_MODULE:to_header(PrevBlock),

              NewBlock = ?TEST_MODULE:new(PrevBlock, [], aec_trees:new()),

              ?assertEqual(12, ?TEST_MODULE:height(NewBlock)),
              SerializedBlockHeader =
                  aec_headers:serialize_to_binary(BlockHeader),
              ?assertEqual(aec_hash:hash(header, SerializedBlockHeader),
                           ?TEST_MODULE:prev_hash(NewBlock)),
              ?assertEqual(<<"fake_txs_tree_hash">>, NewBlock#block.txs_hash),
              ?assertEqual([], NewBlock#block.txs),
              ?assertEqual(17, NewBlock#block.target),
              ?assertEqual(?GENESIS_VERSION, NewBlock#block.version)
      end}}.

network_serialization_test_() ->
    [{"Serialize/deserialize block with min nonce",
      fun() ->
              B = #block{nonce = 0,
                         version = ?PROTOCOL_VERSION},
              SB = #{} = ?TEST_MODULE:serialize_to_map(B),
              ?assertEqual({ok, B}, ?TEST_MODULE:deserialize_from_map(SB))
      end
     },
     {"Serialize/deserialize block with max nonce",
      fun() ->
              B = #block{nonce = ?MAX_NONCE,
                         version = ?PROTOCOL_VERSION},
              SB = #{} = ?TEST_MODULE:serialize_to_map(B),
              ?assertEqual({ok, B}, ?TEST_MODULE:deserialize_from_map(SB))
      end
     },
     {"try to deserialize a blocks with out-of-range nonce",
      fun() ->
             Block1 = #block{nonce = ?MAX_NONCE + 1,
                             version = ?PROTOCOL_VERSION},
             SerializedBlock1 = #{} = ?TEST_MODULE:serialize_to_map(Block1),
             ?assertEqual({error,bad_nonce},
                          ?TEST_MODULE:deserialize_from_map(SerializedBlock1)),

             Block2 = #block{nonce = -1,
                             version = ?PROTOCOL_VERSION},
             SerializedBlock2 = #{} = ?TEST_MODULE:serialize_to_map(Block2),
             ?assertEqual({error,bad_nonce},
                          ?TEST_MODULE:deserialize_from_map(SerializedBlock2))
     end}].

validate_test_() ->
    {setup,
     fun() ->
             ok = meck:new(aec_chain, [passthrough]),
             meck:expect(aec_chain, get_top_state, 0, {ok, aec_trees:new()}),
             aec_test_utils:aec_keys_setup()
     end,
     fun(TmpKeysDir) ->
             meck:unload(aec_chain),
             ok = aec_test_utils:aec_keys_cleanup(TmpKeysDir)
     end,
     [ {"Multiple coinbase txs in the block",
        fun validate_test_multiple_coinbase/0}
     , {"Malformed txs merkle tree hash",
        fun validate_test_malformed_txs_root_hash/0}
     %, {"Malformed tx signature",
     %   fun validate_test_malformed_tx_signature/0}
     , {"Pass validation",
        fun validate_test_pass_validation/0}
     ]}.

validate_test_multiple_coinbase() ->
    SignedCoinbase = aec_test_utils:signed_coinbase_tx(1),
    Block = #block{txs = [SignedCoinbase, SignedCoinbase],
                   version = ?PROTOCOL_VERSION},

    ?assertEqual({error, multiple_coinbase_txs}, ?TEST_MODULE:validate(Block)).

validate_test_malformed_txs_root_hash() ->
    SignedCoinbase = aec_test_utils:signed_coinbase_tx(1),
    {ok, BadCoinbaseTx} = aec_coinbase_tx:new(#{ account => <<"malformed_account">>,
                                                 block_height => 1}),
    MalformedTxs = [SignedCoinbase, aetx_sign:sign(BadCoinbaseTx, <<0:64/unit:8>>)],
    MalformedTree = aec_txs_trees:from_txs(MalformedTxs),
    {ok, MalformedRootHash} = aec_txs_trees:root_hash(MalformedTree),
    Block = #block{txs = [SignedCoinbase], txs_hash = MalformedRootHash,
                   version = ?PROTOCOL_VERSION},

    ?assertEqual({error, malformed_txs_hash}, ?TEST_MODULE:validate(Block)).

validate_test_malformed_tx_signature() ->
    SignedCoinbase = aec_test_utils:signed_coinbase_tx(1),
    Txs = [{signed_tx, aetx_sign:tx(SignedCoinbase), []}],
    Tree = aec_txs_trees:from_txs(Txs),
    {ok, RootHash} = aec_txs_trees:root_hash(Tree),
    Block = #block{txs = Txs, txs_hash = RootHash,
                   version = ?PROTOCOL_VERSION},

    ?assertEqual({error, invalid_transaction_signature}, ?TEST_MODULE:validate(Block)).

validate_test_pass_validation() ->
    SignedCoinbase = aec_test_utils:signed_coinbase_tx(1),
    Txs = [SignedCoinbase],
    Tree = aec_txs_trees:from_txs(Txs),
    {ok, RootHash} = aec_txs_trees:root_hash(Tree),
    Block = #block{txs = Txs, txs_hash = RootHash,
                   version = ?PROTOCOL_VERSION},

    ?assertEqual(ok, ?TEST_MODULE:validate(Block)).

-endif.

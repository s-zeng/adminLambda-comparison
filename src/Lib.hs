{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}

module Lib where

import Universum hiding ((>>), swap, drop)
import Lorentz
import Michelson.Typed (starNotes)
-- import Universum.Base (String, Typeable)

contractToString :: (NiceParameterFull cp, NiceStorage st) => ContractCode cp st -> String
contractToString = toString . printLorentzContract False . defaultContract

adminLambda :: ContractCode (Lambda Address ([Operation], Address)) Address
adminLambda = do
  dup
  cdr
  dip car
  dup
  sender
  eq
  if Holds
     then exec
     else failWith

adminLambda2 :: ContractCode (Lambda Address ([Operation], Address)) Address
adminLambda2 = do
  dup
  car
  swap
  cdr
  dup
  sender
  eq
  if Holds
     then exec
     else failWith

instance HasAnnotation (Either (Address, Address) (Address, Address)) where
    getAnnotation = const starNotes

adminOperator :: Address -> ContractCode (Bool, Address) Address
adminOperator x = do
  unpair
  unpair
  if Holds
     then do swap
             drop
             nil
     else do self @(Bool, Address)
             address
             pair
             left
             nil
             swap
             cons
             push x
             contract @[Either (Address, Address) (Address, Address)]
             assertSome UnspecifiedError
             push (toMutez 0)
             dip swap
             swap
             transferTokens @[Either (Address, Address) (Address, Address)]
             nil
             swap
             cons
  pair


convertGenericMultisigLambda :: Lambda (Lambda () [Operation], Address) ([Operation], Address)
convertGenericMultisigLambda = do
  unpair
  unit
  exec
  pair

-- public carthagenet faucet
-- faucet.tzalpha.net
-- public node: alpha-client=‘tezos-client -A rpcalpha.tzbeta.net -P 443 -S’
-- to actually deplot:
-- get an account: https://assets.tqtezos.com/docs/setup/1-tezos-client/
-- to originate and call a contract: https://assets.tqtezos.com/docs/token-contracts/fa12/3-fa12-lorentz/

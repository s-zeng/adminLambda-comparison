# Comparison on performance of variations of adminLambda contract

The adminLambda contract written by Michael J. Klein, as described
[here](https://gist.github.com/michaeljklein/a364e6624601f020647bf96e8d4277e0)
and
[here](https://gist.github.com/michaeljklein/e31579ff5c7d12a0f55e95511b5235d5),
has a few possible variations that could make an impact on performance.

This document compares three such variations. This document is a valid haskell
source file which declares all the needed contracts with 
[Lorentz](https://hackage.haskell.org/package/lorentz), written with [Literate
Haskell](https://wiki.haskell.org/Literate_programming), using Markdown as the
substrate layer with the help of 
[markdown-unlit](https://github.com/sol/markdown-unlit).

## The contract variations

To begin, we need to get some header stuff out of the way:

```haskell
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
module Main where
import Universum hiding ((>>), swap, drop)
import Lorentz
import Michelson.Typed (starNotes)
import Tezos.Address
import Text.Printf
```

The original adminLambda contract is copied for reference below:

```haskell
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
```

The first variation to consider is changing some of the early stack manipulation 
commands; in particular, swapping out `CDR; DIP{CAR}` with `CAR; SWAP; CDR` for 
the purpose of unconsing the stack head. This variation can be found below:

```haskell
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
```

Finally, there is also the consideration of splitting the adminLambda contract 
into a variant the focuses just on setting operator, and seeing if specialiazing 
in this way can provide any benefits. Below is the start of an implementation of 
such a specialized variation, excluding a few safety checks and such (if it's 
noticeably better than the others, then it would be worth investigating a more 
complete version of this):

```haskell
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
```

In order for this variation to compile, we need to give GHC some pointers to 
allow it to typecheck:

```haskell
instance HasAnnotation (Either (Address, Address) (Address, Address)) where
    getAnnotation = const starNotes
```

## Writing, originating, and using

In order to compile these contracts down to usable michelson, we have to write
a small helper function:

```haskell
contractToString :: (NiceParameterFull cp, NiceStorage st) => ContractCode cp st -> Text
contractToString = toStrict . printLorentzContract False . defaultContract
```

We can also write a helper to let us quickly originate these contracts:

```haskell
cmd = "tezos-client --wait none originate contract %s transferring 0 from %s running \"$(cat %s | tr -d '\\n')\" --init \"\\\"%s\\\"\" --burn-cap 0.6"
makeCmd :: String -> String -> String -> String
makeCmd addr name file = printf cmd name addr file addr
```

Finally, we need some addresses to interact with these contracts:

```haskell
fred :: Address
fred = ContractAddress $ ContractHash $ fromString "tz1LWiALktZCvcfs2PVfYgHjxZ35ZPZ6diV6"
bob = "tz1ebKt4J5fgxQUv3bPmAdJ2nqVT7erhdsw7"
```

With these helpers in hand, we can write a quick main function that writes three 
separate .tz files, and gives us commands to originate them on a test chain.

Caveat on writing the main function: we have overloaded `>>` here so we can't use 
normal do notation for it, at least until qualified do arrives with GHC 8.12. 
So instead we substitute `*>`:

```haskell
main :: IO ()
main = (writeFile "adminOperator.tz" $ contractToString $ adminOperator fred)
    *> (writeFile "adminLambda1.tz" $ contractToString $ adminLambda)
    *> (writeFile "adminLambda2.tz" $ contractToString $ adminLambda2)
    *> (putStrLn $ makeCmd bob "AdminLambdaOne" "adminLambda1.tz")
    *> (putStrLn $ makeCmd bob "AdminLambdaTwo" "adminLambda2.tz")
    *> (putStrLn $ makeCmd bob "AdminOperator" "adminOperator.tz")
```

## Benchmark results

Here are the links to each contract on Better Call Dev:

- [AdminLambdaOne](https://you.better-call.dev/carthagenet/KT1DsjmP7ujhUgtRJHRMSibxDnMU2NGtDLAU/operations)
- [AdminLambdaTwo](https://you.better-call.dev/carthagenet/KT1FMZvgqB7tGQjDJPuapqS4imzoV1HjnfU2/operations)
- [OperatorLambda](https://you.better-call.dev/carthagenet/KT1TDGX1VLtjbX1VT3xPQTZ2WiFY6eyZXipp/operations)

Here's a table to summarize details of origination:

|   Contract         |       Gas              |       Tez         |   Storage
| ------------------ | ---------------------- | ----------------- | --------------
|  AdminLambdaOne    |       12371            |    0.360594       |   102 bytes
|  AdminLambdaTwo    |       12274            |    0.355579       |    97 bytes
|  OperatorLambda    |       16010            |    0.499095       |   240 bytes

Takeaways:
- the Swap implementation of adminLambda seems to be slightly more performant than the original
- the OperatorLambda specialization is a significantly larger contract to originate than the others

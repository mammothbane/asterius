{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

-- |
-- Module      :  Asterius.Passes.Barf
-- Copyright   :  (c) 2018 EURL Tweag
-- License     :  All rights reserved (see LICENCE file in the distribution).
--
-- Elimination of 'Barf' expressions.
--
-- = What is 'Barf'
--
-- The simplest way to generate WebAssembly code which crashes at runtime is by
-- using Wasm instruction @unreachable@: when execution reaches @unreachable@, the
-- program crashes (@unreachable@ is stack-polymorphic, just as Haskell's
-- @undefined@ is type-polymorphic). Unfortunately, @unreachable@ does not emit
-- any useful information before crashing. To address this, Asterius introduces
-- 'Barf': a polymorphic instruction that emits an error message before aborting
-- execution. It is used for reporting missing symbols, built-in function errors,
-- etc.
--
-- = How is 'Barf' Eliminated
--
-- Since WebAssembly does not support 'Barf', at link-time we have to compile them
-- away. This task is performed by 'processBarf'. Essentially, each 'Barf'
-- instruction is translated into a block of two instructions: (a) a 'Call' to a
-- runtime function to report the error message, followed by (b) an 'Unreachable'
-- instruction to abort execution. Though part (b) is straightforward, passing a
-- string to a 'Call' is a little more convoluted.
--
-- = How are the Error Messages Accessed
--
-- When 'processBarf' encounters a 'Barf' instruction, it creates a new data
-- segment, copies the corresponding error message in it, and produces a 'Call'
-- instruction referring to the segment's symbol. The runtime function takes the
-- data segment's symbol as an argument, and reconstructs the error message by
-- reading the memory starting from the given address (see
-- <https://github.com/tweag/asterius/blob/master/asterius/rts/rts.exception.mjs#L119-L161 here>).
module Asterius.Passes.Barf
  ( processBarf,
  )
where

import Asterius.Types
import qualified Asterius.Types.SymbolMap as SM
import Control.Monad.State.Strict
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as CBS
import Data.Data
  ( Data,
    gmapM,
  )
import Data.String
import Data.Word
import qualified Encoding as GHC
import Type.Reflection

-- | Eliminate all 'Barf' expressions within a function definition.
processBarf :: EntitySymbol -> Function -> AsteriusModule
processBarf sym f =
  mempty
    { staticsMap = sm,
      functionMap = SM.singleton sym f'
    }
  where
    (f', (_, sm)) = runState (w f) (0, SM.empty)
    w ::
      Data a =>
      a ->
      State (Word64, SM.SymbolMap AsteriusStatics) a
    w t = case eqTypeRep (typeOf t) (typeRep :: TypeRep Expression) of
      Just HRefl -> case t of
        Barf {..} -> do
          (i, sm_acc) <- get
          let i_sym = fromString $ p <> GHC.toBase62 i
              ss =
                AsteriusStatics
                  { staticsType = ConstBytes,
                    asteriusStatics =
                      [ Serialized
                          $ fromString
                          $ sym_str
                            <> ": "
                            <> unpack barfMessage
                            <> "\0"
                      ]
                  }
          put (succ i, SM.insert i_sym ss sm_acc)
          pure
            Block
              { name = BS.empty,
                bodys =
                  [ Call
                      { target = "barf",
                        operands =
                          [ Symbol
                              { unresolvedSymbol = i_sym,
                                symbolOffset = 0
                              }
                          ],
                        callReturnTypes = []
                      },
                    Unreachable
                  ],
                blockReturnTypes = barfReturnTypes
              }
        _ -> go
      _ -> go
      where
        go = gmapM w t
    sym_str = unpack (entityName sym)
    p = "__asterius_barf_" <> sym_str <> "_"
    unpack = CBS.unpack

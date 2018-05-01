{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}

import Asterius.Boot
import Asterius.Builtins
import Asterius.CodeGen
import Asterius.Internals
import Asterius.Resolve
import Asterius.Store
import Asterius.SymbolDB
import Asterius.Types
import Control.Exception
import qualified Data.HashMap.Strict as HM
import qualified Data.Map as M
import qualified GhcPlugins as GHC
import Language.Haskell.GHC.Toolkit.Run
import Prelude hiding (IO)
import System.Directory
import System.FilePath
import Text.Show.Pretty

main :: IO ()
main = do
  boot_args <- getDefaultBootArgs
  let obj_topdir = bootDir boot_args </> "asterius_lib"
  pwd <- getCurrentDirectory
  let test_path = pwd </> "test" </> "fact-dump"
  withCurrentDirectory test_path $ do
    putStrLn "Compiling Fact.."
    [(ms_mod, ir)] <- M.toList <$> runHaskell defaultConfig ["Fact.hs"]
    case runCodeGen (marshalHaskellIR ir) GHC.unsafeGlobalDynFlags ms_mod of
      Left err -> throwIO err
      Right m -> do
        putStrLn "Dumping IR of Fact.."
        writeFile "Fact.txt" $ ppShow m
        putStrLn "Chasing Fact_root_closure.."
        store' <- decodeFile (obj_topdir </> "asterius_store")
        let store = addModule (marshalToModuleSymbol ms_mod) m store'
            chase_result =
              chase
                store
                [ AsteriusEntitySymbol
                    { entityKind = StaticsEntity
                    , entityName = "Fact_root_closure"
                    }
                , bdescrSymbol
                , capabilitySymbol
                ]
            avail_syms = statusMap chase_result HM.! Available ()
        pPrint chase_result
        pPrint $ linkStart store avail_syms

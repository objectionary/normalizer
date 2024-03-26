{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE CPP #-}
-- Source: https://github.com/haskell/cabal/issues/6726#issuecomment-918663262

-- | Custom Setup that runs bnfc to generate the language sub-libraries
-- for the parsers included in Ogma.
module Main (main) where

import Distribution.Simple (defaultMainWithHooks, hookedPrograms, postConf, preBuild, simpleUserHooks)
import Distribution.Simple.Program (Program (..), findProgramVersion, simpleProgram)
import System.Process (system)
import Data.String.Interpolate (i)

-- | Run BNFC, happy, and alex on the grammar before the actual build step.
--
-- All options for bnfc are hard-coded here.
main :: IO ()
main = defaultMainWithHooks $ simpleUserHooks
  { hookedPrograms = [ bnfcProgram ]
  , postConf       = \args flags packageDesc localBuildInfo -> do
#ifndef mingw32_HOST_OS
      _ <- system $ [i|
            bnfc --haskell -d -p Language.EO.Phi --generic -o src/ grammar/EO/Phi/Syntax.cf
            cd src/Language/EO/Phi/Syntax
            alex Lex.x
            happy Par.y
          |]
#endif
      postConf simpleUserHooks args flags packageDesc localBuildInfo
  }

-- | NOTE: This should be in Cabal.Distribution.Simple.Program.Builtin.
bnfcProgram :: Program
bnfcProgram = (simpleProgram "bnfc")
  { programFindVersion = findProgramVersion "--version" id
  }

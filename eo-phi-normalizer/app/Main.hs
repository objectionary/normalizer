{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ParallelListComp #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-partial-fields #-}
{-# OPTIONS_GHC -Wno-type-defaults #-}

module Main (main) where

import Control.Exception (Exception (..), SomeException, catch, throw)
import Control.Lens.Lens ((&))
import Control.Lens.Operators ((?~))
import Control.Monad (forM, unless, when)
import Data.Aeson (ToJSON)
import Data.Aeson.Encode.Pretty (Config (..), Indent (..), defConfig, encodePrettyToTextBuilder')
import Data.Foldable (forM_)
import Data.List (intercalate, isPrefixOf)
import Data.Maybe (fromMaybe)
import Data.Text.Internal.Builder (toLazyText)
import Data.Text.Lazy as TL (unpack)
import Data.Version (showVersion)
import Data.Yaml (decodeFileThrow)
import GHC.Generics (Generic)
import Language.EO.Phi (Binding (..), Bytes (Bytes), Object (..), Program (Program), parseProgram, printTree)
import Language.EO.Phi.Dataize
import Language.EO.Phi.Dataize.Context
import Language.EO.Phi.Dependencies
import Language.EO.Phi.Metrics.Collect as Metrics (getProgramMetrics)
import Language.EO.Phi.Metrics.Data as Metrics (ProgramMetrics (..), splitPath)
import Language.EO.Phi.Pipeline.Config
import Language.EO.Phi.Pipeline.Dataize.PrintConfigs as PrintConfigs
import Language.EO.Phi.Pipeline.EOTests.PrepareTests as PrepareTests
import Language.EO.Phi.Report.Data (makeProgramReport, makeReport)
import Language.EO.Phi.Report.Html (reportCSS, reportJS, toStringReport)
import Language.EO.Phi.Rules.Common
import Language.EO.Phi.Rules.Fast (fastYegorInsideOut, fastYegorInsideOutAsRule)
import Language.EO.Phi.Rules.RunYegor (yegorRuleSet)
import Language.EO.Phi.Rules.Yaml (RuleSet (rules, title), convertRuleNamed, parseRuleSetFromFile)
import Language.EO.Phi.ToLaTeX
import Main.Utf8
import Options.Applicative hiding (metavar)
import Options.Applicative qualified as Optparse (metavar)
import Paths_eo_phi_normalizer (version)
import PyF (fmt, fmtTrim)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)
import System.IO (IOMode (WriteMode), getContents', hFlush, hPutStr, hPutStrLn, openFile, stdout)

data CLI'TransformPhi = CLI'TransformPhi
  { chain :: Bool
  , rulesPath :: Maybe String
  , outputFile :: Maybe String
  , single :: Bool
  , json :: Bool
  , latex :: Bool
  , inputFile :: Maybe FilePath
  , dependencies :: [FilePath]
  , maxDepth :: Int
  , maxGrowthFactor :: Int
  }
  deriving stock (Show)

data CLI'DataizePhi = CLI'DataizePhi
  { rulesPath :: Maybe String
  , inputFile :: Maybe FilePath
  , dependencies :: [FilePath]
  , outputFile :: Maybe String
  , recursive :: Bool
  , chain :: Bool
  , latex :: Bool
  , asPackage :: Bool
  , minimizeStuckTerms :: Bool
  , wrapRawBytes :: Bool
  , disabledAtomNames :: [String]
  , enabledAtomNames :: [String]
  }
  deriving stock (Show)

data CLI'MetricsPhi = CLI'MetricsPhi
  { inputFile :: Maybe FilePath
  , outputFile :: Maybe FilePath
  , bindingsPath :: Maybe String
  }
  deriving stock (Show)

data CLI'PrintRules = CLI'PrintRules
  { rulesPath :: Maybe String
  , latex :: Bool
  , compact :: Bool
  }
  deriving stock (Show)

newtype CLI'Pipeline'Report = CLI'Pipeline'Report
  { configFile :: FilePath
  }
  deriving stock (Show)

newtype CLI'Pipeline'PrepareTests = CLI'Pipeline'PrepareTests
  { configFile :: FilePath
  }
  deriving stock (Show)

data CLI'Pipeline'PrintDataizeConfigs = CLI'Pipeline'PrintDataizeConfigs
  { configFile :: FilePath
  , phiPrefixesToStrip :: [FilePath]
  , singleLine :: Bool
  }
  deriving stock (Show)

data CLI'Pipeline
  = CLI'Pipeline'Report' CLI'Pipeline'Report
  | CLI'Pipeline'PrepareTests' CLI'Pipeline'PrepareTests
  | CLI'Pipeline'PrintDataizeConfigs' CLI'Pipeline'PrintDataizeConfigs
  deriving stock (Show)

data CLI
  = CLI'TransformPhi' CLI'TransformPhi
  | CLI'DataizePhi' CLI'DataizePhi
  | CLI'MetricsPhi' CLI'MetricsPhi
  | CLI'PrintRules' CLI'PrintRules
  | CLI'Pipeline' CLI'Pipeline
  deriving stock (Show)

data MetavarName = MetavarName
  { file :: String
  , int :: String
  , path :: String
  , atomName :: String
  }

metavarName :: MetavarName
metavarName =
  MetavarName
    { file = "FILE"
    , int = "INT"
    , path = "PATH"
    , atomName = "ATOM_NAME"
    }

data Metavar a b = Metavar
  { file :: Mod a b
  , int :: Mod a b
  , path :: Mod a b
  , atomName :: Mod a b
  }

metavar :: (HasMetavar a) => Metavar a b
metavar =
  Metavar
    { file = Optparse.metavar metavarName.file
    , int = Optparse.metavar metavarName.int
    , path = Optparse.metavar metavarName.path
    , atomName = Optparse.metavar metavarName.atomName
    }

newtype OptionName = OptionName
  { bindingsPath :: String
  }

optionName :: OptionName
optionName =
  OptionName
    { bindingsPath = "bindings-path"
    }

outputFileOption :: Parser (Maybe String)
outputFileOption = optional $ strOption (long "output-file" <> short 'o' <> metavar.file <> help [fmt|Output to {metavarName.file}. When this option is not specified, output to stdout.|])

inputFileArg :: Parser (Maybe String)
inputFileArg = optional $ strArgument (metavar.file <> help [fmt|{metavarName.file} to read input from. When no {metavarName.file} is specified, read from stdin.|])

dependenciesArg :: Parser [FilePath]
dependenciesArg =
  many $
    strOption (long "dependency-file" <> short 'd' <> metavar.file <> help [fmt|{metavarName.file} to read dependencies from (zero or more dependency files allowed).|])

jsonSwitch :: Parser Bool
jsonSwitch = switch (long "json" <> short 'j' <> help "Output JSON.")

latexSwitch :: Parser Bool
latexSwitch = switch (long "tex" <> help "Output LaTeX.")

compactSwitch :: Parser Bool
compactSwitch = switch (long "compact" <> short 'c' <> help "Print rules, each on a single line.")

asPackageSwitch :: Parser Bool
asPackageSwitch = switch (long "as-package" <> help "Automatically inject (λ → Package) in the program if necessary, to dataize all fields.")

minimizeStuckTermsSwitch :: Parser Bool
minimizeStuckTermsSwitch = switch (long "minimize-stuck-terms" <> help "If a dataized (sub)term is stuck (cannot be fully dataized), use the minimal (by size) intermediate result.")

bindingsPathOption :: Parser (Maybe String)
bindingsPathOption =
  optional $
    strOption
      ( long optionName.bindingsPath
          <> short 'b'
          <> metavar.path
          <> help
            let path' = metavarName.path
             in [fmtTrim|
                  Report metrics for bindings of a formation accessible in a program by the {path'}.
                  When this option is not specified, metrics for bindings are not reported.
                  Example of a {path'}: 'org.eolang'.
                |]
      )

data CommandParser'Pipeline = CommandParser'Pipeline
  { report :: Parser CLI'Pipeline'Report
  , prepareTests :: Parser CLI'Pipeline'PrepareTests
  , printDataizeConfigs :: Parser CLI'Pipeline'PrintDataizeConfigs
  }

data CommandParser = CommandParser
  { metrics :: Parser CLI'MetricsPhi
  , transform :: Parser CLI'TransformPhi
  , dataize :: Parser CLI'DataizePhi
  , pipeline :: Parser CLI'Pipeline
  , pipeline' :: CommandParser'Pipeline
  , printRules :: Parser CLI'PrintRules
  }

commandParser :: CommandParser
commandParser =
  CommandParser{..}
 where
  metrics = do
    inputFile <- inputFileArg
    outputFile <- outputFileOption
    bindingsPath <- bindingsPathOption
    pure CLI'MetricsPhi{..}
  printRules = do
    rulesPath <- optional $ strOption (long "rules" <> short 'r' <> metavar.file <> help [fmt|{metavarName.file} with user-defined rules. If unspecified, yegor.yaml is rendered.|])
    latex <- latexSwitch
    compact <- compactSwitch
    pure CLI'PrintRules{..}
  transform = do
    rulesPath <- optional $ strOption (long "rules" <> short 'r' <> metavar.file <> help [fmt|{metavarName.file} with user-defined rules. If unspecified, builtin set of rules is used.|])
    chain <- switch (long "chain" <> short 'c' <> help "Output transformation steps.")
    json <- jsonSwitch
    latex <- latexSwitch
    outputFile <- outputFileOption
    single <- switch (long "single" <> short 's' <> help "Output a single expression.")
    maxDepth <-
      let maxValue = 10
       in option auto (long "max-depth" <> metavar.int <> value maxValue <> help [fmt|Maximum depth of rules application. Defaults to {maxValue}.|])
    maxGrowthFactor <-
      let maxValue = 10
       in option auto (long "max-growth-factor" <> metavar.int <> value maxValue <> help [fmt|The factor by which to allow the input term to grow before stopping. Defaults to {maxValue}.|])
    inputFile <- inputFileArg
    dependencies <- dependenciesArg
    pure CLI'TransformPhi{..}
  dataize = do
    rulesPath <- optional $ strOption (long "rules" <> short 'r' <> metavar.file <> help [fmt|{metavarName.file} with user-defined rules. If unspecified, builtin set of rules is used.|])
    inputFile <- inputFileArg
    dependencies <- dependenciesArg
    outputFile <- outputFileOption
    recursive <- switch (long "recursive" <> help "Apply dataization + normalization recursively.")
    chain <- switch (long "chain" <> help "Display all the intermediate steps.")
    wrapRawBytes <- switch (long "wrap-raw-bytes" <> help "Wrap raw bytes ⟦ Δ ⤍ 01- ⟧ as Φ.org.eolang.bytes(Δ ⤍ 01-) in the final output.")
    latex <- latexSwitch
    asPackage <- asPackageSwitch
    minimizeStuckTerms <- minimizeStuckTermsSwitch
    disabledAtomNames <- many $ strOption (long "disable-atom" <> metavar.atomName <> help "Name of an atom to disable.")
    enabledAtomNames <- many $ strOption (long "enable-atom" <> metavar.atomName <> help "Name of an atom to enable.")
    pure CLI'DataizePhi{..}
  pipeline' =
    CommandParser'Pipeline
      { report = do
          configFile <- strOption (long "config" <> short 'c' <> metavar.file <> help [fmt|A report configuration {metavarName.file}.|])
          pure CLI'Pipeline'Report{..}
      , prepareTests = do
          configFile <- strOption (long "config" <> short 'c' <> metavar.file <> help [fmt|A pipeline tests configuration {metavarName.file}.|])
          pure CLI'Pipeline'PrepareTests{..}
      , printDataizeConfigs = do
          configFile <- strOption (long "config" <> short 'c' <> metavar.file <> help [fmt|A pipeline tests configuration {metavarName.file}.|])
          phiPrefixesToStrip <- many $ strOption (long "strip-phi-prefix" <> short 'p' <> metavar.path <> help [fmt|{metavarName.path} prefix to remove in PHI file paths.|])
          singleLine <- switch (long "single-line" <> short 'l' <> help [fmt|Output configs on an single line.|])
          pure CLI'Pipeline'PrintDataizeConfigs{..}
      }
  pipeline =
    hsubparser
      ( command commandNames.pipeline'.report commandParserInfo.pipeline'.report
          <> command commandNames.pipeline'.prepareTests commandParserInfo.pipeline'.prepareTests
          <> command commandNames.pipeline'.printDataizeConfigs commandParserInfo.pipeline'.printDataizeConfigs
      )

data CommandParserInfo'Pipeline = CommandParserInfo'Pipeline
  { report :: ParserInfo CLI'Pipeline
  , prepareTests :: ParserInfo CLI'Pipeline
  , printDataizeConfigs :: ParserInfo CLI'Pipeline
  }

data CommandParserInfo = CommandParserInfo
  { metrics :: ParserInfo CLI
  , transform :: ParserInfo CLI
  , dataize :: ParserInfo CLI
  , printRules :: ParserInfo CLI
  , pipeline :: ParserInfo CLI
  , pipeline' :: CommandParserInfo'Pipeline
  }

commandParserInfo :: CommandParserInfo
commandParserInfo =
  CommandParserInfo
    { metrics = info (CLI'MetricsPhi' <$> commandParser.metrics) (progDesc "Collect metrics for a PHI program.")
    , transform = info (CLI'TransformPhi' <$> commandParser.transform) (progDesc "Transform a PHI program.")
    , dataize = info (CLI'DataizePhi' <$> commandParser.dataize) (progDesc "Dataize a PHI program.")
    , printRules = info (CLI'PrintRules' <$> commandParser.printRules) (progDesc "Print rules in LaTeX format.")
    , pipeline = info (CLI'Pipeline' <$> commandParser.pipeline) (progDesc "Run pipeline-related commands.")
    , pipeline' =
        CommandParserInfo'Pipeline
          { report = info (CLI'Pipeline'Report' <$> commandParser.pipeline'.report) (progDesc "Generate reports about initial and normalized PHI programs.")
          , prepareTests = info (CLI'Pipeline'PrepareTests' <$> commandParser.pipeline'.prepareTests) (progDesc "Prepare EO test files for the pipeline.")
          , printDataizeConfigs = info (CLI'Pipeline'PrintDataizeConfigs' <$> commandParser.pipeline'.printDataizeConfigs) (progDesc [fmt|Print configs for the `normalizer {commandNames.dataize}` command.|])
          }
    }

data CommandNames'Pipeline = CommandNames'Pipeline
  { report :: String
  , prepareTests :: String
  , printDataizeConfigs :: String
  }

data CommandNames = CommandNames
  { transform :: String
  , metrics :: String
  , dataize :: String
  , printRules :: String
  , pipeline :: String
  , pipeline' :: CommandNames'Pipeline
  }

commandNames :: CommandNames
commandNames =
  CommandNames
    { transform = "transform"
    , metrics = "metrics"
    , dataize = "dataize"
    , printRules = "print-rules"
    , pipeline = "pipeline"
    , pipeline' =
        CommandNames'Pipeline
          { report = "report"
          , prepareTests = "prepare-tests"
          , printDataizeConfigs = "print-dataize-configs"
          }
    }

cli :: Parser CLI
cli =
  hsubparser
    ( command commandNames.transform commandParserInfo.transform
        <> command commandNames.metrics commandParserInfo.metrics
        <> command commandNames.dataize commandParserInfo.dataize
        <> command commandNames.pipeline commandParserInfo.pipeline
        <> command commandNames.printRules commandParserInfo.printRules
    )

cliOpts :: String -> ParserInfo CLI
cliOpts version' =
  info
    (cli <**> helper <**> simpleVersioner version')
    (fullDesc <> progDesc "Work with PHI expressions.")

data StructuredJSON = StructuredJSON
  { input :: String
  , output :: [[(String, String)]]
  }
  deriving (Generic, ToJSON)

logEntryToPair :: LogEntry a -> (String, a)
logEntryToPair LogEntry{..} = (logEntryMessage, logEntryLog)

encodeToJSONString :: (ToJSON a) => a -> String
encodeToJSONString = TL.unpack . toLazyText . encodePrettyToTextBuilder' defConfig{confIndent = Spaces 2}

pprefs :: ParserPrefs
pprefs = prefs (showHelpOnEmpty <> showHelpOnError)

data CLI'Exception
  = NotAFormation {path :: String, bindingsPath :: String}
  | FileDoesNotExist {file :: FilePath}
  | CouldNotRead {message :: String}
  | CouldNotParse {message :: String}
  | CouldNotNormalize
  | CouldNotMergeDependencies {message :: String}
  | Impossible {message :: String}
  deriving anyclass (Exception)

instance Show CLI'Exception where
  show :: CLI'Exception -> String
  show = \case
    NotAFormation{..} -> [fmt|Could not find bindings at path '{bindingsPath}' because an object at '{path}' is not a formation.|]
    FileDoesNotExist{..} -> [fmt|File '{file}' does not exist.|]
    CouldNotRead{..} -> [fmt|Could not read the program:\n{message}|]
    CouldNotParse{..} -> [fmt|An error occurred when parsing the input program:\n{message}|]
    CouldNotNormalize -> [fmt|Could not normalize the program.|]
    CouldNotMergeDependencies{..} -> message
    Impossible{..} -> message

getFile :: Maybe FilePath -> IO (Maybe String)
getFile = \case
  Nothing -> pure Nothing
  Just file' ->
    doesFileExist file' >>= \case
      True -> pure (Just file')
      False -> throw $ FileDoesNotExist file'

getProgram :: Maybe FilePath -> IO Program
getProgram inputFile = do
  inputFile' <- getFile inputFile
  src <- maybe getContents' readFile inputFile' `catch` (throw . CouldNotRead . show @SomeException)
  case parseProgram src of
    Left err -> throw $ CouldNotParse err
    Right program -> pure program

getLoggers :: Maybe FilePath -> IO (String -> IO (), String -> IO ())
getLoggers outputFile = do
  handle <- maybe (pure stdout) (\file -> createDirectoryIfMissing True (takeDirectory file) >> openFile file WriteMode) outputFile
  pure
    ( \x -> hPutStrLn handle x >> hFlush handle
    , \x -> hPutStr handle x >> hFlush handle
    )

-- >>> flip getMetrics' (Just "a.b") "{⟦ a ↦ ⟦ b ↦ ⟦ c ↦ ∅, d ↦ ⟦ φ ↦ ξ.ρ.c ⟧ ⟧, e ↦ ξ.b(c ↦ ⟦⟧).d ⟧ ⟧}"
-- Right (ProgramMetrics {bindingsByPathMetrics = Just (BindingsByPathMetrics {path = ["a","b"], bindingsMetrics = [BindingMetrics {name = "d", metrics = Metrics {dataless = 0, applications = 0, formations = 1, dispatches = 2}}]}), programMetrics = Metrics {dataless = 1, applications = 1, formations = 5, dispatches = 4}})
getMetrics' :: Program -> Maybe String -> Either CLI'Exception ProgramMetrics
getMetrics' program bindingsPath = do
  let metrics = getProgramMetrics program (splitPath <$> bindingsPath)
  case metrics of
    Left path ->
      ( case bindingsPath of
          Nothing ->
            let
              bindingsPath' = optionName.bindingsPath
              path' = metavarName.path
             in
              Left $
                Impossible
                  [fmtTrim|
                    Impossible happened!
                    The option {bindingsPath'} was not specified yet there were errors finding attributes by {path'}.
                  |]
          Just bindingsPath' -> Left $ NotAFormation (intercalate "." path) bindingsPath'
      )
    Right metrics' -> pure metrics'

getMetrics :: Maybe String -> Maybe FilePath -> IO ProgramMetrics
getMetrics bindingsPath inputFile = do
  program <- getProgram inputFile
  either throw pure (getMetrics' program bindingsPath)

injectLamdbaPackage :: [Binding] -> [Binding]
injectLamdbaPackage bs
  | any isPackageBinding bs = bs
  | otherwise = bs ++ [LambdaBinding "Package"]

removeLambdaPackage :: Object -> Object
removeLambdaPackage = \case
  Formation bindings ->
    Formation
      [ binding
      | binding <- bindings
      , not (isLambdaPackage binding)
      ]
  obj -> obj

isLambdaPackage :: Binding -> Bool
isLambdaPackage (LambdaBinding "Package") = True
isLambdaPackage _ = False

wrapRawBytesIn :: Object -> Object
wrapRawBytesIn = \case
  Formation [DeltaBinding bytes] -> wrapBytesInBytes bytes
  Formation bindings ->
    Formation
      [ case binding of
        AlphaBinding a obj -> AlphaBinding a (wrapRawBytesIn obj)
        _ -> binding
      | binding <- bindings
      ]
  Application obj bindings ->
    Application
      (wrapRawBytesIn obj)
      [ case binding of
        AlphaBinding a attached -> AlphaBinding a (wrapRawBytesIn attached)
        _ -> binding
      | binding <- bindings
      ]
  ObjectDispatch obj a ->
    ObjectDispatch (wrapRawBytesIn obj) a
  GlobalObject -> GlobalObject
  ThisObject -> ThisObject
  Termination -> wrapTermination
  obj@MetaSubstThis{} -> obj
  obj@MetaObject{} -> obj
  obj@MetaTailContext{} -> obj
  obj@MetaFunction{} -> obj

-- * Main

main :: IO ()
main = withUtf8 do
  opts <- customExecParser pprefs (cliOpts (showVersion version))
  let printAsProgramOrAsObject = \case
        Formation bindings' -> printTree $ Program bindings'
        x -> printTree x
  case opts of
    CLI'MetricsPhi' CLI'MetricsPhi{..} -> do
      (logStrLn, _) <- getLoggers outputFile
      -- logStrLn "Computing metrics"
      metrics <- getMetrics bindingsPath inputFile
      logStrLn $ encodeToJSONString metrics
    CLI'PrintRules' CLI'PrintRules{..} -> do
      (logStrLn, _) <- getLoggers Nothing
      rules <- rules <$> maybe (return yegorRuleSet) parseRuleSetFromFile rulesPath
      let toLatex' = if compact then rulesToLatexCompact else toLatex
      logStrLn $ show $ toLatex' rules
    CLI'TransformPhi' CLI'TransformPhi{..} -> do
      program' <- getProgram inputFile
      deps <- mapM (getProgram . Just) dependencies
      (logStrLn, logStr) <- getLoggers outputFile
      -- logStrLn "Running transform"
      (builtin, ruleSetTitle, rules) <-
        case rulesPath of
          Just path -> do
            ruleSet <- parseRuleSetFromFile path
            return (False, ruleSet.title, convertRuleNamed <$> ruleSet.rules)
          Nothing -> return (True, "Yegor's rules (builtin)", [fastYegorInsideOutAsRule])
      unless (single || json) $ logStrLn ruleSetTitle
      bindingsWithDeps <- case deepMergePrograms (program' : deps) of
        Left err -> throw (CouldNotMergeDependencies err)
        Right (Program bindingsWithDeps) -> return bindingsWithDeps
      let Program bindings = program'
          uniqueResults
            -- Something here seems incorrect
            | chain = map fst $ applyRulesChainWith' limits ctx (Formation bindings)
            | builtin = return [LogEntry "" (fastYegorInsideOut ctx (Formation bindings)) 0]
            | otherwise = (\x -> [LogEntry "" x 0]) <$> applyRulesWith limits ctx (Formation bindings)
           where
            limits = ApplicationLimits maxDepth (maxGrowthFactor * objectSize (Formation bindings))
            ctx = (defaultContext rules (Formation bindingsWithDeps)){builtinRules = builtin} -- IMPORTANT: context contains dependencies!
          totalResults = length uniqueResults
      when (null uniqueResults || null (head uniqueResults)) (throw CouldNotNormalize)
      if
        | single && json ->
            logStrLn
              . encodeToJSONString
              . printAsProgramOrAsObject
              $ logEntryLog (head (head uniqueResults))
        | single ->
            logStrLn
              . printAsProgramOrAsObject
              $ logEntryLog (head (head uniqueResults))
        | json ->
            logStrLn . encodeToJSONString $
              StructuredJSON
                { input = printTree program'
                , output = (logEntryToPair . fmap printAsProgramOrAsObject <$>) <$> uniqueResults
                }
        | chain && latex -> do
            logStrLn . toLatexString $ Formation bindings
            forM_ uniqueResults $ \steps -> do
              forM_ (init steps) $ \LogEntry{..} -> do
                logStrLn . toLatexString $ logEntryLog
        | latex ->
            logStrLn . toLatexString $ logEntryLog (head (head uniqueResults))
        | otherwise -> do
            logStrLn "Input:"
            logStrLn (printTree program')
            logStrLn "===================================================="
            forM_ (zip [1 ..] uniqueResults) $ \(index, steps) -> do
              logStrLn $
                "Result " <> show index <> " out of " <> show totalResults <> ":"
              let n = length steps
              forM_ (zip [1 ..] steps) $ \(k, LogEntry{..}) -> do
                when chain $
                  logStr ("[ " <> show k <> " / " <> show n <> " ] " <> logEntryMessage <> ": ")
                logStrLn . printAsProgramOrAsObject $ logEntryLog
              logStrLn "----------------------------------------------------"
    CLI'DataizePhi' CLI'DataizePhi{..} -> do
      (logStrLn, _logStr) <- getLoggers outputFile
      -- logStrLn "Running dataize"
      program' <- getProgram inputFile
      deps <- mapM (getProgram . Just) dependencies
      bindingsWithDeps <- case deepMergePrograms (program' : deps) of
        Left err -> throw (CouldNotMergeDependencies err)
        Right (Program bindingsWithDeps) -> return bindingsWithDeps
      (builtin, _ruleSetTitle, rules) <-
        case rulesPath of
          Just path -> do
            ruleSet <- parseRuleSetFromFile path
            return (False, ruleSet.title, convertRuleNamed <$> ruleSet.rules)
          Nothing -> return (True, "Yegor's rules (builtin)", [fastYegorInsideOutAsRule])
      let (Program bindings) = program'
          inputObject
            | asPackage = Formation (injectLamdbaPackage bindings)
            | otherwise = Formation bindings
          ctx =
            (defaultContext rules (Formation bindingsWithDeps)) -- IMPORTANT: context contains dependencies!
              { minimizeTerms = minimizeStuckTerms
              , builtinRules = builtin
              , enabledAtoms = mkEnabledAtoms enabledAtomNames disabledAtomNames
              , knownAtoms = knownAtomsMap
              }
      if chain
        then do
          let dataizeChain
                | recursive = dataizeRecursivelyChain'
                | otherwise = dataizeStepChain'
          if latex
            then do
              logStrLn . toLatexString $ Formation bindings
              forM_ (fst (dataizeChain ctx inputObject)) $ \LogEntry{..} ->
                case logEntryLog of
                  Left obj ->
                    when ("Rule" `isPrefixOf` logEntryMessage) $
                      logStrLn . toLatexString $
                        obj
                  Right (Bytes bytes) -> logStrLn bytes
            else do
              forM_ (fst (dataizeChain ctx inputObject)) $ \LogEntry{..} ->
                case logEntryLog of
                  Left obj -> logStrLn (replicate logEntryLevel ' ' ++ logEntryMessage ++ ": " ++ printTree obj)
                  Right (Bytes bytes) -> logStrLn (replicate logEntryLevel ' ' ++ logEntryMessage ++ ": " ++ bytes)
        else do
          let dataize
                -- This should be moved to a separate subcommand
                | recursive = dataizeRecursively
                | otherwise = dataizeStep'
          case dataize ctx inputObject of
            Left obj ->
              let obj'
                    | asPackage = removeLambdaPackage obj
                    | otherwise = obj
                  obj''
                    | wrapRawBytes = wrapRawBytesIn obj'
                    | otherwise = obj'
               in logStrLn (printAsProgramOrAsObject obj'')
            Right (Bytes bytes) -> logStrLn bytes
    CLI'Pipeline' (CLI'Pipeline'Report' CLI'Pipeline'Report{..}) -> do
      pipelineConfig <- decodeFileThrow @_ @PipelineConfig configFile
      let testSets = filter (fromMaybe True . (.enable)) pipelineConfig.testSets
      programReports <- forM (zip [1 ..] testSets) $ \(index :: Int, (.phi) -> testSet) -> do
        let progress = [fmt|({index}/{length testSets})|] :: String
        putStrLn [fmt|Processing {progress}: {testSet.initial}|]
        metricsPhi <- getMetrics testSet.bindingsPathInitial (Just testSet.initial)
        putStrLn [fmt|Processing {progress}: {testSet.normalized}|]
        metricsPhiNormalized <- getMetrics testSet.bindingsPathNormalized (Just testSet.normalized)
        pure $ makeProgramReport pipelineConfig testSet metricsPhi metricsPhiNormalized

      css <- maybe (pure reportCSS) readFile (pipelineConfig.report.input >>= (.css))
      js <- maybe (pure reportJS) readFile (pipelineConfig.report.input >>= (.js))

      let report = makeReport pipelineConfig programReports
          reportHtml = toStringReport ReportFormat'Html (pipelineConfig & #report . #input ?~ ReportInput{css = Just css, js = Just js}) report
          reportJson = encodeToJSONString report
          reportMarkdown = toStringReport ReportFormat'Markdown pipelineConfig report

      forM_ @[]
        [ (x, y)
        | (Just x, y) <-
            [ (pipelineConfig.report.output.html, reportHtml)
            , (pipelineConfig.report.output.json, reportJson)
            , (pipelineConfig.report.output.markdown, reportMarkdown)
            ]
        ]
        $ \(path, reportString) -> do
          createDirectoryIfMissing True (takeDirectory path)
          writeFile path reportString
    CLI'Pipeline' (CLI'Pipeline'PrepareTests' CLI'Pipeline'PrepareTests{..}) -> do
      config <- decodeFileThrow @_ @PipelineConfig configFile
      PrepareTests.prepareTests config
    CLI'Pipeline' (CLI'Pipeline'PrintDataizeConfigs' CLI'Pipeline'PrintDataizeConfigs{..}) -> do
      config <- decodeFileThrow @_ @PipelineConfig configFile
      PrintConfigs.printDataizeConfigs config phiPrefixesToStrip singleLine

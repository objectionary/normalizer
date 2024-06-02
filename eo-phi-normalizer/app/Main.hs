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
import Data.Yaml (decodeFileThrow)
import GHC.Generics (Generic)
import Language.EO.Phi (Binding (LambdaBinding), Bytes (Bytes), Object (Formation), Program (Program), parseProgram, printTree)
import Language.EO.Phi.Dataize
import Language.EO.Phi.Dependencies
import Language.EO.Phi.Metrics.Collect as Metrics (getProgramMetrics)
import Language.EO.Phi.Metrics.Data as Metrics (ProgramMetrics (..), splitPath)
import Language.EO.Phi.Pipeline.Config
import Language.EO.Phi.Pipeline.EOTests.PrepareTests (prepareTests)
import Language.EO.Phi.Report.Data (makeProgramReport, makeReport)
import Language.EO.Phi.Report.Html (reportCSS, reportJS, toStringReport)
import Language.EO.Phi.Rules.Common
import Language.EO.Phi.Rules.Fast (fastYegorInsideOut, fastYegorInsideOutAsRule)
import Language.EO.Phi.Rules.Yaml (RuleSet (rules, title), convertRuleNamed, parseRuleSetFromFile)
import Language.EO.Phi.ToLaTeX
import Main.Utf8
import Options.Applicative hiding (metavar)
import Options.Applicative qualified as Optparse (metavar)
import PyF (fmt, fmtTrim)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)
import System.IO (IOMode (WriteMode), getContents', hFlush, hPutStr, hPutStrLn, openFile, stdout)

data CLI'RewritePhi = CLI'RewritePhi
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
  deriving (Show)

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
  }
  deriving (Show)

data CLI'MetricsPhi = CLI'MetricsPhi
  { inputFile :: Maybe FilePath
  , outputFile :: Maybe FilePath
  , bindingsPath :: Maybe String
  }
  deriving (Show)

newtype CLI'ReportPhi = CLI'ReportPhi
  { configFile :: FilePath
  }
  deriving (Show)

newtype CLI'PreparePipelineTests = CLI'PreparePipelineTests
  { configFile :: FilePath
  }
  deriving (Show)

data CLI
  = CLI'RewritePhi' CLI'RewritePhi
  | CLI'DataizePhi' CLI'DataizePhi
  | CLI'MetricsPhi' CLI'MetricsPhi
  | CLI'ReportPhi' CLI'ReportPhi
  | CLI'PreparePipelineTests' CLI'PreparePipelineTests
  deriving (Show)

data MetavarName = MetavarName
  { file :: String
  , int :: String
  , path :: String
  }

metavarName :: MetavarName
metavarName =
  MetavarName
    { file = "FILE"
    , int = "INT"
    , path = "PATH"
    }

data Metavar a b = Metavar
  { file :: Mod a b
  , int :: Mod a b
  , path :: Mod a b
  }

metavar :: (HasMetavar a) => Metavar a b
metavar =
  Metavar
    { file = Optparse.metavar metavarName.file
    , int = Optparse.metavar metavarName.int
    , path = Optparse.metavar metavarName.path
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

data CommandParser = CommandParser
  { metrics :: Parser CLI'MetricsPhi
  , rewrite :: Parser CLI'RewritePhi
  , dataize :: Parser CLI'DataizePhi
  , report :: Parser CLI'ReportPhi
  , preparePipelineTests :: Parser CLI'PreparePipelineTests
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

  rewrite = do
    rulesPath <- optional $ strOption (long "rules" <> short 'r' <> metavar.file <> help [fmt|{metavarName.file} with user-defined rules. If unspecified, builtin set of rules is used.|])
    chain <- switch (long "chain" <> short 'c' <> help "Output rewriting steps.")
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
    pure CLI'RewritePhi{..}
  dataize = do
    rulesPath <- optional $ strOption (long "rules" <> short 'r' <> metavar.file <> help [fmt|{metavarName.file} with user-defined rules. If unspecified, builtin set of rules is used.|])
    inputFile <- inputFileArg
    dependencies <- dependenciesArg
    outputFile <- outputFileOption
    recursive <- switch (long "recursive" <> help "Apply dataization + normalization recursively.")
    chain <- switch (long "chain" <> help "Display all the intermediate steps.")
    latex <- latexSwitch
    asPackage <- asPackageSwitch
    minimizeStuckTerms <- minimizeStuckTermsSwitch
    pure CLI'DataizePhi{..}
  report = do
    configFile <- strOption (long "config" <> short 'c' <> metavar.file <> help [fmt|A report configuration {metavarName.file}.|])
    pure CLI'ReportPhi{..}
  preparePipelineTests = do
    configFile <- strOption (long "config" <> short 'c' <> metavar.file <> help [fmt|A pipeline tests configuration {metavarName.file}.|])
    pure CLI'PreparePipelineTests{..}

data CommandParserInfo = CommandParserInfo
  { metrics :: ParserInfo CLI
  , rewrite :: ParserInfo CLI
  , dataize :: ParserInfo CLI
  , report :: ParserInfo CLI
  , preparePipelineTests :: ParserInfo CLI
  }

commandParserInfo :: CommandParserInfo
commandParserInfo =
  CommandParserInfo
    { metrics = info (CLI'MetricsPhi' <$> commandParser.metrics) (progDesc "Collect metrics for a PHI program.")
    , rewrite = info (CLI'RewritePhi' <$> commandParser.rewrite) (progDesc "Rewrite a PHI program.")
    , dataize = info (CLI'DataizePhi' <$> commandParser.dataize) (progDesc "Dataize a PHI program.")
    , report = info (CLI'ReportPhi' <$> commandParser.report) (progDesc "Generate reports about initial and normalized PHI programs.")
    , preparePipelineTests = info (CLI'PreparePipelineTests' <$> commandParser.preparePipelineTests) (progDesc "Prepare EO test files for the pipeline.")
    }

data CommandNames = CommandNames
  { rewrite :: String
  , metrics :: String
  , dataize :: String
  , report :: String
  , preparePipelineTests :: String
  }

commandNames :: CommandNames
commandNames =
  CommandNames
    { rewrite = "rewrite"
    , metrics = "metrics"
    , dataize = "dataize"
    , report = "report"
    , preparePipelineTests = "prepare-pipeline-tests"
    }

cli :: Parser CLI
cli =
  hsubparser
    ( command commandNames.rewrite commandParserInfo.rewrite
        <> command commandNames.metrics commandParserInfo.metrics
        <> command commandNames.dataize commandParserInfo.dataize
        <> command commandNames.report commandParserInfo.report
        <> command commandNames.preparePipelineTests commandParserInfo.preparePipelineTests
    )

cliOpts :: ParserInfo CLI
cliOpts =
  info
    (cli <**> helper)
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
  handle <- maybe (pure stdout) (`openFile` WriteMode) outputFile
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

-- * Main

main :: IO ()
main = withUtf8 do
  opts <- customExecParser pprefs cliOpts
  let printAsProgramOrAsObject = \case
        Formation bindings' -> printTree $ Program bindings'
        x -> printTree x
  case opts of
    CLI'MetricsPhi' CLI'MetricsPhi{..} -> do
      (logStrLn, _) <- getLoggers outputFile
      -- logStrLn "Computing metrics"
      metrics <- getMetrics bindingsPath inputFile
      logStrLn $ encodeToJSONString metrics
    CLI'RewritePhi' CLI'RewritePhi{..} -> do
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
            Left obj -> logStrLn (printAsProgramOrAsObject obj)
            Right (Bytes bytes) -> logStrLn bytes
    CLI'ReportPhi' CLI'ReportPhi{..} -> do
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
    CLI'PreparePipelineTests' CLI'PreparePipelineTests{..} -> do
      config <- decodeFileThrow @_ @PipelineConfig configFile
      prepareTests config

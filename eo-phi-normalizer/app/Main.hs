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
{-# OPTIONS_GHC -Wno-partial-fields #-}
{-# OPTIONS_GHC -Wno-type-defaults #-}

module Main (main) where

import Control.Monad (forM, unless, when)
import Data.Foldable (forM_)

import Control.Exception (Exception (..), SomeException, catch, throw)
import Data.Aeson (ToJSON)
import Data.Aeson.Encode.Pretty (Config (..), Indent (..), defConfig, encodePrettyToTextBuilder')
import Data.List (intercalate)
import Data.String.Interpolate (i, iii)
import Data.Text.Internal.Builder (toLazyText)
import Data.Text.Lazy as TL (unpack)
import Data.Yaml (decodeFileThrow)
import GHC.Generics (Generic)
import Language.EO.Phi (Bytes (Bytes), Object (Formation), Program (Program), parseProgram, printTree)
import Language.EO.Phi.Dataize (dataizeRecursively, dataizeRecursivelyChain, dataizeStep, dataizeStepChain)
import Language.EO.Phi.Metrics.Collect as Metrics (getProgramMetrics)
import Language.EO.Phi.Metrics.Data as Metrics (ProgramMetrics (..), splitPath)
import Language.EO.Phi.Report.Data (Report'InputConfig (..), Report'OutputConfig (..), ReportConfig (..), ReportItem (..), makeProgramReport, makeReport)
import Language.EO.Phi.Report.Html (ReportFormat (..), reportCSS, reportJS, toStringReport)
import Language.EO.Phi.Report.Html qualified as ReportHtml (ReportConfig (..))
import Language.EO.Phi.Rules.Common (ApplicationLimits (ApplicationLimits), applyRulesChainWith, applyRulesWith, defaultContext, objectSize, propagateName1)
import Language.EO.Phi.Rules.Yaml (RuleSet (rules, title), convertRuleNamed, parseRuleSetFromFile)
import Options.Applicative hiding (metavar)
import Options.Applicative qualified as Optparse (metavar)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)
import System.IO (IOMode (WriteMode), getContents', hFlush, hPutStr, hPutStrLn, openFile, stdout)

data CLI'TransformPhi = CLI'TransformPhi
  { chain :: Bool
  , rulesPath :: String
  , outputFile :: Maybe String
  , single :: Bool
  , json :: Bool
  , inputFile :: Maybe FilePath
  , maxDepth :: Int
  , maxGrowthFactor :: Int
  }
  deriving (Show)

data CLI'DataizePhi = CLI'DataizePhi
  { rulesPath :: String
  , inputFile :: Maybe FilePath
  , outputFile :: Maybe String
  , recursive :: Bool
  , chain :: Bool
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

data CLI
  = CLI'TransformPhi' CLI'TransformPhi
  | CLI'DataizePhi' CLI'DataizePhi
  | CLI'MetricsPhi' CLI'MetricsPhi
  | CLI'ReportPhi' CLI'ReportPhi
  deriving (Show)

fileMetavarName :: String
fileMetavarName = "FILE"

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
outputFileOption = optional $ strOption (long "output-file" <> short 'o' <> metavar.file <> help [i|Output to #{fileMetavarName}. When this option is not specified, output to stdout.|])

inputFileArg :: Parser (Maybe String)
inputFileArg = optional $ strArgument (metavar.file <> help [i|#{fileMetavarName} to read input from. When no #{fileMetavarName} is specified, read from stdin.|])

jsonSwitch :: Parser Bool
jsonSwitch = switch (long "json" <> short 'j' <> help "Output JSON.")

bindingsPathOption :: Parser (Maybe String)
bindingsPathOption =
  optional $
    strOption
      ( long optionName.bindingsPath
          <> short 'b'
          <> metavar.path
          <> help
            let path' = metavarName.path
             in [iii|
                  Report metrics for bindings of a formation accessible in a program by the #{path'}.
                  When this option is not specified, metrics for bindings are not reported.
                  Example of a #{path'}: 'org.eolang'.
                |]
      )

data CommandParser = CommandParser
  { metrics :: Parser CLI'MetricsPhi
  , transform :: Parser CLI'TransformPhi
  , dataize :: Parser CLI'DataizePhi
  , report :: Parser CLI'ReportPhi
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

  transform = do
    rulesPath <-
      let file' = metavarName.file
       in strOption (long "rules" <> short 'r' <> metavar.file <> help [i|#{file'} with user-defined rules. Must be specified.|])
    chain <- switch (long "chain" <> short 'c' <> help "Output transformation steps.")
    json <- jsonSwitch
    outputFile <- outputFileOption
    single <- switch (long "single" <> short 's' <> help "Output a single expression.")
    maxDepth <-
      let maxValue = 10
       in option auto (long "max-depth" <> metavar.int <> value maxValue <> help [i|Maximum depth of rules application. Defaults to #{maxValue}.|])
    maxGrowthFactor <-
      let maxValue = 10
       in option auto (long "max-growth-factor" <> metavar.int <> value maxValue <> help [i|The factor by which to allow the input term to grow before stopping. Defaults to #{maxValue}.|])
    inputFile <- inputFileArg
    pure CLI'TransformPhi{..}
  dataize = do
    rulesPath <- strOption (long "rules" <> short 'r' <> metavar.file <> help [i|#{fileMetavarName} with user-defined rules. Must be specified.|])
    inputFile <- inputFileArg
    outputFile <- outputFileOption
    recursive <- switch (long "recursive" <> help "Apply dataization + normalization recursively.")
    chain <- switch (long "chain" <> help "Display all the intermediate steps.")
    pure CLI'DataizePhi{..}
  report = do
    configFile <-
      let file' = metavarName.file
       in strOption (long "config" <> short 'c' <> metavar.file <> help [i|The #{file'} with a report configuration.|])
    pure CLI'ReportPhi{..}

data CommandParserInfo = CommandParserInfo
  { metrics :: ParserInfo CLI
  , transform :: ParserInfo CLI
  , dataize :: ParserInfo CLI
  , report :: ParserInfo CLI
  }

commandParserInfo :: CommandParserInfo
commandParserInfo =
  CommandParserInfo
    { metrics = info (CLI'MetricsPhi' <$> commandParser.metrics) (progDesc "Collect metrics for a PHI program.")
    , transform = info (CLI'TransformPhi' <$> commandParser.transform) (progDesc "Transform a PHI program.")
    , dataize = info (CLI'DataizePhi' <$> commandParser.dataize) (progDesc "Dataize a PHI program.")
    , report = info (CLI'ReportPhi' <$> commandParser.report) (progDesc "Generate reports about initial and normalized PHI programs.")
    }

data CommandNames = CommandNames
  { transform :: String
  , metrics :: String
  , dataize :: String
  , report :: String
  }

commandNames :: CommandNames
commandNames =
  CommandNames
    { transform = "transform"
    , metrics = "metrics"
    , dataize = "dataize"
    , report = "report"
    }

cli :: Parser CLI
cli =
  hsubparser
    ( command commandNames.transform commandParserInfo.transform
        <> command commandNames.metrics commandParserInfo.metrics
        <> command commandNames.dataize commandParserInfo.dataize
        <> command commandNames.report commandParserInfo.report
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
  | Impossible {message :: String}
  deriving anyclass (Exception)

instance Show CLI'Exception where
  show :: CLI'Exception -> String
  show = \case
    NotAFormation{..} -> [i|Could not find bindings at path '#{bindingsPath}' because an object at '#{path}' is not a formation.|]
    FileDoesNotExist{..} -> [i|File '#{file}' does not exist.|]
    CouldNotRead{..} -> [i|Could not read the program:\n#{message}|]
    CouldNotParse{..} -> [i|An error occurred when parsing the input program:\n#{message}|]
    CouldNotNormalize -> [i|Could not normalize the program.|]
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
                  [iii|
                    Impossible happened!
                    The option #{bindingsPath'} was not specified yet there were errors finding attributes by #{path'}.
                  |]
          Just bindingsPath' -> Left $ NotAFormation (intercalate "." path) bindingsPath'
      )
    Right metrics' -> pure metrics'

getMetrics :: Maybe String -> Maybe FilePath -> IO ProgramMetrics
getMetrics bindingsPath inputFile = do
  program <- getProgram inputFile
  either throw pure (getMetrics' program bindingsPath)

main :: IO ()
main = do
  opts <- customExecParser pprefs cliOpts
  let printAsProgramOrAsObject = \case
        Formation bindings' -> printTree $ Program bindings'
        x -> printTree x
  case opts of
    CLI'MetricsPhi' CLI'MetricsPhi{..} -> do
      (logStrLn, _) <- getLoggers outputFile
      metrics <- getMetrics bindingsPath inputFile
      logStrLn $ encodeToJSONString metrics
    CLI'TransformPhi' CLI'TransformPhi{..} -> do
      program' <- getProgram inputFile
      (logStrLn, logStr) <- getLoggers outputFile
      ruleSet <- parseRuleSetFromFile rulesPath
      unless (single || json) $ logStrLn ruleSet.title
      let Program bindings = program'
          uniqueResults
            | chain = applyRulesChainWith limits ctx (Formation bindings)
            | otherwise = pure . ("",) <$> applyRulesWith limits ctx (Formation bindings)
           where
            limits = ApplicationLimits maxDepth (maxGrowthFactor * objectSize (Formation bindings))
            ctx = defaultContext (convertRuleNamed <$> ruleSet.rules) (Formation bindings)
          totalResults = length uniqueResults
      when (null uniqueResults || null (head uniqueResults)) (throw CouldNotNormalize)
      if
        | single && json ->
            logStrLn
              . encodeToJSONString
              . printAsProgramOrAsObject
              $ snd (head (head uniqueResults))
        | single ->
            logStrLn
              . printAsProgramOrAsObject
              $ snd (head (head uniqueResults))
        | json ->
            logStrLn . encodeToJSONString $
              StructuredJSON
                { input = printTree program'
                , output = (propagateName1 printAsProgramOrAsObject <$>) <$> uniqueResults
                }
        | otherwise -> do
            logStrLn "Input:"
            logStrLn (printTree program')
            logStrLn "===================================================="
            forM_ (zip [1 ..] uniqueResults) $ \(index, steps) -> do
              logStrLn $
                "Result " <> show index <> " out of " <> show totalResults <> ":"
              let n = length steps
              forM_ (zip [1 ..] steps) $ \(k, (appliedRuleName, step)) -> do
                when chain $
                  logStr ("[ " <> show k <> " / " <> show n <> " ] " <> appliedRuleName <> ": ")
                logStrLn . printAsProgramOrAsObject $ step
              logStrLn "----------------------------------------------------"
    CLI'DataizePhi' CLI'DataizePhi{..} -> do
      (logStrLn, _logStr) <- getLoggers outputFile
      program' <- getProgram inputFile
      ruleSet <- parseRuleSetFromFile rulesPath
      let (Program bindings) = program'
      let inputObject = Formation bindings
      let ctx = defaultContext (convertRuleNamed <$> ruleSet.rules) inputObject
      ( if chain
          then do
            let dataizeChain
                  | recursive = dataizeRecursivelyChain
                  | otherwise = dataizeStepChain
            forM_ (dataizeChain ctx inputObject) $ \case
              (msg, Left obj) -> logStrLn (msg ++ ": " ++ printTree obj)
              (msg, Right (Bytes bytes)) -> logStrLn (msg ++ ": " ++ bytes)
          else do
            let dataize
                  -- This should be moved to a separate subcommand
                  | recursive = dataizeRecursively
                  | otherwise = dataizeStep
            case dataize ctx inputObject of
              Left obj -> logStrLn (printAsProgramOrAsObject obj)
              Right (Bytes bytes) -> logStrLn bytes
        )
    CLI'ReportPhi' CLI'ReportPhi{..} -> do
      reportConfig <- decodeFileThrow configFile

      programReports <- forM reportConfig.items $ \item -> do
        metricsPhi <- getMetrics item.bindingsPathPhi (Just item.phi)
        metricsPhiNormalized <- getMetrics item.bindingsPathPhiNormalized (Just item.phiNormalized)
        pure $ makeProgramReport reportConfig item metricsPhi metricsPhiNormalized

      css <- maybe (pure reportCSS) readFile (reportConfig.input >>= (.css))
      js <- maybe (pure reportJS) readFile (reportConfig.input >>= (.js))

      let report = makeReport reportConfig programReports
          ReportConfig{..} = reportConfig
          reportConfigHtml = ReportHtml.ReportConfig{format = ReportFormat'Html{..}, ..}
          reportHtml = toStringReport reportConfigHtml report

          reportJson = encodeToJSONString report

          reportConfigMarkdown = ReportHtml.ReportConfig{format = ReportFormat'Markdown, ..}
          reportMarkdown = toStringReport reportConfigMarkdown report

      forM_ @[]
        [ (x, y)
        | (Just x, y) <-
            [ (reportConfig.output.html, reportHtml)
            , (reportConfig.output.json, reportJson)
            , (reportConfig.output.markdown, reportMarkdown)
            ]
        ]
        $ \(path, reportString) -> do
          createDirectoryIfMissing True (takeDirectory path)
          writeFile path reportString

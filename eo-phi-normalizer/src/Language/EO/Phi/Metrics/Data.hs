{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module Language.EO.Phi.Metrics.Data where

import Data.Aeson (ToJSON (..), Value (..), withObject, withScientific, withText, (.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (FromJSON (..), Parser, parseFail)
import Data.Generics.Labels ()
import Data.List (groupBy, intercalate)
import Data.Scientific (toRealFloat)
import GHC.Generics (Generic)
import Language.EO.Phi.Rules.Common ()
import Language.EO.Phi.TH (deriveJSON)

data Metrics a = Metrics
  { dataless :: a
  , applications :: a
  , formations :: a
  , dispatches :: a
  }
  deriving stock (Show, Generic, Eq, Functor, Foldable, Traversable)

$(deriveJSON ''Metrics)

toListMetrics :: Metrics a -> [a]
toListMetrics = foldMap (: [])

instance Applicative Metrics where
  pure :: a -> Metrics a
  pure a =
    Metrics
      { dataless = a
      , applications = a
      , formations = a
      , dispatches = a
      }

  (<*>) :: Metrics (a -> b) -> Metrics a -> Metrics b
  x <*> y =
    Metrics
      { dataless = x.dataless y.dataless
      , applications = x.applications y.applications
      , formations = x.formations y.formations
      , dispatches = x.dispatches y.dispatches
      }

instance (Num a) => Num (Metrics a) where
  (+) :: Metrics a -> Metrics a -> Metrics a
  (+) x y = (+) <$> x <*> y
  (-) :: Metrics a -> Metrics a -> Metrics a
  (-) x y = (-) <$> x <*> y
  (*) :: Metrics a -> Metrics a -> Metrics a
  (*) x y = (*) <$> x <*> y
  negate :: Metrics a -> Metrics a
  negate = (negate <$>)
  abs :: Metrics a -> Metrics a
  abs = (abs <$>)
  signum :: Metrics a -> Metrics a
  signum = (signum <$>)
  fromInteger :: Integer -> Metrics a
  fromInteger x = pure $ fromInteger x

data SafeNumber a = SafeNumber'NaN | SafeNumber'Number a
  deriving stock (Functor)

-- >>> import Data.Aeson (decode')
--
-- >>> decode' @(SafeNumber Double) "\"NaN\""
-- Just NaN
--
-- >>> decode' @(SafeNumber Double) "3"
-- Just 3.0

instance (FromJSON a, RealFloat a) => FromJSON (SafeNumber a) where
  parseJSON :: Value -> Parser (SafeNumber a)
  parseJSON (String s) =
    withText
      "NaN"
      ( \case
          "NaN" -> pure SafeNumber'NaN
          _ -> parseFail "String is not a NaN"
      )
      (String s)
  parseJSON (Number n) =
    withScientific
      "Number"
      (pure . pure . toRealFloat)
      (Number n)
  parseJSON _ = parseFail "Value is not a NaN or a Number"

instance (ToJSON a) => ToJSON (SafeNumber a) where
  toJSON :: SafeNumber a -> Value
  toJSON (SafeNumber'Number a) = toJSON a
  toJSON SafeNumber'NaN = toJSON ("NaN" :: String)

instance (Show a) => Show (SafeNumber a) where
  show :: SafeNumber a -> String
  show (SafeNumber'Number a) = show a
  show SafeNumber'NaN = "NaN"

instance (Eq a) => Eq (SafeNumber a) where
  (==) :: SafeNumber a -> SafeNumber a -> Bool
  (==) (SafeNumber'Number x) (SafeNumber'Number y) = x == y
  (==) _ _ = False

instance (Ord a) => Ord (SafeNumber a) where
  (<=) :: SafeNumber a -> SafeNumber a -> Bool
  (SafeNumber'Number x) <= (SafeNumber'Number y) = x <= y
  _ <= SafeNumber'Number _ = True
  _ <= _ = False

instance Applicative SafeNumber where
  pure :: a -> SafeNumber a
  pure = SafeNumber'Number
  (<*>) :: SafeNumber (a -> b) -> SafeNumber a -> SafeNumber b
  (<*>) (SafeNumber'Number x') (SafeNumber'Number y') = SafeNumber'Number (x' y')
  (<*>) _ _ = SafeNumber'NaN

instance (Num a) => Num (SafeNumber a) where
  (+) :: SafeNumber a -> SafeNumber a -> SafeNumber a
  (+) x y = (+) <$> x <*> y
  (*) :: SafeNumber a -> SafeNumber a -> SafeNumber a
  (*) x y = (*) <$> x <*> y
  abs :: SafeNumber a -> SafeNumber a
  abs = (abs <$>)
  signum :: SafeNumber a -> SafeNumber a
  signum = (signum <$>)
  fromInteger :: Integer -> SafeNumber a
  fromInteger x = pure $ fromInteger x
  negate :: SafeNumber a -> SafeNumber a
  negate = (negate <$>)

instance (Fractional a, Eq a) => Fractional (SafeNumber a) where
  fromRational :: Rational -> SafeNumber a
  fromRational = SafeNumber'Number . fromRational
  (/) :: SafeNumber a -> SafeNumber a -> SafeNumber a
  (/) (SafeNumber'Number x) (SafeNumber'Number y) | y /= 0 = SafeNumber'Number (x / y)
  (/) _ _ = SafeNumber'NaN

type MetricsSafe a = Metrics (SafeNumber a)

instance (Fractional a, Eq a) => Fractional (MetricsSafe a) where
  fromRational :: Rational -> MetricsSafe a
  fromRational _ = 0
  (/) :: MetricsSafe a -> MetricsSafe a -> MetricsSafe a
  (/) x y = (/) <$> x <*> y

instance (Num a) => Semigroup (Metrics a) where
  (<>) :: Metrics a -> Metrics a -> Metrics a
  (<>) = (+)

instance (Num a) => Monoid (Metrics a) where
  mempty :: Metrics a
  mempty = 0

type MetricsCount = Metrics Int

data BindingMetrics = BindingMetrics
  { name :: String
  , metrics :: MetricsCount
  }
  deriving stock (Show, Generic, Eq)

$(deriveJSON ''BindingMetrics)

type Path = [String]

data BindingsByPathMetrics = BindingsByPathMetrics
  { path :: Path
  , bindingsMetrics :: [BindingMetrics]
  }
  deriving (Show, Generic, Eq)

-- >>> splitStringOn '.' "abra.cada.bra"
-- ["abra","cada","bra"]
--
-- >>> splitStringOn '.' ""
-- []
splitStringOn :: Char -> String -> Path
splitStringOn sep = filter (/= [sep]) . groupBy (\a b -> a /= sep && b /= sep)

splitPath :: String -> Path
splitPath = splitStringOn '.'

instance FromJSON BindingsByPathMetrics where
  parseJSON :: Value -> Parser BindingsByPathMetrics
  parseJSON = withObject "BindingsByPathMetrics" $ \obj -> do
    path <- splitPath <$> (obj .: "path")
    bindingsMetrics <- obj .: "bindings-metrics"
    pure BindingsByPathMetrics{..}

instance ToJSON BindingsByPathMetrics where
  toJSON :: BindingsByPathMetrics -> Value
  toJSON BindingsByPathMetrics{..} =
    Aeson.object
      [ "path" .= intercalate "." path
      , "bindings-metrics" .= bindingsMetrics
      ]

data ObjectMetrics = ObjectMetrics
  { bindingsByPathMetrics :: Maybe BindingsByPathMetrics
  , thisObjectMetrics :: MetricsCount
  }
  deriving (Show, Generic, Eq)

$(deriveJSON ''ObjectMetrics)

data ProgramMetrics = ProgramMetrics
  { bindingsByPathMetrics :: Maybe BindingsByPathMetrics
  , programMetrics :: MetricsCount
  }
  deriving (Show, Generic, Eq)

$(deriveJSON ''ProgramMetrics)

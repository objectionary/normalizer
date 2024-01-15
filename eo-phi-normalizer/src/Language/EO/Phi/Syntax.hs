{-# LANGUAGE LambdaCase #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Language.EO.Phi.Syntax (
  module Language.EO.Phi.Syntax.Abs,
  parseObject,
  unsafeParseObject,
  printTree,
) where

import Data.Char (isSpace)
import Data.String (IsString (..))
import Language.EO.Phi.Syntax.Abs
import qualified Language.EO.Phi.Syntax.Abs as Phi
import qualified Language.EO.Phi.Syntax.Par as Phi
import qualified Language.EO.Phi.Syntax.Print as Phi

instance IsString Phi.Object where
  fromString = unsafeParseObject

-- | Parse a 'Object' or return a parsing error.
parseObject :: String -> Either String Phi.Object
parseObject input = Phi.pObject tokens
 where
  tokens = Phi.myLexer input

-- | Parse a 'Object' from a 'String'.
-- May throw an 'error` if input has a syntactical or lexical errors.
unsafeParseObject :: String -> Phi.Object
unsafeParseObject input =
  case parseObject input of
    Left parseError -> error parseError
    Right object -> object

-- * Overriding generated pretty-printer

-- | Like 'Phi.printTree', but without spaces around dots and no indentation for curly braces.
printTree :: (Phi.Print a) => a -> String
printTree = shrinkDots . render . Phi.prt 0

-- | Remove spaces around dots.
--
-- >>> putStrLn (shrinkDots "a ↦ ξ . a")
-- a ↦ ξ.a
shrinkDots :: String -> String
shrinkDots [] = []
shrinkDots (' ' : '.' : ' ' : cs) = '.' : shrinkDots cs
shrinkDots (c : cs) = c : shrinkDots cs

-- | Copy of 'Phi.render', except no indentation is made for curly braces.
render :: Phi.Doc -> String
render d = rend 0 False (map ($ "") $ d []) ""
 where
  rend ::
    Int ->
    -- \^ Indentation level.
    Bool ->
    -- \^ Pending indentation to be output before next character?
    [String] ->
    ShowS
  rend i p = \case
    "[" : ts -> char '[' . rend i False ts
    "(" : ts -> char '(' . rend i False ts
    -- "{"      :ts -> onNewLine i     p . showChar   '{'  . new (i+1) ts
    -- "}" : ";":ts -> onNewLine (i-1) p . showString "};" . new (i-1) ts
    -- "}"      :ts -> onNewLine (i-1) p . showChar   '}'  . new (i-1) ts
    [";"] -> char ';'
    ";" : ts -> char ';' . new i ts
    t : ts@(s : _)
      | closingOrPunctuation s ->
          pending . showString t . rend i False ts
    t : ts -> pending . space t . rend i False ts
    [] -> id
   where
    -- Output character after pending indentation.
    char :: Char -> ShowS
    char c = pending . showChar c

    -- Output pending indentation.
    pending :: ShowS
    pending = if p then indent i else id

  -- Indentation (spaces) for given indentation level.
  indent :: Int -> ShowS
  indent i = Phi.replicateS (2 * i) (showChar ' ')

  -- Continue rendering in new line with new indentation.
  new :: Int -> [String] -> ShowS
  new j ts = showChar '\n' . rend j True ts

  -- Separate given string from following text by a space (if needed).
  space :: String -> ShowS
  space t s =
    case (all isSpace t, null spc, null rest) of
      (True, _, True) -> [] -- remove trailing space
      (False, _, True) -> t -- remove trailing space
      (False, True, False) -> t ++ ' ' : s -- add space if none
      _ -> t ++ s
   where
    (spc, rest) = span isSpace s

  closingOrPunctuation :: String -> Bool
  closingOrPunctuation [c] = c `elem` closerOrPunct
  closingOrPunctuation _ = False

  closerOrPunct :: String
  closerOrPunct = ")],;"
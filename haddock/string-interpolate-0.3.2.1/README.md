# string-interpolate [![pipeline status](https://gitlab.com/williamyaoh/string-interpolate/badges/master/pipeline.svg)](https://gitlab.com/williamyaoh/string-interpolate/commits/master) [![hackage version](https://img.shields.io/hackage/v/string-interpolate.svg)](http://hackage.haskell.org/package/string-interpolate) [![license](https://img.shields.io/badge/license-BSD--3-ff69b4.svg)](https://gitlab.com/williamyaoh/string-interpolate/blob/master/LICENSE)

Haskell having 5 different textual types in common use (String, strict and lazy
Text, strict and lazy ByteString) means that doing any kind of string
manipulation becomes a complicated game of type tetris with constant conversion
back and forth. What if string handling was as simple and easy as it is in
literally any other language?

Behold:

```haskell
showWelcomeMessage :: Text -> Integer -> Text
showWelcomeMessage username visits =
  [i|Welcome to my website, #{username}! You are visitor #{visits}!|]
```

No more needing to `mconcat`, `mappend`, and `(<>)` to glue strings together.
No more having to remember a gajillion different functions for converting
between strict and lazy versions of Text, or having to worry about encoding
between Text <=> ByteString. No more getting bitten by trying to work with
Unicode ByteStrings. It just works!

**string-interpolate** provides a quasiquoter, `i`, that allows you to interpolate
expressions directly into your string. It can produce anything that is an
instance of `IsString`, and can interpolate anything which is an instance of
`Show`.

In addition to the main quasiquoter `i`, there are two additional quasiquoters
for handling multiline strings. If you need to remove extra whitespace and
collapse into a single line, use `iii`. If you need to remove extra indentation
but keep linebreaks, use `__i`.

If you need even *more* specific functionality in how you handle whitespace,
there are variants of `__i` and `iii` with different behavior for
surrounding newlines. These are suffixed by either `'E` or `'L` depending
on what behavior you need. For instance, `__i'E` will remove extra indentation
from its body, but will leave any surrounding newlines intact. `iii'L` will
collapse its body into a single line, and collapse any surrounding newlines
at the beginning/end into a single newline.

## Unicode handling

**string-interpolate** handles converting to/from Unicode when converting
String/Text to ByteString and vice versa. Lots of libraries use ByteString to
represent human-readable text, even though this is not safe. There are lots of
useful libraries in the ecosystem that are unfortunately annoying to work with
because of the need to generate ByteStrings containing application-specific info.
Insisting on explicitly converting to/from UTF-8 in these cases and handling
decoding failures adds lots of syntactic noise, when often you can reasonably
assume that a given ByteString will, 95% of the time, contain Unicode text.
So string-interpolate aims to provide reasonable defaults around conversion
between ByteString and real textual types so that developers don't need to
constantly be aware of text encodings.

When converting a String/Text to a ByteString, **string-interpolate** will
automatically encode it as a sequence of UTF-8 bytes. When converting a
ByteString to String/Text, string-interpolate will assume that the ByteString
contains a UTF-8 string, and convert the characters accordingly. Any invalid
characters in the ByteString will be converted to the Unicode replacement
character � (U+FFFD).

Remember: **string-interpolate** is not designed for 100% correctness around text
encodings, just for convenience in the most common case. If you absolutely need
to be aware of text encodings and to handle decode failures, take a look at
[text-conversions](https://hackage.haskell.org/package/text-conversions).

## Usage

First things first: add **string-interpolate** to your dependencies:

```yaml
dependencies:
  - string-interpolate
```

and import the quasiquoter and enable `-XQuasiQuotes`:

```haskell
{-# LANGUAGE QuasiQuotes #-}

import Data.String.Interpolate ( i )
```

Wrap anything you want to be interpolated with `#{}`:

```haskell
λ> name = "William"
λ> [i|Hello, #{name}!|] :: String
>>> "Hello, William!"
```

You can interpolate in anything which implements `Show`:

```haskell
λ> import Data.Time
λ> now <- getCurrentTime
λ> [i|The current time is #{now}.|] :: String
>>> "The current time is 2019-03-10 18:58:40.573892546 UTC."
```

...and interpolate into anything which implements `IsString`.

string-interpolate *must* know what concrete type it's producing; it cannot be
used to generate a `IsString a => a`. If you're using string-interpolate from
GHCi, make sure to add type signatures to toplevel usages!

string-interpolate also needs to know what concrete type it's *interpolating*.
For instance, the following code won't work:

```haskell
showIt :: Show a => a -> String
showIt it = [i|The value: #{it}|]
```

You would need to convert `it` to a String using `show` first.

Strings and characters are always interpolated without surrounding quotes.

```haskell
λ> verb = 'c'
λ> noun = "sea"
λ> [i|We went to go #{verb} the #{noun}.|] :: String
>>> "We went to go c the sea."
```

You can interpolate arbitrary expressions:

```haskell
λ> [i|Tomorrow's date is #{addDays 1 $ utctDay now}.|] :: String
>>> "Tomorrow's date is 2019-03-11."
```

**string-interpolate**, by default, handles multiline strings by copying the
newline verbatim into the output.

```haskell
λ> :{
 | [i|
 |   a
 |   b
 |   c
 | |] :: String
 | :}
>>> "\n  a\n  b\n  c\n"
```

Another quasiquoter, `iii`, is provided that handles multiline strings/whitespace
in a different way, by collapsing any whitespace into a single space. The
intention is to use it when you want to split something across multiple
lines in source for readability but want it emitted like a normal sentence.
`iii` is otherwise identical to `i`, with the ability to interpolate arbitrary values.

```haskell
λ> :{
 | [iii|
 |   Lorum
 |   ipsum
 |   dolor
 |   sit
 |   amet.
 | |] :: String
 | :}
>>> "Lorum ipsum dolor sit amet."
```

One last quasiquoter, `__i`, is provided that handles removing indentation
without removing line breaks, perhaps if you need to output code samples
or error messages. Again, `__i` is otherwise identical to `i`, with the ability
to interpolate arbitrary values.

```haskell
λ> :{
 | [__i|
 |   id :: a -> a
 |   id x = y
 |     where y = x
 | |] :: String
 | :}
>>> "id :: a -> a\nid x = y\n  where y = x"
```

The intended mnemonics for remembering what `iii` and `__i` do:

* `iii`: Look at the i's as individual lines which have been collapsed into a single line
* `__i`: Look at the i as being indented

In addition, there are variants of `iii` and `__i`, desginated by a letter
suffix. For instance, `__i'L` will reduce indentation, while collapsing
any surrounding newlines into a single newline.

```haskell
λ> :{
 | [__i'L|
 |
 |   id :: a -> a
 |   id x = y
 |     where y = x
 |
 | |] :: String
 | :}
>>> "\nid :: a -> a\nid x = y\n  where y = x\n"
```

Currently there are two variant suffixes, `'E` and `'L`'

* `'E`: Leave any surrounding newlines intact. To remember what this does, look
  visually at the capital E; the multiple horizontal lines suggests multiple
  newlines.
* `'L`: Collapse any surrounding newlines into a single newline. To remember what
  this does, look visually at the capital L; the single horizontal line suggests
  a single newline.

Check the Haddock documentation for all the available variants.

Backslashes are handled exactly the same way they are in normal Haskell strings.
If you need to put a literal `#{` into your string, prefix the pound symbol with
a backslash:

```haskell
λ> [i|\#{ some inner text }#|] :: String
>>> "#{ some inner text }#"
```

## Comparison to other interpolation libraries

Some other interpolation libraries available:

* [**interpolate**](https://hackage.haskell.org/package/interpolate)
* [**formatting**](https://hackage.haskell.org/package/formatting)
* **Text.Printf**, from base
* [**neat-interpolation**](https://hackage.haskell.org/package/neat-interpolation)
* [**Interpolation**](http://hackage.haskell.org/package/Interpolation)
* [**interpolatedstring-perl6**](http://hackage.haskell.org/package/interpolatedstring-perl6-1.0.1)

Of these, **Text.Printf** isn't exception-safe, and **neat-interpolation** can only
produce strict Text values. **interpolate**, **formatting**, **Interpolation**, and
**interpolatedstring-perl6** provide different solutions to the problem of
providing a general way of interpolating any value, into any kind of text.

### Features

|                                          | string-interpolate | interpolate | formatting | Interpolation | interpolatedstring-perl6 | neat-interpolation |
|------------------------------------------|--------------------|-------------|------------|---------------|--------------------------|--------------------|
| String/Text support                      | ✅                  | ✅           | ✅          | ⚠️             | ✅                        | ⚠️                  |
| ByteString support                       | ✅                  | ✅           | ❌          | ⚠️             | ✅                        | ❌                  |
| Can interpolate arbitrary Show instances | ✅                  | ✅           | ✅          | ✅             | ✅                        | ❌                  |
| Unicode-aware                            | ✅                  | ❌           | ⚠️          | ❌             | ❌                        | ⚠️                  |
| Multiline strings                        | ✅                  | ✅           | ✅          | ✅             | ✅                        | ✅                  |
| Indentation handling                     | ✅                  | ✅           | ❌          | ✅             | ❌                        | ✅                  |
| Whitespace/newline chomping              | ✅                  | ❌           | ❌          | ❌             | ❌                        | ❌                  |

⚠ Since **formatting** doesn't support ByteStrings, it technically supports
  Unicode.

⚠ **Interpolation** supports all five textual formats, but doesn't allow you
  to mix and match; that is, you can't interpolate a String into an output
  string of type Text, and vice versa.

⚠ **neat-interpolation** only supports strict Text. Because of that, it technically
  supports Unicode.

### Performance

Overall: **string-interpolate** is competitive with the fastest interpolation
libraries, only getting outperformed on ByteStrings by **Interpolation** and
**interpolatedstring-perl6**, and on large, strict Text specifically by **formatting**.

We run three benchmarks: small string interpolation (<100 chars) with a single
interpolation parameter; small strings with multiple interpolation parameters,
and large string (~100KB) interpolation. Each of these benchmarks is then run
against `String`, both `Text` types, and both `ByteString` types. Numbers are
runtime in relation to string-interpolate; smaller is better.

|                               | **string-interpolate** | **formatting** | **Interpolation** | **interpolatedstring-perl6** | **neat-interpolation** | **interpolate** |
|-------------------------------|------------------------|----------------|-------------------|------------------------------|------------------------|-----------------|
| small String                  | 1x                     | 2.8x           | 1x                | 1x                           |                        | 1x              |
| multi interp, String          | 1x                     | 4.3x           | 1x                | 1x                           |                        | 7.9x            |
| small Text                    | 1x                     | 4.3x           | 1.8x              | 1.9x                         | 5.8x                   | 61x             |
| multi interp, Text            | 1x                     | 3.5x           | 5.3x              | 5.3x                         | 3.3x                   | 29x             |
| large Text                    | 1x                     | 0.6x           | 11x               | 11x                          | 22x                    | 10,000x         |
| small lazy Text               | 1x                     | 6.1x           | 14.5x             | 14.5x                        |                        | 93x             |
| multi interp, lazy Text       | 1x                     | 3.7x           | 5.8x              | 6x                           |                        | 34x             |
| large lazy Text               | 1x                     | 3.9x           | 22,000x           | 22,000x                      |                        | 3,500,000x      |
| small ByteString              | 1x                     |                | 1x                | 1x                           |                        | 47x             |
| multi interp, ByteString      | 1x                     |                | 0.7x              | 0.7x                         |                        | 17x             |
| large ByteString              | 1x                     |                | 1x                | 1x                           |                        | 31,000x         |
| small lazy ByteString         | 1x                     |                | 1x                | 1x                           |                        | 85x             |
| multi interp, lazy ByteString | 1x                     |                | 0.4x              | 0.4x                         |                        | 19x             |
| large lazy ByteString         | 1x                     |                | 0.8x              | 0.8x                         |                        | 1,300,000x      |

(We don't bother running tests on large `String`s, because no one is working
with data that large using `String` anyways.)

In particular, notice that **Interpolation** and **interpolatedstring-perl6**
blow up on both Text types; **string-interpolate** and **formatting** have
consistent performance across all benchmarks, with string-interpolation leading
the pack in `Text` cases.

All results were tested on an AWS EC2 `t2.medium`, with GHC 8.6.5. If you'd
like to replicate the results, the benchmarks are located in `bench/`, and can
be run with `cabal v2-run string-interpolate-bench -O2 -fextended-benchmarks`.

#### Larger Text and ByteString

By default, **string-interpolate** is performance tuned for outputting smaller
strings. If you find yourself regularly needing extremely large outputs, however,
you can change the way output strings are constructed to optimize accordingly.
Enable either the `text-builder` or `bytestring-builder` Cabal flag, depending
on your need, and you should see speedups constructing large strings, at the
cost of slowing down smaller outputs.

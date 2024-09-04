# Custom rules

[N.B: Replace text in square brackets with your text]

| authors                      | date-accepted                         | pr-url                                                     | implemented                                              |
| --------------------------- | ------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------------- |
| Max Trunnikov, Danila Danko | [Date when the proposal was accepted] | [URL](https://github.com/objectionary/normalizer/pull/259) | [normalizer version where this proposal was implemented] |

## Motivation

We need to perform optimizations of particular objects.

These optimizations will be expressed as transformations of `PHI` terms specified via the `MetaPHI` language.

The `MetaPHI` language is `PHI` with additional language constructs.

The current grammar of `MetaPHI` [LBNF grammar](https://bnfc.readthedocs.io/en/latest/lbnf.html) is available by [this link](https://github.com/objectionary/normalizer/blob/17b23dfa447d5b3c0215e1fd5557593948024357/eo-phi-normalizer/grammar/EO/Phi/Syntax.cf).

## Proposed Change Specification

The proposed changes are based on [this example](https://github.com/objectionary/normalizer/issues/65#issuecomment-1910968223).

Currently, `normalizer` uses the `MetaPHI` language to specify [pattern-matching](https://github.com/objectionary/normalizer/pull/258) and [transformations](#transformations).

Custom rules extend `MetaPHI` with [functions](#functions) and [predicates](#predicates).

### Transformations

A transformation specifies:

- `pattern` - A `MetaPHI` expression to match against another `MetaPHI` expression.
- `guards` - Predicates on `MetaPHI` expressions (like Haskell's [guards](https://stackoverflow.com/questions/52507795/haskell-pattern-matching-with-guards)).
- `result` - Constructed `MetaPHI` expression.

#### Example

A transformation:

```yaml
pattern: ⟦ \?Name name ↦ ⟦ ?a ↦ Φ.a.c ⟧ ⟧
guards:
  - "?a == a"
result: ⟦ ?a ↦ ⟦ ?Name ⟧ ⟧
```

The transformation applied to an input:

```yaml
input: ⟦ name ↦ ⟦ a ↦ Φ.a.c ⟧ ⟧
matches:
  - metavar: "?Name"
    value: name ↦ ⟦ a ↦ Φ.a.c ⟧
  - metavar: "?a"
    value: a
results:
  - value: ⟦ a ↦ ⟦ name ↦ ⟦ a ↦ Φ.a.c ⟧ ⟧ ⟧
```

### Functions

Functions specify mappings between arguments (`MetaPHI` expressions) and values.

Functions can be used in results and guards of [transformations](#transformations).

Functions are interpreted by the `normalizer`.

- [ ] Should we allow specifying functions by providing signatures to transformations?

#### Grammar

```console
Expression. Expression ::= Binding | Object | MetaFunction;

Argument. Argument ::= (LabelId ":") ? Expression

MetaFunction. MetaFunction ::= "$" LabelId "(" [ Argument ] ")" ;

separator Expression "," ;
```

#### Syntax

A `signature` here is a way to communicate the types of arguments and return values.

A `signature` does *not* conform to the grammar of a function defined above.

- [ ] Should we parse such signatures?
- [ ] Or, should we just use them as a specification?

```yaml
- signature: |
    $dot(prefix: (Expression), suffix: (Expression)): (Expression)
  description: |
    Return the dispatch <prefix>.<suffix>
  examples:
    - applications:
        - application: $dot(ξ, $dot(ρ, $dot($name(?b_a), write(α0 ↦ ?t))))
          # Note the result isn't a value because the result contains MetaId-s
          result: ξ.ρ.?b_a.write(α0 ↦ ?t)
- signature: |
    $name(binding: (MetaId)): Attribute
  description: |
    Return the name of <binding>.
  examples:
    - pattern: ⟦ \?Name ?a ↦ ⟦ ?A ⟧ ⟧
      input: ⟦ name ↦ ⟦ a ↦ Φ.a.c, b ↦ Φ.a.c ⟧ ⟧
      matches:
        - metavar: "?Name"
          value: name ↦ ⟦ a ↦ Φ.a.c, b ↦ Φ.a.c ⟧
        - metavar: "?a"
          value: name
      applications:
        - application: $name(?Name)
          value: name
- signature: |
    $names(bindings: (MetaId | Function)): [Attribute]
  description: |
    Return the names of <bindings>.
  examples:
    - pattern: "⟦ ?B ⟧"
      input: "⟦ a ↦ Φ.b, c ↦ Φ.c ⟧"
      matches:
        - metavar: "?B"
          value: a ↦ Φ.b, c ↦ Φ.c
      applications:
        - application: $names(?B)
          value: a, c
- signature: |
    $replace(e1: (Expression), e2: (Expression), e3: (Expression)): Expression
  description: |
    Return <e1> with all occurencies of <e2> replaced with <e3>.
  examples:
    - pattern: ⟦ a ↦ ?B ⟧
      input: ⟦ a ↦ ⟦ a ↦ Φ.a, b ↦ Φ.b, c ↦ Φ.c ⟧ ⟧
      matches:
        - metavar: "?B"
          value: ⟦ a ↦ Φ.a, b ↦ Φ.b, c ↦ Φ.c ⟧
      application: $replace(?B, Φ.b, Φ.baz)
# FIXME what's the semantics ???
- signature: |
    $combine(b1: (MetaId), b2: (MetaId)): [Binding]
  # FIXME order of elements depends on order of bindings in code?
  description: |
    Return new bindings obtained by combining <b1> and <b2>.

    ?B1: [a1 -> x, a2 -> y, a3 -> z]
    ?B2: [b1 -> c, b2 -> d, b3 -> e]
    $combine(?B1, ?B2) => [a1 -> c, a2 -> d, a3 -> e]
  examples:
    - pattern: ⟦ a ↦ ⟦ ?A ⟧, b ↦ ⟦ ?B ⟧ ⟧
      input: ⟦ a ↦ ⟦ a ↦ Φ.a, b ↦ Φ.b, c ↦ Φ.c ⟧, b ↦ ⟦ d ↦ Φ.d, e ↦ Φ.e ⟧ ⟧
      matches:
        - metavar: "?A"
          value: a ↦ Φ.a, b ↦ Φ.b, c ↦ Φ.c
        - metavar: "?B"
          value: a ↦ Φ.a, d ↦ Φ.d, e ↦ Φ.e
      applications:
        - application: $combine(?A, ?B)
          value: a ↦ Φ.d, b ↦ Φ.e
  comments:
    Inspiration 1:
      array_combine - https://www.php.net/manual/ru/function.array-combine.php
    Inspiration 2: |
      func foo1(int x, string y)
      func foo2(bool z, char a)

      foo1(1, “s”)
      foo2(true, ‘x’)

      func foo_combo(int x, string y, bool z, char a)

      foo_combo(1, “s”, true, ‘x’)
# FIXME what's the semantics ???
- signature: |
    $unique(bindings: (MetaId)): [Binding]
  description: |
    Replace all names in <bindings> with unique names.
  examples:
    - $unique(?B)
# FIXME what's the semantics ???
- signature: |
    $prefixed(name1: (Expression), name2: (Expression)): ???
```

### Predicates

Predicates are [functions](#functions) that return boolean values.

Predicates are used for introducing additional constraints on pattern-matched values.

#### Syntax

```yaml
- signature: |
    $for-all(bindings: (MetaId), arg: (MetaId), predicate: (Predicate)): Bool
  description: |
    Check that the <predicate> is TRUE for all <bindings>.
    You can use <arg> inside the <predicate>.
  examples: See below
- signature: |
    $bound-to(name: (MetaId), value: (Expression)): Bool
  description: |
    Check that <name> is bound to <value>.
  examples:
    - pattern: "⟦ ?name ↦ Φ.?a.b, ?B ⟧"
      input: ⟦ name ↦ Φ.a.b, a ↦ Φ.a.c, b ↦ Φ.a.c ⟧
      matches:
        - metavar: "?name"
          value: name
        - metavar: "?a"
          value: a
        - metavar: "?B"
          value: a ↦ Φ.a.c, b ↦ Φ.a.c
      where:
        - condition: $bound-to(?name, ∅)
          value: "FALSE"
        - condition: $for-all(?B, ?binding, $bound-to(?binding, Φ.a.c))
          value: "TRUE"
- signature: |
    $starts-with(name: (Expression), prefix: (String)): Bool
  description: |
    Check that <name> starts with <prefix>.
  examples:
    - pattern: '⟦ \?Binding Φ.?a.b, ?Bindings ⟧'
      input: "⟦ name ↦ ⟦ k ↦ Φ.a.b ⟧, a_foo ↦ Φ.a.c, a_bar ↦ Φ.a.c ⟧"
      matches:
        - metavar: "?Binding"
          value: name ↦ ⟦ k ↦ Φ.a.b ⟧
        - metavar: "?Bindings"
          value: a_foo ↦ Φ.a.c, a_bar ↦ Φ.a.c
      where:
        - condition: $for-all(?Bindings, ?binding, $starts-with($name(?binding), "a_"))
          value: TRUE
- signature: |
    $not(predicate: (Predicate)): Bool
  description: |
    Negate the <predicate>.
  examples:
    - pattern: "⟦ ?name ↦ Φ.?a.b, ?B ⟧"
      input: ⟦ name ↦ Φ.foo.b ⟧
      matches:
        - metavar: "?name"
          value: name
        - metavar: "?a"
          value: foo
        - metavar: "?B"
          value: []
      where:
        - condition: $not($starts-with(?a), "foo")
          value: FALSE
        - condition: $not($bound-to(?name, Φ))
          value: TRUE
```

## Examples

[
This section illustrates the specification through the use of examples of the
language change proposed. It is best to exemplify each point made in the
specification, though perhaps one example can cover several points. Contrived
examples are OK here. If the Motivation section describes something that is
hard to do without this proposal, this is a good place to show how easy that
thing is to do with the proposal.
]

## Effect and Interactions

[
Your proposed change addresses the issues raised in the
motivation. Explain how.

Also, discuss possibly contentious interactions with existing language or normalizer
features. Complete this section with potential interactions raised
during the PR discussion.
]

## Alternatives

[
List alternative designs to your proposed change. Both existing
workarounds, or alternative choices for the changes. Explain
the reasons for choosing the proposed change over these alternative:
*e.g.* they can be cheaper but insufficient, or better but too
expensive. Or something else.

The PR discussion often raises other potential designs, and they should be
added to this section. Similarly, if the proposed change
specification changes significantly, the old one should be listed in
this section.
]

## Unresolved Questions

[
Explicitly list any remaining issues that remain in the conceptual design and
specification. Please do not list *implementation* issues.
]

## Implementation Plan

[
(Optional) If accepted who will implement the change?
Which other resources and prerequisites are required for implementation?
]

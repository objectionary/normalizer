# Extended pattern matching

[N.B: Replace text in square brackets with your text]

| authors                       | date-accepted                         | pr-url                                                     | implemented                                              |
| ----------------------------- | ------------------------------------- | ---------------------------------------------------------- | -------------------------------------------------------- |
| Maxim Trunnikov, Danila Danko | [Date when the proposal was accepted] | [URL](https://github.com/objectionary/normalizer/pull/258) | [normalizer version where this proposal was implemented] |

## Motivation

Some optimizations should be performed on specific objects deep within a program.

Therefore, one needs a way to find such objects using pattern matching.

## Proposed Change Specification

### Syntax v0

[Original example](https://github.com/objectionary/normalizer/issues/65#issuecomment-1910968223)

1. `\?B1 ?x.?y... ↦ ?a.b`
    - Binding `B1` that matches with `?x.?y... -> ?a.b`, can be used futher as `?B1`

1. `?bar => \?b_bar ξ.ρ.?b_a.?foo`
    - In the current formation:
        1. Find a binding where a formation attached to an attribute `?bar` (not a concrete name) contains somewhere `ξ.ρ.?b_a.?foo`.
        1. Save the formation attached to `?bar` to the variable `?b_bar`

1. `?p1..?main`
    - Some path to `?main` (not a concrete name)
      1. If used in formation, it means an enclosure.
          - Example: `⟦ org ↦ ⟦ eolang ↦ ⟦ main ↦ ... ⟧ ⟧ ⟧`
      1. If used in an application, it means dispatches.
          - Example: `(x ↦ org.eolang.main)`

### Syntax v1

#### Observations

- `(3)` cannot be used without a right side (after `↦`) that helps understand when to stop searching.
- `(2)` is expressible via `(1)`
  - The attribute can be extracted via a function on bindings ([link](https://github.com/objectionary/normalizer/pull/259)).

#### Suggestions

Use the following syntax:

1. `\?A ?a.?b..c.?d..?e.f ↦ ⟦ ?B ⟧`
1. `\?C ?g..h.?i ↦ ?j.k(D).?l..?m.n`

What it does:

1. Finds a binding that matches `?a.?b..c.?d..?e.f ↦ ⟦ ?B ⟧` and saves it to the metavariable `?A`
1. Finds a binding that matches `?g..h.?i ↦ ?j.k(D).?l..?m.n` and saves it to the metavariable `?C`

This syntax allows:

- Optionally saving the full binding to a given metavariable (`?A`, `?C`)
- Matching individual path elements (`?a`, `c`, `?e`, `f`, `h`, `?i`)
- Matching a segment of the path (`?b..`, `?d..`, `?g..`)
- Matching an object on the right side (`⟦ ?C ⟧`, `?j.k(D).?l..?m.n`)
- Matching a segment of a path within a sequence of dispatches (`?l..`)

### Grammar

This is a grammar of [Syntax v1](#syntax-v1) in the [LBNF](https://bnfc.readthedocs.io/en/latest/lbnf.html)-like format.

Nonterminals in parentheses come from the currently used `PHI` grammar ([link](https://github.com/objectionary/normalizer/blob/17b23dfa447d5b3c0215e1fd5557593948024357/eo-phi-normalizer/grammar/EO/Phi/Syntax.cf)).

```lbnf
MetaDispatchPath. Attribute ::= MetaId "..";

MetaPath. MetaPath ::= Attribute ("." MetaPath)?

MetaBinding. Binding ::= ("\" <binding :: (MetaId)>)? <path :: (MetaPath)> "↦" <object :: (Object)>
```

Find a `<binding>` that has a `<path>` to a value after the `↦` that matches a given `<object>`.
When `<binding>` is given, the `<binding>` equals to the full binding - includes both the `<path>` and the `<object>`.

### Examples

```yaml
- pattern: '⟦ \?FullBinding ?Path..?Name ↦ ?Object.world(?Bindings) ⟧'
  input: "⟦ org ↦ ⟦ eolang ↦ ⟦ main ↦ hello.world(and ↦ you) ⟧ ⟧ ⟧"
  matches:
    - metavar: "?Path"
      value: ["org", "eolang"]
    - metavar: "?Name"
      value: "main"
    - metavar: "?Object"
      value: "hello"
    - metavar: "?Bindings"
      value: [and ↦ you]
    - metavar: "?FullBinding"
      value: [org ↦ ⟦ eolang ↦ ⟦ main ↦ hello.world(and ↦ you) ⟧ ⟧]
- pattern: '(\?FullBinding ?Name ↦ ?DispatchPath..?DispatchName.world)'
  input: "(x ↦ Φ.org.eolang.world, y ↦ Φ.org.eolang.work)"
  matches:
    - metavar: "?FullBinding"
      value: "x ↦ Φ.org.eolang.world"
    - metavar: "?Name"
      value: "x"
    - metavar: "?DispatchPath"
      value: ["Φ", "org"]
    - metavar: "?DispatchName"
      value: "eolang"
```

## Effect and Interactions

The proposed changes allow matching expressions deep within a program.

Matched expressions can be used for constructing new expressions.

This proposal implies metavariables are denoted via a question mark (`?`) rather than (`!`).
A question mark sounds a bit more appropriate because a metavariable has an unknown value before pattern matching.

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

# Proposals

A proposal is a document describing a proposed change to the Normalizer.

## Proposal format

- Proposals must follow the [template](./000-template.md).
  - This template resembles the [ghc-proposals template](https://github.com/ghc-proposals/ghc-proposals/blob/master/proposals/0000-template.md).
- Proposal file names must consist of an index, a title, and the `.md` extension.
  - Example: `001-pattern-matching-on-paths.md`.
- Pull request names must follow the format `[proposal] proposal_title`.
  - Example: `[proposal] Pattern matching on paths`.
- Proposals must go into the [proposals](./) directory.

## Proposal process

1. [No label] An author submits a proposal for discussion as a pull request against the `normalizer` repository ([link](https://github.com/objectionary/normalizer)).
1. [[proposal under review](https://github.com/objectionary/normalizer/labels/proposal%20under%20review)] The Normalizer team discusses the proposal in the commit section of the pull request, while the author refines the proposal. This phase lasts as long as necessary.
1. Eventually, the Normalizer team does one of these actions:
   1. Rejects the proposal [[proposal rejected](https://github.com/objectionary/normalizer/labels/proposal%20rejected)].
   1. Passes the proposal back to the author(s) for review [[proposal needs revision](https://github.com/objectionary/normalizer/labels/Proposal%20needs%20revision)].
   1. Accepts the proposal.
      - [[proposal accepted](https://github.com/objectionary/normalizer/labels/proposal%20accepted)]
      - Proposal priority - one of these labels:
        - [[proposal priority: high](https://github.com/objectionary/normalizer/labels/proposal%20priority%3A%20high)]
        - [[proposal priority: medium](https://github.com/objectionary/normalizer/labels/proposal%20priority%3A%20medium)]
        - [[proposal priority: low](https://github.com/objectionary/normalizer/labels/proposal%20priority%3A%20low)]
1. [[proposal implemented](https://github.com/objectionary/normalizer/labels/proposal%20implemented)] Once a proposal is accepted, it still has to be implemented. The author(s) may do that, or someone else. We mark the proposal implemented once it hits the `normalizer` master branch (and we are happy to be nudged to do so by email, GitHub issue, or a comment on the relevant pull request), and the corresponding documentation on the site is updated.
